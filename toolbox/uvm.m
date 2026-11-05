function varargout = uvm(command, varargin)
%UVM  Project and package manager for MATLAB.
%
%   Projects
%     uvm init [--name NAME] [--project]  Create uvm.json in the current folder
%     uvm add NAME[@SPEC]            Add a dependency from a registry, e.g. uvm add signal_utils@^1.2
%     uvm add URL [--tag T | --branch B | --rev R | --version SPEC] [--name NAME]
%                                    Add a dependency straight from a git repository
%     uvm remove NAME                Remove a dependency
%     uvm lock [--upgrade]           Resolve dependencies and write uvm.lock
%     uvm sync [--upgrade | --frozen]  Lock if needed, install, and activate the project
%     uvm list                       Show locked packages; P = uvm("list") returns them
%     uvm run SCRIPT [--frozen]      Sync, then run SCRIPT in the base workspace
%     uvm test [FOLDER] [--frozen] [--junit FILE]
%                                    Sync, then run the tests (default: the tests folder)
%     uvm activate [FOLDER]          Put the project's packages on the path
%     uvm deactivate                 Take them off again
%     uvm project [--remove]         Sync and activate whenever the MATLAB project opens
%
%   --frozen never changes uvm.lock and fails if it does not match uvm.json;
%   use it in CI, e.g.  matlab -batch "uvm test --frozen --junit results.xml"
%
%   Configuration
%     uvm registry add NAME URL      Register a package index (a git repo with index.json)
%     uvm registry remove NAME
%     uvm registry list
%     uvm cache dir | clean          Show or delete the package cache
%     uvm setup [--remove] [--file F]  Add the startup.m hook that activates projects
%     uvm doc [PAGE]                 Open the documentation
%     uvm version                    Show the uvm and git versions
%
%   Any command accepts --quiet to suppress progress messages.
%
%   Version specs: ^1.2 (>=1.2.0 <2.0.0, also the meaning of a bare 1.2),
%   ~1.2 (>=1.2.0 <1.3.0), >=1.0, <2, =1.4.1, * and comma-separated
%   combinations such as ">=1.2, <1.8".
%
%   Packages and registries are plain git repositories, so a git server at
%   work (GitLab, Bitbucket, Gitea, ...) is all the infrastructure needed.
%   Set the UVM_HOME environment variable to move the cache and config away
%   from ~/.uvm.
%
%   Documentation: <a href="matlab:uvm doc">uvm doc</a>, or
%   <a href="matlab:uvm doc getting_started">Getting Started</a>.

    if nargin < 1
        help uvm
        return
    end
    command = char(command);
    args = cellfun(@char, varargin, 'UniformOutput', false);
    quiet = any(strcmp(args, '--quiet'));
    args(strcmp(args, '--quiet')) = [];
    previousQuiet = uvm.internal.say('quiet', quiet);
    restoreQuiet = onCleanup(@() uvm.internal.say('quiet', previousQuiet));

    switch command
        case 'init'
            cmdInit(args);
        case 'add'
            cmdAdd(args);
        case 'remove'
            cmdRemove(args);
        case 'lock'
            opts = uvm.internal.parseArgs(args, {'--upgrade'}, {});
            uvm.internal.lockProject(uvm.internal.loadProject(pwd), opts.upgrade, true, false);
        case 'sync'
            opts = uvm.internal.parseArgs(args, {'--upgrade', '--frozen'}, {});
            if opts.upgrade && opts.frozen
                error('uvm:badArgs', '--upgrade and --frozen cannot be combined.');
            end
            uvm.internal.syncProject(uvm.internal.loadProject(pwd), opts.upgrade, opts.frozen);
        case 'list'
            packages = cmdList(nargout > 0);
            if nargout > 0
                varargout{1} = packages;
            end
        case 'run'
            cmdRun(args);
        case 'test'
            results = cmdTest(args);
            if nargout > 0
                varargout{1} = results;
            elseif any([results.Failed]) || any([results.Incomplete])
                % An error makes "matlab -batch" exit with a non-zero status for CI.
                error('uvm:testsFailed', '%d of %d tests did not pass.', ...
                    nnz([results.Failed] | [results.Incomplete]), numel(results));
            end
        case 'project'
            opts = uvm.internal.parseArgs(args, {'--remove'}, {});
            project = uvm.internal.loadProject(pwd);
            uvm.internal.connectMatlabProject(project, opts.remove);
            if ~opts.remove
                uvm.internal.syncProject(project, false, false);
            end
        case 'activate'
            cmdActivate(args, quiet);
        case 'deactivate'
            uvm.internal.deactivate(true);
        case 'registry'
            registries = cmdRegistry(args, nargout > 0);
            if nargout > 0
                varargout{1} = registries;
            end
        case 'cache'
            folder = cmdCache(args, nargout > 0);
            if nargout > 0
                varargout{1} = folder;
            end
        case 'setup'
            opts = uvm.internal.parseArgs(args, {'--remove'}, {'--file'});
            uvm.internal.setupStartup(opts.file, opts.remove);
        case 'doc'
            cmdDoc(args);
        case 'version'
            if nargout > 0
                varargout{1} = uvm.internal.toolVersion();
            else
                fprintf('uvm %s\n', uvm.internal.toolVersion());
                [gitVersion, status] = uvm.internal.git('--version');
                if status == 0
                    fprintf('%s\n', strtrim(gitVersion));
                else
                    fprintf('git not found; install it and make sure it is on the PATH.\n');
                end
            end
        case {'help', '--help', '-h'}
            help uvm
        otherwise
            error('uvm:unknownCommand', 'Unknown command "%s". Run "help uvm" for usage.', command);
    end
