function projectOpened(root)
%PROJECTOPENED  Startup hook of a MATLAB project connected with "uvm project".
%   Syncs (normally just a check against uvm.lock; the network is only used
%   when packages are missing or uvm.json changed, e.g. after "git pull") and
%   activates. Problems become warnings so the project always opens.

    try
        uvm.internal.syncProject(uvm.internal.loadProject(root), false, false);
    catch err
        warning('uvm:projectSyncFailed', 'Could not sync %s: %s', root, err.message);
    end
end
