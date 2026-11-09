function artifact = build(project, lock, format, outputDir, includeDeps)
%BUILD  Package a project and its locked packages for people without uvm.
%   ARTIFACT = uvm.internal.build(PROJECT, LOCK, FORMAT, OUTPUTDIR, INCLUDEDEPS)
%   writes OUTPUTDIR/<name>-<version>.zip (FORMAT 'zip') or .mltbx (FORMAT
%   'toolbox') and returns its path. Every package in LOCK must be installed.
%
%   The bundle holds the project's files (in a git repository: tracked and
%   untracked-but-not-ignored files), the packages under uvm_packages/, and
%   THIRD_PARTY_LICENSES.md. A zip also gets setup_<name>.m, which puts
%   everything on the path; a toolbox sets the path when it is installed.

    name = matlab.lang.makeValidName(project.manifest.name);
    version = project.manifest.version;
    if isempty(version)
        version = '0.0.0';
    end
    bundleName = sprintf('%s-%s', name, version);
    staging = tempname;
    bundle = fullfile(staging, bundleName);
    mkdir(bundle);
    cleanup = onCleanup(@() rmdir(staging, 's'));

    copyProjectFiles(project.root, bundle, outputDir);
    folders = uvm.internal.packagePaths(bundle, project.manifest.paths, name);
    packages = lock.packages;
    if ~includeDeps
        packages = packages([]);
    end
    licenses = cell(numel(packages), 1);
    for i = 1:numel(packages)
        p = packages(i);
        source = uvm.internal.packageDir(p);
        if ~isfolder(source)
            error('uvm:notInstalled', 'Package "%s" is not installed. Run "uvm sync" first.', p.name);
        end
        dest = fullfile(bundle, 'uvm_packages', p.name);
        mkdir(dest);
        copyfile(source, dest);
        folders = [folders, uvm.internal.packagePaths(dest, p.paths, p.name)]; %#ok<AGROW>
        licenses{i} = detectLicense(dest);
    end
    writeLicenseReport(fullfile(bundle, 'THIRD_PARTY_LICENSES.md'), project, packages, licenses, includeDeps, lock);

    if ~isfolder(outputDir)
        mkdir(outputDir);
    end
    if strcmp(format, 'toolbox')
        artifact = fullfile(outputDir, [bundleName '.mltbx']);
        packageToolbox(project, name, version, bundle, folders, artifact, includeDeps, lock);
    else
        relative = cellfun(@(f) strrep(f(numel(bundle) + 2:end), filesep, '/'), folders, 'UniformOutput', false);
        writeSetupScript(fullfile(bundle, ['setup_' name '.m']), name, version, relative);
        artifact = fullfile(outputDir, [bundleName '.zip']);
        if isfile(artifact)
            delete(artifact);
        end
        zip(artifact, bundleName, staging);
    end

    copyleft = packages(contains(licenses, 'GPL'));
    if ~isempty(copyleft)
        warning('uvm:copyleft', ['These bundled packages use a GPL-family license, which then applies to ' ...
            'what you distribute with them: %s. See THIRD_PARTY_LICENSES.md in the bundle.'], ...
            strjoin({copyleft.name}, ', '));
    end
    unknown = packages(startsWith(licenses, 'none'));
    if ~isempty(unknown)
        warning('uvm:noLicense', ['No license file found for: %s. Without a license you may not have ' ...
            'the right to redistribute that code.'], strjoin({unknown.name}, ', '));
    end
    info = dir(artifact);
    uvm.internal.say('Built %s (%d package(s), %.1f MB)', artifact, numel(packages), info.bytes / 2^20);
end

function copyProjectFiles(root, bundle, outputDir)
%COPYPROJECTFILES  Copy the project's own files, leaving out uvm state and build output.
    files = listProjectFiles(root);
    skip = {'.uvm', 'dist'};
    if startsWith([outputDir filesep], [root filesep])
        skip{end + 1} = strrep(outputDir(numel(root) + 2:end), filesep, '/');
    end
    for i = 1:numel(files)
        rel = files{i};
        if any(strcmp(rel, skip) | startsWith(rel, strcat(skip, '/')))
            continue
        end
        source = fullfile(root, rel);
        if ~isfile(source)
            continue   % tracked by git but deleted
        end
        dest = fullfile(bundle, rel);
        destDir = fileparts(dest);
        if ~isfolder(destDir)
            mkdir(destDir);
        end
        copyfile(source, dest);
    end
