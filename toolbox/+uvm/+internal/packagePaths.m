function folders = packagePaths(base, relative, owner)
%PACKAGEPATHS  Absolute path entries for the "paths" of a package rooted at BASE.

    folders = cell(1, numel(relative));
    for i = 1:numel(relative)
        rel = strrep(relative{i}, '\', '/');
        if any(strcmp(strsplit(rel, '/'), '..')) || startsWith(rel, '/')
            error('uvm:badManifest', 'Path "%s" of %s must stay inside the package.', relative{i}, owner);
        end
        if isempty(rel) || strcmp(rel, '.')
            folders{i} = base;
        else
            folders{i} = fullfile(base, rel);
        end
    end
end
