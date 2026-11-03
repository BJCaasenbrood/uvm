classdef UvmTest < matlab.unittest.TestCase
%UVMTEST  End-to-end tests against local git repositories.
%   Every test gets a fresh UVM_HOME and project folder, so the user's real
%   cache and config are never touched.
%
%   Fixture repositories:
%     lib_a  tags v1.0.0, v1.1.0 (annotated), v2.0.0; lib_a_version() returns the version
%     lib_b  v0.1.0 needs lib_a ^1.0, v0.2.0 needs lib_a ^1.1
%     lib_c  no tags, branch main, code in src/
%     clash  defines lib_a_version() too
%     registry  index.json listing lib_a, lib_b and clash

    properties
        Fixtures
        Repos
        Project
    end

    methods (TestClassSetup)
        function addToolbox(tc)
            here = fileparts(mfilename('fullpath'));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(here, '..', 'toolbox')));
        end

        function createRepos(tc)
            tc.Fixtures = tempname;
            mkdir(tc.Fixtures);
            tc.addTeardown(@() rmdir(tc.Fixtures, 's'));

            a = tc.newRepo('lib_a');
            for v = {'1.0.0', '1.1.0', '2.0.0'}
                writeFile(fullfile(a, 'lib_a_version.m'), ...
                    sprintf('function v = lib_a_version()\nv = ''%s'';\nend\n', v{1}));
                commitAll(a);
                if strcmp(v{1}, '1.1.0')
                    gitIn(a, 'tag', '-a', ['v' v{1}], '-m', 'annotated');
                else
                    gitIn(a, 'tag', ['v' v{1}]);
                end
            end

            b = tc.newRepo('lib_b');
            writeFile(fullfile(b, 'lib_b_hello.m'), sprintf('function s = lib_b_hello()\ns = [''b uses '' lib_a_version()];\nend\n'));
            for step = {{'0.1.0', '^1.0'}, {'0.2.0', '^1.1'}}
                writeFile(fullfile(b, 'uvm.json'), sprintf( ...
                    '{"name": "lib_b", "version": "%s", "dependencies": {"lib_a": "%s"}}', step{1}{:}));
                commitAll(b);
                gitIn(b, 'tag', ['v' step{1}{1}]);
            end

            c = tc.newRepo('lib_c');
            mkdir(fullfile(c, 'src'));
            writeFile(fullfile(c, 'uvm.json'), '{"name": "lib_c", "paths": ["src"]}');
            writeFile(fullfile(c, 'src', 'lib_c_hello.m'), sprintf('function s = lib_c_hello()\ns = ''c'';\nend\n'));
            commitAll(c);

            clash = tc.newRepo('clash');
            writeFile(fullfile(clash, 'lib_a_version.m'), sprintf('function v = lib_a_version()\nv = ''clash'';\nend\n'));
            commitAll(clash);
            gitIn(clash, 'tag', 'v1.0.0');

            reg = tc.newRepo('registry');
            index = struct('packages', struct( ...
                'lib_a', struct('url', a), 'lib_b', struct('url', b), 'clash', struct('url', clash)));
            writeFile(fullfile(reg, 'index.json'), jsonencode(index));
            commitAll(reg);

            tc.Repos = struct('a', a, 'b', b, 'c', c, 'clash', clash, 'registry', reg);
        end
    end

    methods (TestMethodSetup)
        function freshProject(tc)
            work = tempname;
            mkdir(work);
            tc.addTeardown(@() rmdir(work, 's'));
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                'UVM_HOME', fullfile(work, 'home')));
            tc.Project = fullfile(work, 'project');
            mkdir(tc.Project);
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(tc.Project));
            tc.addTeardown(@() uvm.internal.deactivate(false));
            uvm('registry', 'add', 'test', tc.Repos.registry, '--quiet');
            uvm('init', '--quiet');
        end
    end

    methods (Test)
        function initWritesManifest(tc)
            m = jsondecode(fileread('uvm.json'));
            tc.verifyEqual(m.name, 'project');
            tc.verifyEqual(m.matlab, ['>=R' version('-release')]);
            tc.verifyError(@() uvm('init'), 'uvm:projectExists');
        end

        function addFromRegistryPinsLatest(tc)
            uvm add lib_a --quiet
            m = jsondecode(fileread('uvm.json'));
            tc.verifyEqual(m.dependencies.lib_a, '^2.0.0');
            tc.verifyEqual(lib_a_version(), '2.0.0');
            packages = uvm('list');
            tc.verifyEqual(packages.version, '2.0.0');
            tc.verifyEqual(packages.ref, 'v2.0.0');
        end

        function addWithConstraint(tc)
            uvm add lib_a@~1.0 --quiet
            tc.verifyEqual(lib_a_version(), '1.0.0');
            m = jsondecode(fileread('uvm.json'));
            tc.verifyEqual(m.dependencies.lib_a, '~1.0');
        end

        function annotatedTagResolvesToCommit(tc)
            uvm add lib_a@=1.1.0 --quiet
            tc.verifyEqual(lib_a_version(), '1.1.0');
        end

        function transitiveDependencies(tc)
            uvm add lib_b --quiet
            packages = uvm('list');
            tc.verifyEqual({packages.name}, {'lib_a', 'lib_b'});
            % lib_b 0.2.0 needs lib_a ^1.1, so 2.0.0 is out and 1.1.0 is the newest fit.
            tc.verifyEqual(packages(1).version, '1.1.0');
            tc.verifyEqual(lib_b_hello(), 'b uses 1.1.0');
        end

        function conflictingRequirementsFail(tc)
            uvm add lib_b --quiet
            tc.verifyError(@() uvm('add', 'lib_a@^2', '--quiet'), 'uvm:noVersion');
            % A failed add leaves the project as it was.
            m = jsondecode(fileread('uvm.json'));
            tc.verifyFalse(isfield(m.dependencies, 'lib_a'));
            tc.verifyEqual(lib_b_hello(), 'b uses 1.1.0');
        end

        function lockKeepsVersionsUntilUpgrade(tc)
            repo = fullfile(tc.Fixtures, 'moving');
            copyfile(tc.Repos.a, repo);
            tc.addTeardown(@() rmdir(repo, 's'));
            uvm('add', repo, '--version', '^1.0', '--name', 'moving', '--quiet');
            tc.verifyEqual(lib_a_version(), '1.1.0');

            writeFile(fullfile(repo, 'lib_a_version.m'), sprintf('function v = lib_a_version()\nv = ''1.2.0'';\nend\n'));
            commitAll(repo);
            gitIn(repo, 'tag', 'v1.2.0');

            uvm lock --quiet
            tc.verifyEqual(lib_a_version(), '1.1.0');
            uvm sync --upgrade --quiet
            tc.verifyEqual(lib_a_version(), '1.2.0');
        end

        function gitDependencyWithoutTagsFollowsBranch(tc)
            uvm('add', tc.Repos.c, '--quiet');
            m = jsondecode(fileread('uvm.json'));
            tc.verifyEqual(m.dependencies.lib_c, struct('git', tc.Repos.c, 'branch', 'main'));
            tc.verifyEqual(lib_c_hello(), 'c');
            packages = uvm('list');
            tc.verifyEqual(packages.kind, 'branch');
        end

        function removeAndDeactivate(tc)
            uvm add lib_a --quiet
            tc.verifyEqual(exist('lib_a_version', 'file'), 2);
            uvm deactivate --quiet
            tc.verifyEqual(exist('lib_a_version', 'file'), 0);
            uvm activate --quiet
            tc.verifyEqual(exist('lib_a_version', 'file'), 2);
            uvm remove lib_a --quiet
            tc.verifyEqual(exist('lib_a_version', 'file'), 0);
            tc.verifyEmpty(uvm('list'));
        end

        function activateWorksFromSubfolder(tc)
            uvm add lib_a --quiet
            uvm deactivate --quiet
            mkdir('analysis');
            cd('analysis');
            uvm activate --quiet
            tc.verifyEqual(lib_a_version(), '2.0.0');
        end

        function syncInstallsFromLockOnly(tc)
            uvm add lib_b --quiet
            lockBefore = fileread('uvm.lock');
            uvm deactivate --quiet
            uvm cache clean --quiet
            uvm sync --quiet
            tc.verifyEqual(fileread('uvm.lock'), lockBefore);
            tc.verifyEqual(lib_b_hello(), 'b uses 1.1.0');
        end

        function runScript(tc)
            uvm add lib_a --quiet
            writeFile('job.m', 'uvmTestResult = lib_a_version();');
            uvm run job.m --quiet
            tc.verifyEqual(evalin('base', 'uvmTestResult'), '2.0.0');
            evalin('base', 'clear uvmTestResult');
        end

        function shadowingIsReported(tc)
            uvm add lib_a --quiet
            tc.verifyWarning(@() uvm('add', 'clash', '--quiet'), 'uvm:shadowing');
        end

        function missingToolboxIsReported(tc)
            m = jsondecode(fileread('uvm.json'));
            m.toolboxes = {'Imaginary Toolbox'};
            uvm.internal.writeManifest('uvm.json', m);
            tc.verifyWarning(@() uvm('sync', '--quiet'), 'uvm:missingToolbox');
        end

        function unknownPackage(tc)
            tc.verifyError(@() uvm('add', 'nope', '--quiet'), 'uvm:unknownPackage');
        end

        function startupHook(tc)
            file = fullfile(tc.Project, 'startup_test.m');
            writeFile(file, sprintf('disp(''mine'');\n'));
            uvm('setup', '--file', file, '--quiet');
            uvm('setup', '--file', file, '--quiet');
            text = fileread(file);
            tc.verifyEqual(numel(strfind(text, '% >>> uvm >>>')), 1);
            tc.verifyTrue(startsWith(text, 'disp(''mine'');'));

            uvm add lib_a --quiet
            uvm deactivate --quiet
            run(file);
            tc.verifyEqual(lib_a_version(), '2.0.0');

            uvm('setup', '--remove', '--file', file, '--quiet');
            tc.verifyEqual(fileread(file), sprintf('disp(''mine'');\n'));
        end
    end

    methods (Test, TestTags = {'Unit'})
        function versionConstraints(tc)
            ok = @(v, c) uvm.internal.versionSatisfies(v, c);
            tc.verifyTrue(ok([1 4 0], '^1.2'));
            tc.verifyFalse(ok([2 0 0], '^1.2'));
            tc.verifyFalse(ok([1 1 9], '1.2'));
            tc.verifyTrue(ok([0 2 5], '^0.2.3'));
            tc.verifyFalse(ok([0 3 0], '^0.2.3'));
            tc.verifyFalse(ok([0 0 4], '^0.0.3'));
            tc.verifyTrue(ok([1 2 9], '~1.2.3'));
            tc.verifyFalse(ok([1 3 0], '~1.2.3'));
            tc.verifyTrue(ok([1 9 0], '~1'));
            tc.verifyTrue(ok([1 5 0], '>=1.2, <1.8'));
            tc.verifyFalse(ok([1 8 0], '>=1.2, <1.8'));
            tc.verifyTrue(ok([3 0 0], '*'));
            tc.verifyTrue(ok([1 4 1], '=1.4.1'));
            tc.verifyError(@() ok([1 0 0], '^banana'), 'uvm:badConstraint');
        end

        function versionParsing(tc)
            [v, n] = uvm.internal.versionParse('v1.2');
            tc.verifyEqual(v, [1 2 0]);
            tc.verifyEqual(n, 2);
            tc.verifyEmpty(uvm.internal.versionParse('v2.0.0-rc1'));
            tc.verifyEmpty(uvm.internal.versionParse('latest'));
        end

        function releaseConstraints(tc)
            ok = @(r, c) uvm.internal.releaseSatisfies(r, c);
            tc.verifyTrue(ok('2024a', '>=R2023a'));
            tc.verifyFalse(ok('2023a', '>=R2023b'));
            tc.verifyTrue(ok('2023b', 'R2023b'));
            tc.verifyFalse(ok('2025a', '>=R2022b, <R2025a'));
            tc.verifyTrue(ok('2024b', ''));
        end
    end

    methods (Access = private)
        function repo = newRepo(tc, name)
            repo = fullfile(tc.Fixtures, name);
            mkdir(repo);
            gitIn(repo, 'init', '--quiet', '-b', 'main');
        end
    end
end

function gitIn(repo, varargin)
    uvm.internal.git('-C', repo, '-c', 'user.name=uvm test', '-c', 'user.email=test@example.com', varargin{:});
end

function commitAll(repo)
    gitIn(repo, 'add', '-A');
    gitIn(repo, 'commit', '--quiet', '-m', 'update');
end

function writeFile(file, text)
    fid = fopen(file, 'w');
    fwrite(fid, text, 'char');
    fclose(fid);
end
