function folder = home()
%HOME  Folder holding the uvm cache and config (UVM_HOME, default ~/.uvm).

    folder = getenv('UVM_HOME');
    if isempty(folder)
        if ispc
            base = getenv('USERPROFILE');
        else
            base = getenv('HOME');
        end
        folder = fullfile(base, '.uvm');
    end
end
