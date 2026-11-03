function value = fieldOr(s, name, default)
%FIELDOR  S.(NAME) if that field exists, otherwise DEFAULT.

    if isstruct(s) && isfield(s, name)
        value = s.(name);
    else
        value = default;
    end
end
