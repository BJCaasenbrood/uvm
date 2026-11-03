function tags = listTags(mirrorDir)
%LISTTAGS  Version tags of a mirror as a struct array (tag, version, commit).
%   Tags that are not plain versions (v1.2.3, 1.2, ...) are skipped.

    tags = struct('tag', {}, 'version', {}, 'commit', {});
    out = uvm.internal.git('--git-dir', mirrorDir, 'for-each-ref', 'refs/tags', ...
        '--format=%(refname:strip=2) %(objectname) %(*objectname)');
    lines = splitlines(strtrim(out));
    for i = 1:numel(lines)
        parts = strsplit(strtrim(lines{i}), ' ');
        if numel(parts) < 2
            continue
        end
        v = uvm.internal.versionParse(parts{1});
        if isempty(v)
            continue
        end
        % Annotated tags list the tagged commit last; lightweight tags are the commit.
        tags(end + 1) = struct('tag', parts{1}, 'version', v, 'commit', parts{end}); %#ok<AGROW>
    end
end
