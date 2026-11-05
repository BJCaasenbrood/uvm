function results = parseSearchResults(source, response, query)
%PARSESEARCHRESULTS  Search results from a decoded web API response.
%   SOURCE is 'github' (GitHub repository search) or 'fex' (MATLAB Central
%   community search). Results whose name matches QUERY exactly come first;
%   otherwise the API's order is kept. See uvm.internal.search for the
%   fields. With SOURCE 'none', returns an empty result array.

    results = struct('source', {}, 'name', {}, 'url', {}, 'description', {}, ...
        'stars', {}, 'note', {}, 'add', {});
    results = reshape(results, 0, 1);
    if strcmp(source, 'none')
        return
    end
    items = uvm.internal.fieldOr(response, 'items', []);
    if isempty(items)
        return
    end
    if ~iscell(items)
        items = num2cell(items);
    end

    names = cell(numel(items), 1);
    for i = 1:numel(items)
        item = items{i};
        switch source
            case 'github'
                name = text(item, 'full_name');
                url = text(item, 'clone_url');
                stars = uvm.internal.fieldOr(item, 'stargazers_count', NaN);
                add = ['uvm add ' url];
                [~, names{i}] = fileparts(name);
            otherwise
                % Only title and url are known to exist in this API's items.
                name = text(item, 'title');
                url = text(item, 'url');
                stars = NaN;
                add = '';
                names{i} = name;
        end
        description = text(item, 'description');
        if isempty(description)
            description = text(item, 'summary');
        end
        description = strtrim(regexprep(description, '\s+', ' '));
        results(end + 1, 1) = struct('source', source, 'name', name, 'url', url, ...
            'description', description, 'stars', stars, 'note', '', 'add', add); %#ok<AGROW>
    end

    simplify = @(s) lower(regexprep(s, '[-_\s]', ''));
    exact = strcmp(cellfun(simplify, names, 'UniformOutput', false), simplify(query));
    results = [results(exact); results(~exact)];
end

function value = text(item, field)
    value = uvm.internal.fieldOr(item, field, '');
    if ~ischar(value) && ~isstring(value)
        value = '';   % JSON null decodes to []
    end
    value = char(value);
end
