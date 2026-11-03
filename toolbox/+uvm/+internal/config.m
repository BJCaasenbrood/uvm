function cfg = config(cfg)
%CONFIG  Read the user configuration, or write it when given one.
%   CFG = uvm.internal.config() reads UVM_HOME/config.json.
%   uvm.internal.config(CFG) writes it.
%
%   CFG.registries is a struct array with fields name and url.

    file = fullfile(uvm.internal.home(), 'config.json');
    if nargin == 0
        raw = struct();
        if isfile(file)
            raw = uvm.internal.readJson(file);
        end
        cfg = struct();
        cfg.registries = uvm.internal.toStructArray( ...
            uvm.internal.fieldOr(raw, 'registries', []), {'name', 'url'});
        return
    end
    folder = uvm.internal.home();
    if ~isfolder(folder)
        mkdir(folder);
    end
    out = cfg;
    out.registries = num2cell(cfg.registries(:)');
    uvm.internal.writeJson(file, out);
end
