function folders = packagePaths(base, relative, owner)
%PACKAGEPATHS  Absolute path entries for the "paths" of a package rooted at BASE.
%   Each entry is a folder relative to the package root. 'folder/**' adds
%   the folder and all its subfolders, and '**' does that for the root.
%   Like genpath, recursion skips private, @class and +namespace folders,
%   which MATLAB finds on its own, and also hidden folders such as .git.

    folders = {};
    for i = 1:numel(relative)
        rel = strrep(relative{i}, '\', '/');
        recursive = strcmp(rel, '**') || endsWith(rel, '/**');
        if recursive
            rel = regexprep(rel, '/?\*\*$', '');
        end
        if any(strcmp(strsplit(rel, '/'), '..')) || startsWith(rel, '/') || contains(rel, '*')
            error('uvm:badManifest', 'Path "%s" of %s must be a folder inside the package.', relative{i}, owner);
        end
        if isempty(rel) || strcmp(rel, '.')
            folder = base;
        else
            folder = fullfile(base, rel);
        end
        if ~recursive || ~isfolder(folder)
            folders{end + 1} = folder; %#ok<AGROW>
            continue
        end
        tree = strsplit(genpath(folder), pathsep);
        tree = tree(~cellfun(@isempty, tree));
        % Only look below FOLDER: the cache itself lives under ~/.uvm.
        inside = cellfun(@(f) f(numel(folder) + 1:end), tree, 'UniformOutput', false);
        tree = tree(~contains(inside, [filesep '.']));
        folders = [folders, tree]; %#ok<AGROW>
    end
end
