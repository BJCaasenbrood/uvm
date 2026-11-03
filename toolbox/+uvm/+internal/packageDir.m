function folder = packageDir(pkg)
%PACKAGEDIR  Cache folder holding the installed files of a locked package.
%   Installs are keyed by commit, so projects using the same commit share
%   one copy and an installed folder never changes.

    folder = fullfile(uvm.internal.home(), 'pkgs', pkg.name, pkg.commit(1:min(12, end)));
end
