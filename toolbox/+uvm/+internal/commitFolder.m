function commitFolder(staging, dest)
%COMMITFOLDER  Move a fully written STAGING folder into place as DEST.
%   Cache folders are written next to their destination under a unique name
%   (see uvm.internal.stagingFolder) and only then renamed, so a cache
%   folder is either complete or absent. If another MATLAB session created
%   DEST in the meantime, its copy is kept and STAGING is discarded; both
%   hold the same content.

    if isfolder(dest)
        rmdir(staging, 's');
        return
    end
    [ok, message] = movefile(staging, dest);
    if ~ok
        if isfolder(dest)
            rmdir(staging, 's');
        else
            error('uvm:writeFailed', 'Could not create %s: %s', dest, message);
        end
    end
end
