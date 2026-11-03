function checkEnvironment(project, lock)
%CHECKENVIRONMENT  Warn about MATLAB releases, missing toolboxes and name clashes.
%   MATLAB has one global namespace for functions, so two packages that both
%   ship e.g. utils.m silently shadow each other; this reports such clashes.

    owners = [{project.manifest.name}, {lock.packages.name}];
    releases = [{project.manifest.matlab}, {lock.packages.matlab}];
    toolboxes = [{project.manifest.toolboxes}, {lock.packages.toolboxes}];
    folders = {uvm.internal.packagePaths(project.root, project.manifest.paths, project.manifest.name)};
    for p = lock.packages(:)'
        folders{end + 1} = uvm.internal.packagePaths(uvm.internal.packageDir(p), p.paths, p.name); %#ok<AGROW>
    end

    release = version('-release');
    for i = 1:numel(owners)
        if ~uvm.internal.releaseSatisfies(release, releases{i})
            warning('uvm:matlabRelease', '%s needs MATLAB %s, but this is R%s.', owners{i}, releases{i}, release);
        end
    end

    if any(~cellfun(@isempty, toolboxes))
        installed = ver;
        names = {installed.Name};
        for i = 1:numel(owners)
            missing = setdiff(toolboxes{i}, names);
            if ~isempty(missing)
                warning('uvm:missingToolbox', '%s needs toolboxes that are not installed: %s', ...
                    owners{i}, strjoin(missing, ', '));
            end
        end
    end

    seen = containers.Map();
    clashes = {};
    for i = 1:numel(owners)
        for name = definedNames(folders{i})
            if ~seen.isKey(name{1})
                seen(name{1}) = owners{i};
            elseif ~strcmp(seen(name{1}), owners{i})
                clashes{end + 1} = sprintf('  %s (in %s and %s)', name{1}, seen(name{1}), owners{i}); %#ok<AGROW>
            end
        end
    end
    if ~isempty(clashes)
        warning('uvm:shadowing', 'These names are defined by more than one package; MATLAB uses the first one on the path:\n%s', ...
            strjoin(clashes, newline));
    end
end

function names = definedNames(folders)
%DEFINEDNAMES  Functions, scripts and classes defined directly in FOLDERS.
    names = {};
    for i = 1:numel(folders)
        if ~isfolder(folders{i})
            continue
        end
        for entry = dir(folders{i})'
            [~, base, ext] = fileparts(entry.name);
            if entry.isdir && startsWith(entry.name, '@')
                names{end + 1} = entry.name(2:end); %#ok<AGROW>
            elseif ~entry.isdir && (any(strcmp(ext, {'.m', '.mlx', '.p', '.slx', '.mdl'})) || startsWith(ext, '.mex'))
                names{end + 1} = base; %#ok<AGROW>
            end
        end
    end
    names = setdiff(unique(names), {'Contents', 'startup'});
    names = reshape(names, 1, []);   % so "for" over an empty result runs zero times
end
