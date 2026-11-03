function writeLock(file, lock)
%WRITELOCK  Write uvm.lock.

    packages = lock.packages(:)';
    for i = 1:numel(packages)
        for f = {'paths', 'toolboxes', 'dependencies'}
            packages(i).(f{1}) = uvm.internal.toCellstr(packages(i).(f{1}));
        end
    end
    out = struct('version', 1, 'requires', lock.requires, 'packages', {num2cell(packages)});
    uvm.internal.writeJson(file, out);
end
