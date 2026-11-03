function activate(root)
%ACTIVATE  Put the synced packages of the project at ROOT on the MATLAB path.
%   Only reads ROOT/.uvm/paths.txt, so it is fast enough for startup.m and
%   never touches the network. Any previously active project is deactivated.

    uvm.internal.deactivate(false);
    pathsFile = fullfile(root, '.uvm', 'paths.txt');
    if ~isfile(pathsFile)
        warning('uvm:notSynced', 'Project %s is not synced yet. Run "uvm sync".', root);
        return
    end
    entries = splitlines(strtrim(fileread(pathsFile)))';
    entries = entries(~cellfun(@isempty, entries));
    present = cellfun(@isfolder, entries);
    if ~all(present)
        warning('uvm:notSynced', 'Some packages of %s are not installed. Run "uvm sync".', root);
    end
    entries = entries(present);
    if ~isempty(entries)
        addpath(entries{:});
    end
    setappdata(groot, 'uvm_active', struct('root', root, 'paths', {entries}));

    synced = dir(pathsFile);
    for f = {'uvm.json', 'uvm.lock'}
        info = dir(fullfile(root, f{1}));
        if ~isempty(info) && info.datenum > synced.datenum
            warning('uvm:stale', '%s changed since the last sync. Run "uvm sync".', f{1});
            break
        end
    end
    uvm.internal.say('Activated %s (%d path entries)', root, numel(entries));
end
