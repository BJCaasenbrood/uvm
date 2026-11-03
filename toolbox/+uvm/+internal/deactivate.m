function deactivate(verbose)
%DEACTIVATE  Remove the active project's path entries again.

    state = getappdata(groot, 'uvm_active');
    if isempty(state)
        if verbose
            uvm.internal.say('No project is active.');
        end
        return
    end
    previous = warning('off', 'MATLAB:rmpath:DirNotFound');
    restore = onCleanup(@() warning(previous));
    if ~isempty(state.paths)
        rmpath(state.paths{:});
    end
    rmappdata(groot, 'uvm_active');
    if verbose
        uvm.internal.say('Deactivated %s', state.root);
    end
end