end

function cmdInit(args)
    opts = uvm.internal.parseArgs(args, {'--project'}, {'--name'});
    root = pwd;
    file = fullfile(root, 'uvm.json');
    if isfile(file)
        error('uvm:projectExists', 'uvm.json already exists in %s.', root);
    end
    name = opts.name;
    if isempty(name)
        [~, folderName] = fileparts(root);
        name = matlab.lang.makeValidName(folderName);
    end
    manifest = struct('name', name, 'version', '0.1.0', ...
        'matlab', ['>=R' version('-release')], 'toolboxes', {{}}, ...
        'paths', {{'.'}}, 'dependencies', struct());
    uvm.internal.writeManifest(file, manifest);
    uvm.internal.say('Initialized project "%s" in %s', name, root);
    if opts.project
        project = uvm.internal.loadProject(root);
        uvm.internal.connectMatlabProject(project, false);
        uvm.internal.syncProject(project, false, false);
    end
end

function cmdAdd(args)
    [opts, positional] = uvm.internal.parseArgs(args, {}, ...
        {'--tag', '--branch', '--rev', '--version', '--name'});
    if numel(positional) ~= 1
        error('uvm:badArgs', 'Usage: uvm add NAME[@SPEC]  or  uvm add URL [--tag T | --branch B | --rev R]');
    end
    target = positional{1};
    project = uvm.internal.loadProject(pwd);

    pins = {'tag', 'branch', 'rev'};
    given = pins(~cellfun(@(p) isempty(opts.(p)), pins));
    if numel(given) > 1
        error('uvm:badArgs', 'Use only one of --tag, --branch and --rev.');
    end

    % autoSpec: no version given, so pin to ^<resolved version> afterwards.
    autoSpec = false;
    if isGitSource(target)
        url = uvm.internal.absoluteSource(target, pwd);
        name = opts.name;
        if isempty(name)
            name = nameFromUrl(url);
        end
        spec = struct('git', url);
        if ~isempty(given)
            spec.(given{1}) = opts.(given{1});
        elseif ~isempty(opts.version)
            spec.version = opts.version;
        else
            mirrorDir = uvm.internal.mirror(url, [], true);
            if isempty(uvm.internal.listTags(mirrorDir))
                % Without version tags the best we can do is follow the default branch.
                spec.branch = uvm.internal.defaultBranch(mirrorDir);
            else
                autoSpec = true;
            end
        end
    else
        [name, spec] = strtok(target, '@');
        spec = strtrim(spec(2:end));
        if ~isvarname(name)
            error('uvm:badArgs', '"%s" is neither a package name (letters, digits, _) nor a git URL.', target);
        end
        if ~isempty(given)
            error('uvm:badArgs', '--%s only applies to git URLs.', given{1});
        end
        if ~isempty(opts.version)
            spec = opts.version;
        end
        if isempty(spec)
            spec = '*';
            autoSpec = true;
        end
    end
    if ~isvarname(name)
        error('uvm:badArgs', '"%s" is not a valid package name; pass --name.', name);
    end

    manifestBackup = fileread(project.manifestFile);
    lockBackup = '';
    if isfile(project.lockFile)
        lockBackup = fileread(project.lockFile);
    end
    try
        project = setDependency(project, name, spec);
        lock = uvm.internal.lockProject(project, false, false, false);
        if autoSpec
            package = lock.packages(strcmp({lock.packages.name}, name));
            if strcmp(package.kind, 'semver') && ~isempty(package.version)
                constraint = ['^' package.version];
                if isstruct(spec)
                    spec.version = constraint;
                else
                    spec = constraint;
                end
                project = setDependency(project, name, spec);
                lock.requires = project.manifest.dependencies;
                uvm.internal.writeLock(project.lockFile, lock);
            end
        end
        uvm.internal.syncProject(project, false, false);
    catch err
        restoreFile(project.manifestFile, manifestBackup);
        restoreFile(project.lockFile, lockBackup);
        rethrow(err);
    end
    uvm.internal.say('Added %s', name);
