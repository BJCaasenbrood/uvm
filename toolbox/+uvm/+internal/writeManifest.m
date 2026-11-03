function writeManifest(file, raw)
%WRITEMANIFEST  Write uvm.json, keeping list fields as JSON arrays.
%   jsondecode turns one-element arrays into scalars; this undoes that so a
%   round trip through MATLAB does not change the file's structure.

    for f = {'toolboxes', 'paths'}
        if isfield(raw, f{1})
            raw.(f{1}) = uvm.internal.toCellstr(raw.(f{1}));
        end
    end
    if isfield(raw, 'registries')
        raw.registries = num2cell(uvm.internal.toStructArray(raw.registries, {'name', 'url'})');
    end
    uvm.internal.writeJson(file, raw);
end
