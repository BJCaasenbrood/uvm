function project = loadProject(startDir)
%LOADPROJECT  Locate and read the project that contains STARTDIR.
%   PROJECT has fields root, manifestFile, lockFile, raw (uvm.json as
%   decoded) and manifest (raw with defaults filled in).

    root = uvm.internal.findRoot(startDir);
    if isempty(root)
        error('uvm:noProject', 'No uvm.json found in "%s" or its parents. Run "uvm init" first.', startDir);
    end
    project.root = root;
    project.manifestFile = fullfile(root, 'uvm.json');
    project.lockFile = fullfile(root, 'uvm.lock');
    project.raw = uvm.internal.readJson(project.manifestFile);
    project.manifest = uvm.internal.normalizeManifest(project.raw);
    if isempty(project.manifest.name)
        [~, folderName] = fileparts(root);
        project.manifest.name = folderName;
    end
end