end

function cmdRemove(args)
    [~, positional] = uvm.internal.parseArgs(args, {}, {});
    if numel(positional) ~= 1
        error('uvm:badArgs', 'Usage: uvm remove NAME');
    end
    name = positional{1};
    project = uvm.internal.loadProject(pwd);
    raw = project.raw;
    if ~isfield(raw, 'dependencies') || ~isstruct(raw.dependencies) || ~isfield(raw.dependencies, name)
        error('uvm:notADependency', '"%s" is not a dependency of this project.', name);
    end
    raw.dependencies = rmfield(raw.dependencies, name);
    uvm.internal.writeManifest(project.manifestFile, raw);
    uvm.internal.syncProject(uvm.internal.loadProject(project.root), false, false);
    uvm.internal.say('Removed %s', name);
end

function packages = cmdList(returnOnly)
    project = uvm.internal.loadProject(pwd);
    lock = uvm.internal.readLock(project.lockFile);
    if isempty(lock)
        error('uvm:notLocked', 'No uvm.lock yet. Run "uvm sync" first.');
    end
    packages = lock.packages;
    if returnOnly
        return
    end
    if isempty(packages)
        fprintf('No dependencies.\n');
        return
    end
    fprintf('%-20s %-16s %-10s %s\n', 'Package', 'Version', 'Commit', 'Source');
    for p = packages(:)'
        label = p.version;
        if ~strcmp(p.kind, 'semver')
            label = sprintf('%s:%s', p.kind, p.ref);
        end
        fprintf('%-20s %-16s %-10s %s\n', p.name, label, p.commit(1:min(8, end)), p.source);
    end
end

