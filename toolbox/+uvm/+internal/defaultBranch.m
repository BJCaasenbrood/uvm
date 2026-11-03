function branch = defaultBranch(mirrorDir)
%DEFAULTBRANCH  Name of the branch the remote's HEAD points to.

    branch = strtrim(uvm.internal.git('--git-dir', mirrorDir, 'symbolic-ref', '--short', 'HEAD'));
end
