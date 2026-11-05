classdef InstallTest < matlab.unittest.TestCase
%INSTALLTEST  install_uvm against a local copy of this repository.
%   Installs into a temporary folder with a temporary startup.m, so the
%   user's path, startup.m and ~/.uvm are left alone.

    properties
        Work
        Source
        Folder
        StartupFile
        OldCommit
    end

    methods (TestMethodSetup)
        function prepare(tc)
            % Teardowns run in reverse order: restore the path before deleting the folders on it.
            tc.Work = tempname;
            mkdir(tc.Work);
            tc.addTeardown(@() rmdir(tc.Work, 's'));

            repoRoot = fullfile(fileparts(mfilename('fullpath')), '..');
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(repoRoot));   % for install_uvm
            savedPath = path;
            tc.addTeardown(@() path(savedPath));
            tc.addTeardown(@() clear('uvm'));
            tc.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture('UVM_HOME', fullfile(tc.Work, 'home')));

            % A source repository whose main branch can move on during a test.
            tc.Source = fullfile(tc.Work, 'source');
            git('clone', '--quiet', '--branch', 'main', repoRoot, tc.Source);
            tc.OldCommit = strtrim(git('-C', tc.Source, 'rev-parse', 'HEAD'));
            git('-C', tc.Source, 'tag', 'v0.0.1');

            tc.Folder = fullfile(tc.Work, 'installed');
            tc.StartupFile = fullfile(tc.Work, 'startup.m');
        end
    end

    methods (Test)
        function installUpdateAndUninstall(tc)
            evalc('install_uvm(Folder=tc.Folder, Source=tc.Source, StartupFile=tc.StartupFile)');
            tc.verifyEqual(which('uvm'), fullfile(tc.Folder, 'toolbox', 'uvm.m'));
            tc.verifyTrue(contains(fileread(tc.StartupFile), fullfile(tc.Folder, 'toolbox')));

            % A new commit upstream arrives with the next install_uvm.
            git('-C', tc.Source, '-c', 'user.name=t', '-c', 'user.email=t@example.com', ...
                'commit', '--quiet', '--allow-empty', '-m', 'upstream change');
            newCommit = strtrim(git('-C', tc.Source, 'rev-parse', 'HEAD'));
            evalc('install_uvm(Folder=tc.Folder, Source=tc.Source, StartupFile=tc.StartupFile)');
            tc.verifyEqual(strtrim(git('-C', tc.Folder, 'rev-parse', 'HEAD')), newCommit);

            % Installing an older tag goes back to it.
            evalc('install_uvm(Folder=tc.Folder, Source=tc.Source, Ref="v0.0.1", StartupFile=tc.StartupFile)');
            tc.verifyEqual(strtrim(git('-C', tc.Folder, 'rev-parse', 'HEAD')), tc.OldCommit);
            tc.verifyEqual(numel(strfind(fileread(tc.StartupFile), '% >>> uvm >>>')), 1);

            evalc('install_uvm(Folder=tc.Folder, Uninstall=true, StartupFile=tc.StartupFile)');
            tc.verifyFalse(isfolder(tc.Folder));
            tc.verifyFalse(contains(fileread(tc.StartupFile), 'uvm'));
            tc.verifyFalse(contains(path, fullfile(tc.Folder, 'toolbox')));
        end

        function withoutStartupHook(tc)
            evalc('install_uvm(Folder=tc.Folder, Source=tc.Source, Startup=false, StartupFile=tc.StartupFile)');
            tc.verifyEqual(which('uvm'), fullfile(tc.Folder, 'toolbox', 'uvm.m'));
            tc.verifyFalse(isfile(tc.StartupFile));
        end

        function refusesForeignFolder(tc)
            mkdir(tc.Folder);
            fid = fopen(fullfile(tc.Folder, 'notes.txt'), 'w');
            fclose(fid);
            tc.verifyError(@() install_uvm(Folder=tc.Folder, Source=tc.Source, Startup=false), ...
                'uvm:install:folderInUse');
            tc.verifyTrue(isfile(fullfile(tc.Folder, 'notes.txt')));
        end
    end
end

function out = git(varargin)
    quoted = cellfun(@(a) ['''' strrep(a, '''', '''\''''') ''''], varargin, 'UniformOutput', false);
    [status, out] = system(['env -u LD_LIBRARY_PATH git ' strjoin(quoted, ' ') ' 2>&1']);
    assert(status == 0, 'git failed: %s', out);
end