function cmdRun(args)
    [opts, positional] = uvm.internal.parseArgs(args, {'--frozen'}, {});
    if numel(positional) ~= 1
        error('uvm:badArgs', 'Usage: uvm run SCRIPT [--frozen]');
    end
    script = positional{1};
    if ~isfile(script) && isfile([script '.m'])
        script = [script '.m'];
    end
    if ~isfile(script)
        error('uvm:noScript', 'Script "%s" not found.', positional{1});
    end
    script = uvm.internal.absoluteSource(script, pwd);
    uvm.internal.syncProject(uvm.internal.loadProject(pwd), false, opts.frozen);
    evalin('base', sprintf('run(''%s'');', strrep(script, '''', '''''')));
end

function results = cmdTest(args)
    [opts, positional] = uvm.internal.parseArgs(args, {'--frozen'}, {'--junit'});
    if numel(positional) > 1
        error('uvm:badArgs', 'Usage: uvm test [FOLDER] [--frozen] [--junit FILE]');
    end
    project = uvm.internal.loadProject(pwd);
    uvm.internal.syncProject(project, false, opts.frozen);
    target = '';
    if ~isempty(positional)
        target = uvm.internal.absoluteSource(positional{1}, pwd);
    end
    junit = '';
    if ~isempty(opts.junit)
        junit = fullfile(pwd, opts.junit);
        if startsWith(opts.junit, {'/', '\'}) || ~isempty(regexp(opts.junit, '^[A-Za-z]:', 'once'))
            junit = opts.junit;
        end
    end
    results = uvm.internal.runTests(project, target, junit);
end

function cmdActivate(args, quiet)
    [~, positional] = uvm.internal.parseArgs(args, {}, {});
    folder = pwd;
    if ~isempty(positional)
        folder = positional{1};
    end
    root = uvm.internal.findRoot(folder);
    if isempty(root)
        if quiet
            return
        end
        error('uvm:noProject', 'No uvm.json found in "%s" or its parents.', folder);
    end
    uvm.internal.activate(root);
end

function result = cmdRegistry(args, returnOnly)
    if isempty(args)
        args = {'list'};
    end
    cfg = uvm.internal.config();
    result = cfg.registries;
    switch args{1}
        case 'add'
            if numel(args) ~= 3
                error('uvm:badArgs', 'Usage: uvm registry add NAME URL');
            end
            url = uvm.internal.absoluteSource(args{3}, pwd);
            idx = find(strcmp({cfg.registries.name}, args{2}), 1);
            if isempty(idx)
                idx = numel(cfg.registries) + 1;
            end
            cfg.registries(idx, 1).name = args{2};
            cfg.registries(idx, 1).url = url;
            uvm.internal.config(cfg);
            uvm.internal.say('Registry "%s" -> %s', args{2}, url);
        case 'remove'
            if numel(args) ~= 2
                error('uvm:badArgs', 'Usage: uvm registry remove NAME');
            end
            keep = ~strcmp({cfg.registries.name}, args{2});
            if all(keep)
                error('uvm:noRegistry', 'No registry named "%s".', args{2});
            end
            cfg.registries = cfg.registries(keep);
            uvm.internal.config(cfg);
            uvm.internal.say('Removed registry "%s"', args{2});
        case 'list'
            if returnOnly
                return
            end
            if isempty(cfg.registries)
                fprintf('No registries configured. Add one with "uvm registry add NAME URL".\n');
            end
            for r = cfg.registries(:)'
                fprintf('%-12s %s\n', r.name, r.url);
            end
        otherwise
            error('uvm:badArgs', 'Usage: uvm registry add|remove|list');
    end
    result = cfg.registries;
end

function folder = cmdCache(args, returnOnly)
    folder = uvm.internal.home();
    if isempty(args)
        args = {'dir'};
    end
    switch args{1}
        case 'dir'
            if ~returnOnly
                fprintf('%s\n', folder);
            end
        case 'clean'
            uvm.internal.deactivate(false);
            for sub = {'git', 'pkgs'}
                target = fullfile(folder, sub{1});
                if isfolder(target)
                    rmdir(target, 's');
                end
            end
            uvm.internal.say('Cleaned %s', folder);
        otherwise
            error('uvm:badArgs', 'Usage: uvm cache dir|clean');
    end
end

function cmdDoc(args)
    page = 'index';
    if ~isempty(args)
        page = regexprep(args{1}, '\.html$', '');
    end
    file = fullfile(fileparts(mfilename('fullpath')), 'doc', [page '.html']);
    if ~isfile(file)
        error('uvm:noDocPage', 'No documentation page "%s". Run "uvm doc" for the contents.', page);
    end
    web(file);
end

function project = setDependency(project, name, spec)
    raw = project.raw;
    deps = uvm.internal.fieldOr(raw, 'dependencies', struct());
    if isempty(deps)
        deps = struct();
    end
    deps.(name) = spec;
    raw.dependencies = deps;
    uvm.internal.writeManifest(project.manifestFile, raw);
    project = uvm.internal.loadProject(project.root);
end

function tf = isGitSource(target)
    tf = contains(target, '://') || isfolder(target) || endsWith(target, '.git') || ...
        ~isempty(regexp(target, '^[\w.-]+@[\w.-]+:', 'once'));
end

function name = nameFromUrl(url)
    url = regexprep(url, '[\\/]+$', '');
    url = regexprep(url, '\.git$', '');
    parts = regexp(url, '[\\/:]', 'split');
    name = matlab.lang.makeValidName(parts{end});
end

function restoreFile(file, text)
    if isempty(text)
        if isfile(file)
            delete(file);
        end
        return
    end
    fid = fopen(file, 'w', 'n', 'UTF-8');
    fwrite(fid, text, 'char');
    fclose(fid);
end
