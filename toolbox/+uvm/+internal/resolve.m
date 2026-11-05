function lock = resolve(project, previous, upgrade)
%RESOLVE  Pick one commit for every package the project needs, transitively.
%   Version-constrained dependencies get the newest tag that satisfies every
%   package asking for them. Packages already in the PREVIOUS lock keep their
%   locked commit while it still satisfies the requirements, unless UPGRADE
%   is set; remotes are only contacted when that is not enough.
%
%   Resolution repeats until the selection stops changing, because picking a
%   different version of a package can change what it requires.

    ctx.fetched = containers.Map();
    ctx.index = containers.Map();      % registry index, filled on first use
    ctx.registries = [project.manifest.registries; uvm.internal.config().registries];
    ctx.upgrade = upgrade;
    ctx.prefs = containers.Map();
    if ~upgrade && ~isempty(previous)
        for p = previous.packages(:)'
            ctx.prefs(p.name) = p;
        end
    end

    rootReqs = normalizeDeps(project.manifest.dependencies, project.manifest.name, ctx, project.root);
    selected = containers.Map();
    converged = false;
    for iteration = 1:100
        reqs = collect(rootReqs, selected);
        next = containers.Map();
        changed = false;
        for name = reqs.keys
            pkg = choose(name{1}, reqs(name{1}), ctx);
            current = [];
            if selected.isKey(name{1})
                current = selected(name{1});
            end
            if ~isempty(current) && strcmp(current.commit, pkg.commit)
                pkg = current;
            else
                pkg = loadPackage(pkg, reqs(name{1}), ctx);
                changed = true;
            end
            next(name{1}) = pkg;
        end
        changed = changed || ~isequal(next.keys, selected.keys);
        selected = next;
        if ~changed
            converged = true;
            break
        end
    end
    if ~converged
        error('uvm:resolveFailed', 'Dependency resolution did not settle; check for conflicting requirements.');
    end

    names = selected.keys;
    packages = repmat(rmfield(makePackage('', '', '', '', '', ''), 'requires'), 0, 1);
    for i = 1:numel(names)
        packages(i, 1) = rmfield(selected(names{i}), 'requires');
    end
    lock = struct('version', 1, 'requires', project.manifest.dependencies, 'packages', {packages});
end

function reqs = collect(rootReqs, selected)
%COLLECT  All requirements reachable from the project through selected packages.
    reqs = containers.Map();
    queue = {rootReqs};
    visited = containers.Map();
    while ~isempty(queue)
        deps = queue{1};
        queue(1) = [];
        for d = deps(:)'
            if reqs.isKey(d.name)
                reqs(d.name) = [reqs(d.name); d];
            else
                reqs(d.name) = d;
            end
            if selected.isKey(d.name) && ~visited.isKey(d.name)
                visited(d.name) = true;
                pkg = selected(d.name);
                queue{end + 1} = pkg.requires; %#ok<AGROW>
            end
        end
    end
end

function pkg = choose(name, reqs, ctx)
%CHOOSE  Select a commit of NAME that satisfies all of REQS.
    urls = unique({reqs.url});
    if numel(urls) > 1
        error('uvm:sourceConflict', 'Package "%s" is required from different sources:\n%s', ...
            name, describe(reqs));
    end
    url = urls{1};
    pref = [];
    if ctx.prefs.isKey(name)
        pref = ctx.prefs(name);
        if ~strcmp(pref.source, url)
            pref = [];
        end
    end
    % With a locked version to keep, try the local mirror before going online.
    mirrorDir = uvm.internal.mirror(url, ctx.fetched, isempty(pref));
    pkg = pick(name, url, mirrorDir, reqs, pref);
    if isempty(pkg) && ~isempty(pref)
        mirrorDir = uvm.internal.mirror(url, ctx.fetched, true);
        pkg = pick(name, url, mirrorDir, reqs, []);
    end
    if isempty(pkg)
        hint = '';
        if all(strcmp({reqs.kind}, 'semver')) && isempty(uvm.internal.listTags(mirrorDir))
            hint = sprintf(['\n%s has no version tags. Depend on a branch instead, e.g. ' ...
                '"uvm add %s --branch main", or give its registry entry a "branch".'], url, url);
        end
        error('uvm:noVersion', 'No version of "%s" satisfies all requirements:\n%s%s', ...
            name, describe(reqs), hint);
    end
end

