function syncProject(project, upgrade, frozen)
%SYNCPROJECT  Lock if needed, install, check the environment and activate.

    lock = uvm.internal.lockProject(project, upgrade, false, frozen);
    uvm.internal.install(project, lock);
    uvm.internal.checkEnvironment(project, lock);
    uvm.internal.activate(project.root);
end
