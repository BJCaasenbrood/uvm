function s = toStructArray(x, fields)
%TOSTRUCTARRAY  Column struct array with exactly FIELDS from a decoded JSON list.
%   jsondecode returns [], a struct, a struct array or a cell array depending
%   on the list contents; this gives callers a single shape to work with.
%   Missing fields become ''.

    if isempty(x)
        items = {};
    elseif iscell(x)
        items = x(:)';
    else
        items = num2cell(x(:)');
    end
    s = cell2struct(cell(numel(fields), 0), fields(:), 1);
    for i = 1:numel(items)
        for f = 1:numel(fields)
            s(i, 1).(fields{f}) = uvm.internal.fieldOr(items{i}, fields{f}, '');
        end
    end
end
