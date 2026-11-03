function c = toCellstr(x)
%TOCELLSTR  Row cellstr from whatever jsondecode produced for a list of strings.

    if isempty(x)
        c = {};
    elseif ischar(x)
        c = {x};
    elseif isstring(x)
        c = cellstr(x(:)');
    elseif iscell(x)
        c = cellfun(@char, x(:)', 'UniformOutput', false);
    else
        error('uvm:badManifest', 'Expected a list of strings.');
    end
end
