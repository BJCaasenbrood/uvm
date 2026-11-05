function packages = readRegistry(registry, fetched, fetch)
%READREGISTRY  The "packages" object of a registry's index.json.
%   REGISTRY has fields name and url. FETCHED and FETCH are passed on to
%   uvm.internal.mirror. Returns struct() with a warning when the registry
%   has no readable index.json.

    packages = struct();
    mirrorDir = uvm.internal.mirror(registry.url, fetched, fetch);
    [text, status] = uvm.internal.git('--git-dir', mirrorDir, 'show', 'HEAD:index.json');
    if status ~= 0
        warning('uvm:badRegistry', 'Registry "%s" has no index.json.', registry.name);
        return
    end
    try
        packages = uvm.internal.fieldOr(jsondecode(text), 'packages', struct());
    catch err
        warning('uvm:badRegistry', 'index.json of registry "%s" is invalid: %s', registry.name, err.message);
    end
    if isempty(packages) || ~isstruct(packages)
        packages = struct();
    end
end
