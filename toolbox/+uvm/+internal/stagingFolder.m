function staging = stagingFolder(dest)
%STAGINGFOLDER  Unique not-yet-existing folder name next to DEST.
%   Unique per call, so concurrent MATLAB sessions never write into the same
%   folder. Finish with uvm.internal.commitFolder(STAGING, DEST).

    parent = fileparts(dest);
    if ~isfolder(parent)
        mkdir(parent);
    end
    [~, id] = fileparts(tempname);
    staging = [dest '.partial-' id];
end
