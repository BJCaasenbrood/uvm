function commit = revParse(mirrorDir, rev)
%REVPARSE  Commit that REV points to in the mirror, or '' if it does not exist.

    [out, status] = uvm.internal.git('--git-dir', mirrorDir, 'rev-parse', ...
        '--verify', '--quiet', [rev '^{commit}']);
    if status == 0
        commit = strtrim(out);
    else
        commit = '';
    end
end
