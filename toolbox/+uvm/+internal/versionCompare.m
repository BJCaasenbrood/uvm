function c = versionCompare(a, b)
%VERSIONCOMPARE  -1, 0 or 1 as version vector A is below, equal to or above B.

    d = a - b;
    first = find(d, 1);
    if isempty(first)
        c = 0;
    else
        c = sign(d(first));
    end
end