function pkg = pick(name, url, mirrorDir, reqs, pref)
%PICK  Best commit from the mirror's current contents, or [] if none fits.
%   With a preference (the locked package) only that one is acceptable, so an
%   empty result tells the caller to fetch and pick again without it.
    pkg = [];
    isPin = ~strcmp({reqs.kind}, 'semver');
    ranges = {reqs(~isPin).constraint};
    pins = reqs(isPin);

    if ~isempty(pins)
        if numel(unique(strcat({pins.kind}, ':', {pins.ref}))) > 1
            error('uvm:pinConflict', 'Package "%s" is pinned to different refs:\n%s', name, describe(reqs));
        end
        kind = pins(1).kind;
        ref = pins(1).ref;
        if ~isempty(pref)
            if ~strcmp(pref.kind, kind) || ~strcmp(pref.ref, ref) || ...
                    isempty(uvm.internal.revParse(mirrorDir, pref.commit))
                return
            end
            commit = pref.commit;
        else
            switch kind
                case 'tag'
                    commit = uvm.internal.revParse(mirrorDir, ['refs/tags/' ref]);
                case 'branch'
                    commit = uvm.internal.revParse(mirrorDir, ['refs/heads/' ref]);
                otherwise
                    commit = uvm.internal.revParse(mirrorDir, ref);
            end
            if isempty(commit)
                return
            end
        end
        version = '';
        v = [];
        if strcmp(kind, 'tag')
            v = uvm.internal.versionParse(ref);
        end
        if ~isempty(v)
            version = sprintf('%d.%d.%d', v);
            if ~all(cellfun(@(c) uvm.internal.versionSatisfies(v, c), ranges))
                return
            end
        elseif ~isempty(ranges)
            warning('uvm:uncheckedConstraint', ...
                '"%s" is pinned to %s %s, which has no version; ignoring version constraints on it.', ...
                name, kind, ref);
        end
        pkg = makePackage(name, version, url, kind, ref, commit);
        return
    end

    tags = uvm.internal.listTags(mirrorDir);
    ok = true(size(tags));
    for i = 1:numel(tags)
        ok(i) = all(cellfun(@(c) uvm.internal.versionSatisfies(tags(i).version, c), ranges));
    end
    tags = tags(ok);
    if isempty(tags)
        return
    end
    if ~isempty(pref)
        best = tags(strcmp({tags.tag}, pref.ref) & strcmp({tags.commit}, pref.commit));
        if isempty(best)
            return
        end
        best = best(1);
    else
        [~, order] = sortrows(vertcat(tags.version));
        best = tags(order(end));
    end
    pkg = makePackage(name, sprintf('%d.%d.%d', best.version), url, 'semver', best.tag, best.commit);
end

function pkg = loadPackage(pkg, reqs, ctx)
%LOADPACKAGE  Fill in what the package's own uvm.json says at the chosen commit.
%   For a package without uvm.json, or whose uvm.json leaves out "paths" or
%   "dependencies", those come from its requirement or registry entry; the
%   default is the package root and no dependencies.
    mirrorDir = uvm.internal.mirror(pkg.source, ctx.fetched, false);
    [text, status] = uvm.internal.git('--git-dir', mirrorDir, 'show', [pkg.commit ':uvm.json']);
    raw = struct();
    if status == 0
        try
            raw = jsondecode(text);
        catch err
            error('uvm:badManifest', 'uvm.json of "%s" at %s is invalid: %s', ...
                pkg.name, pkg.commit(1:8), err.message);
        end
    end
    m = uvm.internal.normalizeManifest(raw);
    if isempty(pkg.version)
        pkg.version = m.version;
    end
    pkg.paths = m.paths;
    given = reqs(~cellfun(@isempty, {reqs.paths}));
    if ~isfield(raw, 'paths') && ~isempty(given)
        pkg.paths = given(1).paths;
    end
    pkg.toolboxes = m.toolboxes;
    pkg.matlab = m.matlab;
    deps = m.dependencies;
    given = reqs(~cellfun(@(d) isempty(fieldnames(d)), {reqs.deps}));
    if ~isfield(raw, 'dependencies') && ~isempty(given)
        deps = given(1).deps;
    end
    pkg.requires = normalizeDeps(deps, pkg.name, ctx, '');
    pkg.dependencies = {pkg.requires.name};
end

function reqs = normalizeDeps(deps, from, ctx, baseDir)
%NORMALIZEDEPS  Requirement structs for a manifest's "dependencies" object.
    reqs = repmat(makeReq('', '', '', '', '', '', {}, struct()), 0, 1);
    names = fieldnames(deps);
    for i = 1:numel(names)
        reqs(end + 1, 1) = normalizeDep(names{i}, deps.(names{i}), from, ctx, baseDir); %#ok<AGROW>
    end
end

function req = normalizeDep(name, spec, from, ctx, baseDir)
    if ischar(spec) || isstring(spec)
        entry = registryLookup(name, from, ctx);
        if isempty(entry.branch)
            req = makeReq(name, entry.url, 'semver', char(spec), '', from, entry.paths, entry.dependencies);
            return
        end
        % The registry says this package has no versions: follow its branch.
        if ~any(strcmp(strtrim(char(spec)), {'', '*'}))
            warning('uvm:uncheckedConstraint', ...
                '"%s" has no versions (the registry follows branch %s); ignoring "%s" from %s.', ...
                name, entry.branch, char(spec), from);
        end
        req = makeReq(name, entry.url, 'branch', '', entry.branch, from, entry.paths, entry.dependencies);
        return
    end
    if ~isstruct(spec) || ~isfield(spec, 'git')
        error('uvm:badManifest', ...
            'Dependency "%s" of %s must be a version string or an object with a "git" field.', name, from);
    end
    url = char(spec.git);
    if ~isempty(baseDir)
        url = uvm.internal.absoluteSource(url, baseDir);
    end
    paths = uvm.internal.toCellstr(uvm.internal.fieldOr(spec, 'paths', {}));
    deps = dependencyObject(uvm.internal.fieldOr(spec, 'dependencies', struct()), name, from);
    kinds = intersect({'tag', 'branch', 'rev'}, fieldnames(spec), 'stable');
    if numel(kinds) > 1
        error('uvm:badManifest', 'Dependency "%s" of %s may set only one of tag, branch and rev.', name, from);
    end
    if isempty(kinds)
        req = makeReq(name, url, 'semver', char(uvm.internal.fieldOr(spec, 'version', '*')), '', from, paths, deps);
    else
        req = makeReq(name, url, kinds{1}, '', char(spec.(kinds{1})), from, paths, deps);
    end
