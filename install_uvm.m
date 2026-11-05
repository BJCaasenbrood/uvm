function install_uvm(options)
%INSTALL_UVM  Install, update or uninstall uvm.
%   INSTALL_UVM clones uvm into ~/.uvm/uvm (or $UVM_HOME/uvm), or updates an
%   existing installation there, puts it on the path, and adds the uvm hook
%   to startup.m so uvm is available in every MATLAB session. Run it again
%   at any time to update.
%
%   INSTALL_UVM(Name=Value) changes the defaults:
%     Folder      where to install uvm (default ~/.uvm/uvm)
%     Source      git URL or folder to install from
%                 (default https://github.com/BJCaasenbrood/uvm.git)
%     Ref         branch or tag to install (default main)
%     Startup     add the startup.m hook (default true)
%     StartupFile startup.m to change (default: the one uvm setup picks)
%     Uninstall   remove the startup.m hook, the path entry and the installed
%                 copy; your projects and the package cache stay (default false)
%
%   Requires MATLAB R2023a or newer and git on the system path. uvm uses
%   your own git, so a private repository installs with the same login that
%   works for "git clone" in a terminal.
%
%   Examples
%     install_uvm
%     install_uvm(Ref="v0.1.0")
%     install_uvm(Source="git@github.com:BJCaasenbrood/uvm.git")
%     install_uvm(Uninstall=true)

    arguments
        options.Folder (1,:) char = fullfile(uvmHome(), 'uvm')
        options.Source (1,:) char = 'https://github.com/BJCaasenbrood/uvm.git'
        options.Ref (1,:) char = 'main'
        options.Startup (1,1) logical = true
        options.StartupFile (1,:) char = ''
        options.Uninstall (1,1) logical = false
    end

    folder = options.Folder;
    toolbox = fullfile(folder, 'toolbox');
    if options.Uninstall
        uninstall(folder, toolbox, options.StartupFile);
        return
    end

    if isMATLABReleaseOlderThan('R2023a')
        error('uvm:install:release', 'uvm needs MATLAB R2023a or newer; this is R%s.', version('-release'));
    end
    [status, gitVersion] = git('--version');
    if status ~= 0
        error('uvm:install:noGit', ['git was not found. Install it from https://git-scm.com, make sure ' ...
            'it is on the system PATH, restart MATLAB and run install_uvm again.']);
    end
    fprintf('Using %s\n', strtrim(gitVersion));

    source = options.Source;
    if isfolder(source)
        listing = dir(source);
        source = listing(1).folder;   % absolute, so the clone does not depend on the current folder
    end

    if isfolder(fullfile(folder, '.git'))
        fprintf('Updating uvm in %s\n', folder);
        mustGit('-C', folder, 'fetch', '--quiet', '--tags', source, options.Ref);
        % Check out exactly what was asked for, which also allows going back to an
        % older tag. Fails, rather than overwriting, if files there were edited.
        [status, message] = git('-C', folder, 'checkout', '--quiet', '--detach', 'FETCH_HEAD');
        if status ~= 0
            error('uvm:install:update', 'Could not update %s:\n%s', folder, strtrim(message));
        end
    elseif isfolder(folder) && numel(dir(folder)) > 2
        error('uvm:install:folderInUse', ['%s exists but is not a uvm installation. ' ...
            'Remove it, or choose another folder with install_uvm(Folder=...).'], folder);
    else
        fprintf('Installing uvm into %s\n', folder);
        parent = fileparts(folder);
        if ~isfolder(parent)
            mkdir(parent);
        end
        mustGit('clone', '--quiet', '--branch', options.Ref, source, folder);
    end

    if ~isfile(fullfile(toolbox, 'uvm.m'))
        error('uvm:install:broken', '%s does not contain toolbox/uvm.m; check Source and Ref.', folder);
    end
    addpath(toolbox);
    rehash path
    if options.Startup
        setupArgs = {'setup'};
        if ~isempty(options.StartupFile)
            setupArgs = [setupArgs, {'--file', options.StartupFile}];
        end
        uvm(setupArgs{:});
    end
    fprintf('Installed uvm %s. Run "uvm doc getting_started" to begin.\n', uvm('version'));
end

function uninstall(folder, toolbox, startupFile)
    if exist('uvm', 'file') == 2
        uvm('deactivate', '--quiet');
        setupArgs = {'setup', '--remove'};
        if ~isempty(startupFile)
            setupArgs = [setupArgs, {'--file', startupFile}];
        end
        uvm(setupArgs{:});
    end
    if contains([pathsep path pathsep], [pathsep toolbox pathsep])
        rmpath(toolbox);
    end
    clear uvm
    if isfolder(folder)
        if ~isfile(fullfile(toolbox, 'uvm.m'))
            error('uvm:install:notUvm', 'Refusing to delete %s: it does not look like a uvm installation.', folder);
        end
        rmdir(folder, 's');
        fprintf('Removed %s\n', folder);
    end
    fprintf('uvm is uninstalled. Your projects and the package cache in %s are untouched.\n', uvmHome());
end

function folder = uvmHome()
    folder = getenv('UVM_HOME');
    if isempty(folder)
        if ispc
            folder = fullfile(getenv('USERPROFILE'), '.uvm');
        else
            folder = fullfile(getenv('HOME'), '.uvm');
        end
    end
end

function mustGit(varargin)
%MUSTGIT  Run git and stop with its message if it fails.
    [status, message] = git(varargin{:});
    if status ~= 0
        error('uvm:install:git', 'git %s failed:\n%s', strjoin(varargin, ' '), strtrim(message));
    end
end

function [status, out] = git(varargin)
%GIT  Run git without prompts, the same way uvm itself does (see uvm.internal.git):
%   no input, no pager, no password prompts, and ssh in batch mode unless
%   you configured your own ssh command.
    env = {'GIT_TERMINAL_PROMPT', '0'};
    if isempty(getenv('GIT_SSH_COMMAND')) && isempty(getenv('GIT_SSH')) && ~hasSshConfig()
        env(end + 1, :) = {'GIT_SSH_COMMAND', 'ssh -o BatchMode=yes'};
    end
    args = strjoin(cellfun(@quote, [{'--no-pager'}, varargin], 'UniformOutput', false), ' ');
    if ispc
        prefix = strjoin(cellfun(@(k, v) sprintf('set "%s=%s"&& ', k, v), ...
            env(:, 1), env(:, 2), 'UniformOutput', false), '');
        command = [prefix 'git ' args ' <NUL 2>&1'];
    else
        % MATLAB's own libcurl/libssl on the library path break git's https transport.
        assignments = strjoin(cellfun(@(k, v) [k '=' quote(v)], ...
            env(:, 1), env(:, 2), 'UniformOutput', false), ' ');
        command = ['env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH ' assignments ' git ' args ' </dev/null 2>&1'];
    end
    [status, out] = system(command);
end

function tf = hasSshConfig()
    if ispc
        [status, out] = system('git config --get core.sshCommand <NUL');
    else
        [status, out] = system('env -u LD_LIBRARY_PATH git config --get core.sshCommand </dev/null');
    end
    tf = status == 0 && ~isempty(strtrim(out));
end

function s = quote(arg)
    if ispc
        s = ['"' strrep(arg, '"', '\"') '"'];
    else
        s = ['''' strrep(arg, '''', '''\''''') ''''];
    end
end
