function m = normalizeManifest(raw)
%NORMALIZEMANIFEST  Fill in defaults for a decoded uvm.json.
%
%   {
%     "name": "my_analysis",
%     "version": "0.1.0",
%     "matlab": ">=R2023a",
%     "toolboxes": ["Signal Processing Toolbox"],
%     "paths": ["."],                  folders to put on the path
%     "dependencies": {
%       "signal_utils": "^1.2",        from a registry
%       "daq_tools": {"git": "git@server:lab/daq_tools.git", "tag": "v0.4.0"}
%     },
%     "registries": [{"name": "work", "url": "git@server:matlab/registry.git"}]
%   }

    if isempty(raw)
        raw = struct();
    end
    m.name = char(uvm.internal.fieldOr(raw, 'name', ''));
    m.version = char(uvm.internal.fieldOr(raw, 'version', ''));
    m.matlab = char(uvm.internal.fieldOr(raw, 'matlab', ''));
    m.toolboxes = uvm.internal.toCellstr(uvm.internal.fieldOr(raw, 'toolboxes', {}));
    m.paths = uvm.internal.toCellstr(uvm.internal.fieldOr(raw, 'paths', {'.'}));
    m.dependencies = uvm.internal.fieldOr(raw, 'dependencies', struct());
    if isempty(m.dependencies)
        m.dependencies = struct();
    end
    if ~isstruct(m.dependencies) || ~isscalar(m.dependencies)
        error('uvm:badManifest', '"dependencies" must be an object.');
    end
    m.registries = uvm.internal.toStructArray( ...
        uvm.internal.fieldOr(raw, 'registries', []), {'name', 'url'});
end