end

function entry = registryLookup(name, from, ctx)
%REGISTRYLOOKUP  Registry entry (url, branch, paths) of NAME from the first registry listing it.
%   Registries are read from their local mirrors first and only fetched when
%   the name is missing or an upgrade was requested.
    loadIndex(ctx, ctx.upgrade);
    if ~ctx.index.isKey(name)
        loadIndex(ctx, true);
    end
    if ~ctx.index.isKey(name)
        if isempty(ctx.registries)
            error('uvm:unknownPackage', ['"%s" (needed by %s) has no git URL and no registry is configured.\n' ...
                'Add one with "uvm registry add NAME URL".'], name, from);
        end
        error('uvm:unknownPackage', '"%s" (needed by %s) is not in any registry (%s).', ...
            name, from, strjoin({ctx.registries.name}, ', '));
    end
    entry = ctx.index(name);
end

function loadIndex(ctx, fetch)
    state = 'local';
    if fetch
        state = 'fetched';
    end
    if ctx.index.isKey(['?' state])
        return
    end
    found = containers.Map();
    for r = ctx.registries(:)'
        packages = uvm.internal.readRegistry(r, ctx.fetched, fetch);
        for f = fieldnames(packages)'
            if ~found.isKey(f{1})
                found(f{1}) = registryEntry(packages.(f{1}), f{1}, r.name);
            end
        end
    end
    % Keys starting with '?' cannot be package names, so they mark what was loaded.
    for k = ctx.index.keys
        if ~startsWith(k{1}, '?')
            ctx.index.remove(k{1});
        end
    end
    for k = found.keys
        ctx.index(k{1}) = found(k{1});
    end
    ctx.index(['?' state]) = true;
end

function entry = registryEntry(raw, name, registry)
%REGISTRYENTRY  Normalize an index.json entry: a URL string, or an object
%   with "url" and optionally "branch" (for repositories without version
%   tags), and "paths" and "dependencies" (for repositories without their
%   own uvm.json).
    if ischar(raw) || isstring(raw)
        raw = struct('url', char(raw));
    end
    if ~isstruct(raw) || ~isfield(raw, 'url')
        error('uvm:badRegistry', 'Entry "%s" in registry "%s" needs a "url".', name, registry);
    end
    entry = struct('url', char(raw.url), ...
        'branch', char(uvm.internal.fieldOr(raw, 'branch', '')), ...
        'paths', {uvm.internal.toCellstr(uvm.internal.fieldOr(raw, 'paths', {}))}, ...
        'dependencies', dependencyObject(uvm.internal.fieldOr(raw, 'dependencies', struct()), name, registry));
end

function deps = dependencyObject(deps, name, where)
%DEPENDENCYOBJECT  Validate a "dependencies" object given outside a package's uvm.json.
    if isempty(deps)
        deps = struct();
    end
    if ~isstruct(deps) || ~isscalar(deps)
        error('uvm:badManifest', '"dependencies" of "%s" in %s must be an object.', name, where);
    end
end

function req = makeReq(name, url, kind, constraint, ref, from, paths, deps)
%MAKEREQ  One requirement. PATHS and DEPS are the folders and dependencies
%   to use when the package's own uvm.json does not give them ({} means the
%   package root, struct() means no dependencies).
    req = struct('name', name, 'url', url, 'kind', kind, 'constraint', constraint, ...
        'ref', ref, 'from', from, 'paths', {paths}, 'deps', deps);
end

function pkg = makePackage(name, version, source, kind, ref, commit)
    pkg = struct('name', name, 'version', version, 'source', source, 'kind', kind, ...
        'ref', ref, 'commit', commit, 'paths', {{}}, 'toolboxes', {{}}, 'matlab', '', ...
        'dependencies', {{}}, 'requires', repmat(makeReq('', '', '', '', '', '', {}, struct()), 0, 1));
end

function text = describe(reqs)
    lines = cell(numel(reqs), 1);
    for i = 1:numel(reqs)
        r = reqs(i);
        if strcmp(r.kind, 'semver')
            what = r.constraint;
        else
            what = [r.kind ' ' r.ref];
        end
        lines{i} = sprintf('  %s requires %s %s (%s)', r.from, r.name, what, r.url);
    end
    text = strjoin(lines, newline);
end
