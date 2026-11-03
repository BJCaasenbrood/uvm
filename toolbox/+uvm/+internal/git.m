function [out, status] = git(varargin)
%GIT  Run git with the given arguments and return its standard output.
%   OUT = uvm.internal.git(ARGS...) errors when git fails.
%   [OUT, STATUS] = uvm.internal.git(ARGS...) returns the exit status instead.
%
%   uvm uses the git installed on the machine so that SSH keys, credential
%   helpers, proxies and company certificates work exactly as they do in a
%   terminal.

    errFile = [tempname '.txt'];
    cleanup = onCleanup(@() deleteIfExists(errFile));
    quoted = cellfun(@quote, varargin, 'UniformOutput', false);
    if ispc
        prefix = 'set GIT_TERMINAL_PROMPT=0&& git';
    else
        % MATLAB puts its own libcurl/libssl on the library path, which breaks
        % git's https transport, so git starts with a clean library path.
        prefix = 'env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH GIT_TERMINAL_PROMPT=0 git';
    end
    [status, out] = system(sprintf('%s %s 2>%s', prefix, strjoin(quoted, ' '), quote(errFile)));
    if status ~= 0 && nargout < 2
        message = '';
        if isfile(errFile)
            message = strtrim(fileread(errFile));
        end
        if status == 127 || contains(message, 'is not recognized')
            error('uvm:gitNotFound', 'git was not found. Install git and make sure it is on the PATH.');
        end
        error('uvm:gitFailed', 'git %s failed:\n%s', strjoin(varargin, ' '), message);
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
