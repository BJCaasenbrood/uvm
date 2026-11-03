function tf = releaseSatisfies(release, constraint)
%RELEASESATISFIES  True if MATLAB release RELEASE (e.g. '2024a') meets CONSTRAINT.
%   CONSTRAINT looks like '>=R2023a' or '>=R2022b, <R2025a'. A bare release
%   ('R2023a') means that release or newer.

    tf = true;
    constraint = strtrim(char(constraint));
    if isempty(constraint) || strcmp(constraint, '*')
        return
    end
    current = releaseNumber(release);
    for part = strtrim(strsplit(constraint, ','))
        op = regexp(part{1}, '^(>=|<=|>|<|==|=)', 'match', 'once');
        rest = strtrim(part{1}(numel(op) + 1:end));
        if isempty(regexp(rest, '^[Rr]?\d{4}[ab]$', 'once'))
            error('uvm:badConstraint', 'Invalid MATLAB release constraint "%s".', constraint);
        end
        bound = releaseNumber(rest);
        switch op
            case {'', '>='}
                ok = current >= bound;
            case '>'
                ok = current > bound;
            case '<='
                ok = current <= bound;
            case '<'
                ok = current < bound;
            otherwise
                ok = current == bound;
        end
        tf = tf && ok;
    end
end

function n = releaseNumber(release)
    tokens = regexp(char(release), '(\d{4})([ab])', 'tokens', 'once');
    n = str2double(tokens{1}) + 0.5 * strcmp(tokens{2}, 'b');
end
