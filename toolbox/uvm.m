function varargout = uvm(command, varargin)
%UVM  Project and package manager for MATLAB.
%
%   Projects
%     uvm init [--name NAME]         Create uvm.json in the current folder
%     uvm add NAME[@SPEC]            Add a dependency from a registry, e.g. uvm add signal_utils@^1.2
%     uvm add URL [--tag T | --branch B | --rev R | --version SPEC] [--name NAME]
%                                    Add a dependency straight from a git repository
%     uvm remove NAME                Remove a dependency
%     uvm lock [--upgrade]           Resolve dependencies and write uvm.lock
%     uvm sync [--upgrade]           Lock if needed, install, and activate the project
%     uvm list                       Show locked packages; P = uvm("list") returns them
%     uvm run SCRIPT                 Sync, then run SCRIPT in the base workspace
%     uvm activate [FOLDER]          Put the project's packages on the path
%     uvm deactivate                 Take them off again
%
%   Configuration
%     uvm registry add NAME URL      Register a package index (a git repo with index.json)
%     uvm registry remove NAME
%     uvm registry list
%     uvm cache dir | clean          Show or delete the package cache
%     uvm setup [--remove] [--file F]  Add the startup.m hook that activates projects
%     uvm version
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
            lockProject(uvm.internal.loadProject(pwd), opts.upgrade, true);
        case 'sync'
            opts = uvm.internal.parseArgs(args, {'--upgrade'}, {});
            syncProject(uvm.internal.loadProject(pwd), opts.upgrade);
        case 'list'
            packages = cmdList(nargout > 0);
            if nargout > 0
                varargout{1} = packages;
            end
        case 'run'
            cmdRun(args);
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
        case 'version'
            if nargout > 0
                varargout{1} = uvm.internal.toolVersion();
            else
                fprintf('uvm %s\n', uvm.internal.toolVersion());
            end
        case {'help', '--help', '-h'}
            help uvm
        otherwise
            error('uvm:unknownCommand', 'Unknown command "%s". Run "help uvm" for usage.', command);
    end
end

function cmdInit(args)
    opts = uvm.internal.parseArgs(args, {}, {'--name'});
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
        lock = lockProject(project, false, false);
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
        syncProject(project, false);
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
    syncProject(uvm.internal.loadProject(project.root), false);
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
    fprintf('%-20s %-12s %-10s %s\n', 'Package', 'Version', 'Commit', 'Source');
    for p = packages(:)'
        label = p.version;
        if ~strcmp(p.kind, 'semver')
            label = sprintf('%s:%s', p.kind, p.ref);
        end
        fprintf('%-20s %-12s %-10s %s\n', p.name, label, p.commit(1:min(8, end)), p.source);
    end
end

function cmdRun(args)
    [~, positional] = uvm.internal.parseArgs(args, {}, {});
    if numel(positional) ~= 1
        error('uvm:badArgs', 'Usage: uvm run SCRIPT');
    end
    script = positional{1};
    if ~isfile(script) && isfile([script '.m'])
        script = [script '.m'];
    end
    if ~isfile(script)
        error('uvm:noScript', 'Script "%s" not found.', positional{1});
    end
    script = uvm.internal.absoluteSource(script, pwd);
    syncProject(uvm.internal.loadProject(pwd), false);
    evalin('base', sprintf('run(''%s'');', strrep(script, '''', '''''')));
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

function lock = lockProject(project, upgrade, force)
%LOCKPROJECT  Return an up-to-date lock, resolving only when the manifest changed.
    previous = uvm.internal.readLock(project.lockFile);
    if ~force && ~upgrade && ~isempty(previous) && ...
            strcmp(jsonencode(previous.requires), jsonencode(project.manifest.dependencies))
        lock = previous;
        return
    end
    lock = uvm.internal.resolve(project, previous, upgrade);
    uvm.internal.writeLock(project.lockFile, lock);
    uvm.internal.say('Resolved %d package(s)', numel(lock.packages));
end

function syncProject(project, upgrade)
    lock = lockProject(project, upgrade, false);
    uvm.internal.install(project, lock);
    uvm.internal.checkEnvironment(project, lock);
    uvm.internal.activate(project.root);
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
