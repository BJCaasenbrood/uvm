function install(project, lock)
%INSTALL  Make sure every locked package is in the cache and record the path.
%   Writes PROJECT/.uvm/paths.txt, the list of folders that
%   uvm.internal.activate puts on the MATLAB path.

    entries = uvm.internal.packagePaths(project.root, project.manifest.paths, project.manifest.name);
    installed = 0;
    for p = lock.packages(:)'
        dest = uvm.internal.packageDir(p);
        if ~isfolder(dest)
            extract(p, dest);
            installed = installed + 1;
        end
        entries = [entries, uvm.internal.packagePaths(dest, p.paths, p.name)]; %#ok<AGROW>
    end
    if installed > 0
        uvm.internal.say('Installed %d package(s)', installed);
    end

    stateDir = fullfile(project.root, '.uvm');
    if ~isfolder(stateDir)
        mkdir(stateDir);
    end
    writeText(fullfile(stateDir, '.gitignore'), sprintf('# Created by uvm; nothing in here belongs in version control.\n*\n'));
    writeText(fullfile(stateDir, 'paths.txt'), sprintf('%s\n', entries{:}));
end

function extract(p, dest)
    mirrorDir = uvm.internal.mirror(p.source, [], false);
    if isempty(uvm.internal.revParse(mirrorDir, p.commit))
        mirrorDir = uvm.internal.mirror(p.source, [], true);
        if isempty(uvm.internal.revParse(mirrorDir, p.commit))
            error('uvm:missingCommit', 'Commit %s of "%s" no longer exists in %s. Run "uvm lock --upgrade".', ...
                p.commit, p.name, p.source);
        end
    end
    parent = fileparts(dest);
    if ~isfolder(parent)
        mkdir(parent);
    end
    partial = [dest '.partial'];
    if isfolder(partial)
        rmdir(partial, 's');
    end
    archive = [tempname '.zip'];
    cleanup = onCleanup(@() deleteIfExists(archive));
    uvm.internal.git('--git-dir', mirrorDir, 'archive', '--format=zip', '-o', archive, p.commit);
    mkdir(partial);
    unzip(archive, partial);
    movefile(partial, dest);
end

function writeText(file, text)
    fid = fopen(file, 'w', 'n', 'UTF-8');
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

function deleteIfExists(file)
    if isfile(file)
        delete(file);
    end
end
