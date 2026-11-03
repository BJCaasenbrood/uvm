function root = findRoot(startDir)
%FINDROOT  Nearest folder at or above STARTDIR that contains uvm.json ('' if none).

    folder = char(startDir);
    while true
        if isfile(fullfile(folder, 'uvm.json'))
            root = folder;
            return
        end
        parent = fileparts(folder);
        if isempty(parent) || strcmp(parent, folder)
            root = '';
            return
        end
        folder = parent;
    end
end
