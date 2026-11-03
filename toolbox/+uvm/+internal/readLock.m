function lock = readLock(file)
%READLOCK  Read uvm.lock, or return [] when there is none.
%   LOCK.packages is a column struct array with the fields listed in
%   uvm.internal.lockFields.

    if ~isfile(file)
        lock = [];
        return
    end
    raw = uvm.internal.readJson(file);
    requires = uvm.internal.fieldOr(raw, 'requires', struct());
    if isempty(requires)
        requires = struct();
    end
    packages = uvm.internal.toStructArray(uvm.internal.fieldOr(raw, 'packages', []), ...
        uvm.internal.lockFields());
    for i = 1:numel(packages)
        for f = {'paths', 'toolboxes', 'dependencies'}
            packages(i).(f{1}) = uvm.internal.toCellstr(packages(i).(f{1}));
        end
    end
    lock = struct('version', uvm.internal.fieldOr(raw, 'version', 1), ...
        'requires', requires, 'packages', {packages});
end
