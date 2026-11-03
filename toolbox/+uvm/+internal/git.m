function [out, status] = git(varargin)
%GIT  Run git with the given arguments and return its standard output.
%   OUT = uvm.internal.git(ARGS...) errors when git fails.
%   [OUT, STATUS] = uvm.internal.git(ARGS...) returns the exit status instead.
%
%   uvm uses the git installed on the machine so that SSH keys, credential
%   helpers, proxies and company certificates work exactly as they do in a
%   terminal. MATLAB cannot answer prompts, so git runs with no input, no
%   pager, password prompts switched off, and (unless you configured your own ssh
%   command) ssh in batch mode, which fails instead of asking about an
%   unknown host key.

    errFile = [tempname '.txt'];
    cleanup = onCleanup(@() deleteIfExists(errFile));
    env = {'GIT_TERMINAL_PROMPT', '0'};
    ssh = batchSshCommand();
    if ~isempty(ssh)
        env(end + 1, :) = {'GIT_SSH_COMMAND', ssh};
    end
    % MATLAB runs commands in a pseudo-terminal, which makes git start a pager
    % that waits for a key press forever.
    args = strjoin(cellfun(@quote, [{'--no-pager'}, varargin], 'UniformOutput', false), ' ');
    if ispc
        prefix = strjoin(cellfun(@(k, v) sprintf('set "%s=%s"&& ', k, v), ...
            env(:, 1), env(:, 2), 'UniformOutput', false), '');
        command = sprintf('%sgit %s <NUL 2>%s', prefix, args, quote(errFile));
    else
        % MATLAB puts its own libcurl/libssl on the library path, which breaks
        % git's https transport, so git starts with a clean library path.
        assignments = strjoin(cellfun(@(k, v) [k '=' quote(v)], ...
            env(:, 1), env(:, 2), 'UniformOutput', false), ' ');
        command = sprintf('env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH %s git %s </dev/null 2>%s', ...
            assignments, args, quote(errFile));
    end
    [status, out] = system(command);
    if status ~= 0 && nargout < 2
        message = '';
        if isfile(errFile)
            message = strtrim(fileread(errFile));
        end
        if status == 127 || status == 9009 || contains(message, 'is not recognized')
            error('uvm:gitNotFound', 'git was not found. Install git and make sure it is on the PATH.');
        end
        error('uvm:gitFailed', 'git %s failed:\n%s%s', strjoin(varargin, ' '), message, hint(message));
    end
end

function command = batchSshCommand()
%BATCHSSHCOMMAND  ssh command for git, or '' to leave the user's own setup alone.
    persistent cached
    if isempty(cached)
        cached = {'ssh -o BatchMode=yes'};
        if ~isempty(getenv('GIT_SSH_COMMAND')) || ~isempty(getenv('GIT_SSH'))
            cached = {''};
        else
            if ispc
                probe = 'git config --get core.sshCommand <NUL';
            else
                probe = 'env -u LD_LIBRARY_PATH git config --get core.sshCommand </dev/null';
            end
            [probeStatus, configured] = system(probe);
            if probeStatus == 0 && ~isempty(strtrim(configured))
                cached = {''};
            end
        end
    end
    command = cached{1};
end

function text = hint(message)
    text = '';
    if contains(message, 'Host key verification failed')
        text = sprintf(['\n\nThe server''s SSH host key is not known yet. Connect once from a terminal ' ...
            '(for example "ssh -T git@your-server" or "git ls-remote URL") and accept the key.']);
    elseif contains(message, {'Permission denied', 'Authentication failed', 'could not read Username', ...
            'terminal prompts disabled'})
        text = sprintf(['\n\nuvm cannot answer login prompts. Make "git ls-remote URL" work in a terminal ' ...
            'without a prompt (load your SSH key into an agent, or store HTTPS credentials with a ' ...
            'credential helper), then try again.']);
    end
end

function s = quote(arg)
    if ispc
        s = ['"' strrep(arg, '"', '\"') '"'];
    else
        s = ['''' strrep(arg, '''', '''\''''') ''''];
    end
end

function deleteIfExists(file)
    if isfile(file)
        delete(file);
    end
end
