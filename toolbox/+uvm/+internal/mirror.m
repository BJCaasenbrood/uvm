function mirrorDir = mirror(url, fetched, fetch)
%MIRROR  Local bare mirror of the git repository at URL, cloned on first use.
%   FETCH asks for an update from the remote. FETCHED is a containers.Map
%   (or []) recording which URLs were already fetched by the current
%   command, so each remote is contacted at most once per command.

    mirrorDir = fullfile(uvm.internal.home(), 'git', regexprep(url, '[^A-Za-z0-9._-]', '_'));
    if ~isfolder(mirrorDir)
        uvm.internal.say('Cloning %s', url);
        staging = uvm.internal.stagingFolder(mirrorDir);
        try
            uvm.internal.git('clone', '--mirror', '--quiet', url, staging);
        catch err
            if isfolder(staging)
                rmdir(staging, 's');
            end
            rethrow(err);
        end
        uvm.internal.commitFolder(staging, mirrorDir);
    elseif fetch && ~(~isempty(fetched) && fetched.isKey(url))
        uvm.internal.say('Fetching %s', url);
        uvm.internal.git('--git-dir', mirrorDir, 'fetch', '--prune', '--quiet', 'origin');
    else
        return
    end
    if ~isempty(fetched)
        fetched(url) = true; %#ok<NASGU> containers.Map is a handle
    end
end
