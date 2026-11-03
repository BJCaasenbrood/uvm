function tf = versionSatisfies(v, constraint)
%VERSIONSATISFIES  True if version vector V meets CONSTRAINT.
%   Constraints follow Cargo's rules:
%     ^1.2.3  >=1.2.3 <2.0.0     (^0.2.3 means <0.3.0, ^0.0.3 means <0.0.4)
%     1.2.3   same as ^1.2.3
%     ~1.2.3  >=1.2.3 <1.3.0     (~1 means <2.0.0)
%     >=, >, <=, <, =             plain comparisons
%     *  or ''                    anything
%   Combine with commas: ">=1.2, <1.8".

    constraint = strtrim(char(constraint));
    tf = true;
    if isempty(constraint) || strcmp(constraint, '*')
        return
    end
    for part = strtrim(strsplit(constraint, ','))
        op = regexp(part{1}, '^(\^|~|>=|<=|>|<|==|=)', 'match', 'once');
        [bound, given] = uvm.internal.versionParse(part{1}(numel(op) + 1:end));
        if isempty(bound)
            error('uvm:badConstraint', 'Invalid version constraint "%s".', constraint);
        end
        c = uvm.internal.versionCompare(v, bound);
        switch op
            case {'', '^'}
                ok = c >= 0 && uvm.internal.versionCompare(v, caretUpper(bound, given)) < 0;
            case '~'
                if given == 1
                    upper = [bound(1) + 1, 0, 0];
                else
                    upper = [bound(1), bound(2) + 1, 0];
                end
                ok = c >= 0 && uvm.internal.versionCompare(v, upper) < 0;
            case '>='
                ok = c >= 0;
            case '>'
                ok = c > 0;
            case '<='
                ok = c <= 0;
            case '<'
                ok = c < 0;
            otherwise
                ok = c == 0;
        end
        tf = tf && ok;
    end
end

function upper = caretUpper(bound, given)
    if bound(1) > 0 || given == 1
        upper = [bound(1) + 1, 0, 0];
    elseif bound(2) > 0 || given == 2
        upper = [0, bound(2) + 1, 0];
    else
        upper = [0, 0, bound(3) + 1];
    end
end
