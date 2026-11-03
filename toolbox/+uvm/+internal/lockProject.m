function lock = lockProject(project, upgrade, force, frozen)
%LOCKPROJECT  Return an up-to-date lock, resolving only when the manifest changed.
%   FORCE resolves even when the lock matches uvm.json (locked versions are
%   still preferred unless UPGRADE). FROZEN never resolves: the lock must
%   exist and match uvm.json, which is what CI should check.

    previous = uvm.internal.readLock(project.lockFile);
    upToDate = ~isempty(previous) && ...
        strcmp(jsonencode(previous.requires), jsonencode(project.manifest.dependencies));
    if frozen
        if isempty(previous)
            error('uvm:noLock', 'No uvm.lock in %s. Run "uvm lock" and commit uvm.lock.', project.root);
        end
        if ~upToDate
            error('uvm:lockOutdated', ['uvm.lock does not match the dependencies in uvm.json. ' ...
                'Run "uvm lock" and commit uvm.lock.']);
        end
        lock = previous;
        return
    end
    if upToDate && ~force && ~upgrade
        lock = previous;
        return
    end
    lock = uvm.internal.resolve(project, previous, upgrade);
    uvm.internal.writeLock(project.lockFile, lock);
    uvm.internal.say('Resolved %d package(s)', numel(lock.packages));
end
