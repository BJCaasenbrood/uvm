function connectMatlabProject(project, remove)
%CONNECTMATLABPROJECT  Hook the uvm project into a MATLAB project (.prj).
%   Adds a startup file that syncs and activates the uvm project whenever
%   the MATLAB project opens, and a shutdown file that deactivates it when
%   the project closes. Creates a MATLAB project in the project root if
%   there is none. With REMOVE, takes the hooks out again.
%
%   The hook files live in resources/uvm/ and belong in version control,
%   so everyone who opens the project gets the same behavior.

    hookDir = fullfile(project.root, 'resources', 'uvm');
    startupFile = fullfile(hookDir, 'uvm_project_startup.m');
    shutdownFile = fullfile(hookDir, 'uvm_project_shutdown.m');

    proj = openProjectAt(project.root, project.manifest.name, ~remove);
    if remove
        if ~isempty(proj)
            if any(proj.StartupFiles == startupFile)
                removeStartupFile(proj, startupFile);
            end
            if any(proj.ShutdownFiles == shutdownFile)
                removeShutdownFile(proj, shutdownFile);
            end
            for f = {startupFile, shutdownFile}
                if ~isempty(findFile(proj, f{1}))
                    removeFile(proj, f{1});
                end
            end
        end
        if isfolder(hookDir)
            rmdir(hookDir, 's');
        end
        uvm.internal.say('Disconnected %s from its MATLAB project', project.root);
        return
    end

    if ~isfolder(hookDir)
        mkdir(hookDir);
    end
    writeText(startupFile, strjoin({
        '% Runs when this MATLAB project opens; created by "uvm project".'
        '% Brings the packages in line with uvm.lock and puts them on the path.'
        'if exist(''uvm'', ''file'') == 2'
        '    uvm.internal.projectOpened(fileparts(fileparts(fileparts(mfilename(''fullpath'')))));'
        'else'
        '    warning(''uvm:notInstalled'', ''This project uses uvm, but uvm is not on the path.'');'
        'end'
        ''}, newline));
    writeText(shutdownFile, strjoin({
        '% Runs when this MATLAB project closes; created by "uvm project".'
        'if exist(''uvm'', ''file'') == 2'
        '    uvm.internal.deactivate(false);'
        'end'
        ''}, newline));
    for f = {startupFile, shutdownFile}
        if isempty(findFile(proj, f{1}))
            addFile(proj, f{1});
        end
    end
    if ~any(proj.StartupFiles == startupFile)
        addStartupFile(proj, startupFile);
    end
    if ~any(proj.ShutdownFiles == shutdownFile)
        addShutdownFile(proj, shutdownFile);
    end
    uvm.internal.say('Connected %s to MATLAB project "%s"', project.root, proj.Name);
end

function proj = openProjectAt(root, name, create)
%OPENPROJECTAT  The MATLAB project rooted at ROOT, opening or creating it.
    proj = matlab.project.rootProject;
    if ~isempty(proj) && strcmp(char(proj.RootFolder), root)
        return
    end
    if ~isempty(dir(fullfile(root, '*.prj')))
        proj = openProject(root);
    elseif create
        proj = matlab.project.createProject('Folder', root, 'Name', name);
    else
        proj = [];
    end
end

function writeText(file, text)
    fid = fopen(file, 'w', 'n', 'UTF-8');
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end
