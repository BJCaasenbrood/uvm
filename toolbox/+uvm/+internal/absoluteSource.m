function source = absoluteSource(source, base)
%ABSOLUTESOURCE  Make a local path absolute (relative to BASE); leave URLs alone.

    source = char(source);
    if contains(source, '://') || ~isempty(regexp(source, '^[\w.-]+@[\w.-]+:', 'once'))
        return
    end
    isAbsolute = startsWith(source, {'/', '\'}) || ~isempty(regexp(source, '^[A-Za-z]:', 'once'));
    candidate = source;
    if ~isAbsolute
        candidate = fullfile(base, source);
    end
    if isfolder(candidate)
        listing = dir(candidate);
        source = listing(1).folder;
    elseif isfile(candidate)
        listing = dir(candidate);
        source = fullfile(listing(1).folder, listing(1).name);
    end
end