end

function files = listProjectFiles(root)
%LISTPROJECTFILES  Project files relative to ROOT, with '/' separators.
%   In a git repository: tracked files plus untracked files that are not
%   ignored, so .gitignore keeps secrets and scratch files out. Otherwise
%   every file except hidden ones.
    [out, status] = uvm.internal.git('-c', 'core.quotePath=false', '-C', root, 'ls-files', ...
        '--cached', '--others', '--exclude-standard');
    if status == 0
        files = splitlines(strtrim(out));
        files = files(~cellfun(@isempty, files))';
        files = unique(strrep(files, '\', '/'));
        return
    end
    listing = dir(fullfile(root, '**', '*'));
    listing = listing(~[listing.isdir]);
    files = cell(1, numel(listing));
    for i = 1:numel(listing)
        full = fullfile(listing(i).folder, listing(i).name);
        files{i} = strrep(full(numel(root) + 2:end), filesep, '/');
    end
    hidden = cellfun(@(f) any(startsWith(strsplit(f, '/'), '.')), files);
    files = files(~hidden);
end

function license = detectLicense(folder)
%DETECTLICENSE  License family of a package, from its LICENSE or COPYING file.
    listing = dir(folder);
    names = {listing(~[listing.isdir]).name};
    candidates = names(~cellfun(@isempty, regexpi(names, '^(licen[cs]e|copying)(\.\w+)?$', 'once')));
    if isempty(candidates)
        license = 'none found';
        return
    end
    text = fileread(fullfile(folder, candidates{1}));
    if contains(text, 'GNU LESSER GENERAL PUBLIC LICENSE', 'IgnoreCase', true)
        family = 'LGPL';
    elseif contains(text, 'GNU AFFERO GENERAL PUBLIC LICENSE', 'IgnoreCase', true)
        family = 'AGPL';
    elseif contains(text, 'GNU GENERAL PUBLIC LICENSE', 'IgnoreCase', true)
        family = 'GPL';
    elseif contains(text, 'Apache License', 'IgnoreCase', true)
        family = 'Apache';
    elseif contains(text, 'Mozilla Public License', 'IgnoreCase', true)
        family = 'MPL';
    elseif contains(text, 'Permission is hereby granted, free of charge', 'IgnoreCase', true)
        family = 'MIT';
    elseif contains(text, 'Redistribution and use in source and binary forms', 'IgnoreCase', true)
        family = 'BSD';
    else
        family = 'other';
    end
    license = sprintf('%s (%s)', family, candidates{1});
end

function writeLicenseReport(file, project, packages, licenses, includeDeps, lock)
    lines = {
        sprintf('# Third-party packages in %s %s', project.manifest.name, project.manifest.version)
        ''
        sprintf('Created by uvm build on %s. Each package keeps its own license file in uvm_packages/<name>/.', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd')))
        'The license column is detected automatically; check the files themselves before you redistribute.'
        ''
        '| Package | Version | Commit | License | Source |'
        '|---|---|---|---|---|'
        };
    for i = 1:numel(packages)
        p = packages(i);
        label = p.version;
        if ~strcmp(p.kind, 'semver')
            label = sprintf('%s %s', p.kind, p.ref);
        end
        lines{end + 1, 1} = sprintf('| %s | %s | %s | %s | %s |', p.name, label, p.commit(1:min(12, end)), ...
            licenses{i}, p.source); %#ok<AGROW>
    end
    if isempty(packages)
        lines{end + 1, 1} = '| (none bundled) | | | | |';
    end
    if ~includeDeps && ~isempty(lock.packages)
        lines = [lines; {''; 'Not bundled; install these separately:'; ''}; ...
            cellfun(@(n, s) sprintf('- %s (%s)', n, s), {lock.packages.name}', {lock.packages.source}', ...
            'UniformOutput', false)];
    end
    writeText(file, strjoin(lines, newline));
end

function writeSetupScript(file, name, version, relative)
    quoted = cellfun(@(r) sprintf('        ''%s''', strrep(r, '''', '''''')), relative, 'UniformOutput', false);
    lines = [{
        sprintf('function setup_%s(action)', name)
        sprintf('%%SETUP_%s  Put %s and its bundled packages on the MATLAB path.', upper(name), name)
        sprintf('%%   setup_%s            adds them for this session', name)
        sprintf('%%   setup_%s(''remove'')  removes them again', name)
        '%'
        sprintf('%%   Created by "uvm build" from %s %s. No uvm or git needed.', name, version)
        ''
        '    if nargin < 1'
        '        action = ''add'';'
        '    end'
        '    root = fileparts(mfilename(''fullpath''));'
        '    folders = {'
        }; quoted(:); {
        '        };'
        '    folders = fullfile(root, strrep(folders, ''/'', filesep));'
        '    if strcmp(action, ''remove'')'
        '        rmpath(folders{:});'
        '    else'
        '        addpath(folders{:});'
        '    end'
        'end'
        ''
        }];
    writeText(file, strjoin(lines, newline));
end

function packageToolbox(project, name, version, bundle, folders, artifact, includeDeps, lock)
%PACKAGETOOLBOX  Write a .mltbx with MATLAB's ToolboxOptions API (R2023a+).
    % A stable identifier per project name, so a new build upgrades the old install.
    identifier = char(java.util.UUID.nameUUIDFromBytes(typecast(unicode2native(['uvm:' name], 'UTF-8'), 'int8')));
    opts = matlab.addons.toolbox.ToolboxOptions(bundle, identifier);
    opts.ToolboxName = project.manifest.name;
    opts.ToolboxVersion = toolboxVersion(version);
    opts.OutputFile = artifact;
    opts.ToolboxMatlabPath = folders;
    opts.Summary = char(uvm.internal.fieldOr(project.raw, 'description', ...
        sprintf('%s, packaged with uvm', project.manifest.name)));
    opts.AuthorName = char(uvm.internal.fieldOr(project.raw, 'author', ''));
    notes = {};
    if ~isempty(project.manifest.toolboxes)
        notes{end + 1} = ['Requires: ' strjoin(project.manifest.toolboxes, ', ') '.'];
    end
    if ~includeDeps && ~isempty(lock.packages)
        notes{end + 1} = ['Install these packages separately: ' strjoin({lock.packages.name}, ', ') '.'];
    end
    opts.Description = strjoin(notes, ' ');
    [minimum, maximum] = releaseRange(project.manifest.matlab);
    if ~isempty(minimum)
        opts.MinimumMatlabRelease = minimum;
    end
    if ~isempty(maximum)
        opts.MaximumMatlabRelease = maximum;
    end
    matlab.addons.toolbox.packageToolbox(opts);
end

function v = toolboxVersion(version)
%TOOLBOXVERSION  ToolboxOptions accepts only numbers separated by dots.
    numbers = regexp(version, '^\d+(\.\d+){0,3}', 'match', 'once');
    if isempty(numbers)
        numbers = '1.0';
    end
    v = numbers;
end

function [minimum, maximum] = releaseRange(constraint)
%RELEASERANGE  Lowest and highest release a constraint like '>=R2023a, <R2025a' allows.
    minimum = '';
    maximum = '';
    for part = strtrim(strsplit(char(constraint), ','))
        tokens = regexp(part{1}, '^(>=|<=|>|<|==|=)?\s*[Rr]?(\d{4})([ab])$', 'tokens', 'once');
        if isempty(tokens)
            continue
        end
        op = regexp(part{1}, '^(>=|<=|>|<|==|=)', 'match', 'once');
        release = str2double(tokens{end - 1}) + 0.5 * strcmp(tokens{end}, 'b');
        switch op
            case {'', '>='}
                minimum = releaseName(release);
            case '>'
                minimum = releaseName(release + 0.5);
            case '<='
                maximum = releaseName(release);
            case '<'
                maximum = releaseName(release - 0.5);
            otherwise
                minimum = releaseName(release);
                maximum = minimum;
        end
    end
end

function name = releaseName(n)
    letters = 'ab';
    name = sprintf('R%d%s', floor(n), letters(1 + (n - floor(n) >= 0.5)));
end

function writeText(file, text)
    fid = fopen(file, 'w', 'n', 'UTF-8');
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end
