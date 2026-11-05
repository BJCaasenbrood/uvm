function [results, failed] = search(query, sources, limit, registries)
%SEARCH  Find packages in registries, on GitHub and on the File Exchange.
%   RESULTS = uvm.internal.search(QUERY, SOURCES, LIMIT, REGISTRIES)
%   searches each of SOURCES ('registry', 'github', 'fex') and returns at
%   most LIMIT results per source as a column struct array with fields:
%     source       'registry', 'github' or 'fex'
%     name         package name, owner/repository, or File Exchange title
%     url          git URL, or the File Exchange page
%     description  one-line summary ('' if none)
%     stars        GitHub stars (NaN otherwise)
%     note         extra information, e.g. which registry lists it
%     add          the uvm command that adds it ('' if uvm cannot yet)
%
%   A source that cannot be reached gives a uvm:searchFailed warning and
%   is listed in FAILED; the other sources are still searched. A GitHub
%   result that a registry also lists suggests the registry name, whose
%   entry knows the right branch and paths.

    results = uvm.internal.parseSearchResults('none', []);
    failed = {};
    % URLs of every registry entry, so GitHub hits can point to the registry name.
    [found, known] = searchRegistries(query, registries, limit);
    if any(strcmp(sources, 'registry'))
        results = [results; found];
    end
    if any(strcmp(sources, 'github'))
        [found, ok] = searchGithub(query, limit, known);
        results = [results; found];
        if ~ok, failed{end + 1} = 'github'; end
    end
    if any(strcmp(sources, 'fex'))
        [found, ok] = searchFileExchange(query, limit);
        results = [results; found];
        if ~ok, failed{end + 1} = 'fex'; end
    end
end

function [results, known] = searchRegistries(query, registries, limit)
    results = uvm.internal.parseSearchResults('none', []);
    known = containers.Map();
    words = lower(strsplit(strtrim(query)));
    scores = [];
    fetched = containers.Map();
    for r = registries(:)'
        try
            packages = uvm.internal.readRegistry(r, fetched, true);
        catch err
            % Offline: fall back to the copy from the last fetch, if there is one.
            try
                packages = uvm.internal.readRegistry(r, fetched, false);
                warning('uvm:searchFailed', 'Could not update registry "%s"; searching the cached copy.', r.name);
            catch
                warning('uvm:searchFailed', 'Could not read registry "%s": %s', r.name, err.message);
                continue
            end
        end
        for f = fieldnames(packages)'
            entry = packages.(f{1});
            if ischar(entry) || isstring(entry)
                entry = struct('url', char(entry));
            end
            url = char(uvm.internal.fieldOr(entry, 'url', ''));
            known(normalizeUrl(url)) = struct('name', f{1}, 'registry', r.name);
            description = char(uvm.internal.fieldOr(entry, 'description', ''));
            haystack = lower(strjoin({f{1}, description, char(uvm.internal.fieldOr(entry, 'category', ''))}, ' '));
            if ~all(cellfun(@(w) contains(haystack, w), words))
                continue
            end
            result = makeResult('registry', f{1}, url, description, NaN, ...
                sprintf('registry "%s"', r.name), ['uvm add ' f{1}]);
            results(end + 1, 1) = result; %#ok<AGROW>
            scores(end + 1, 1) = rank(f{1}, query); %#ok<AGROW>
        end
    end
    [~, order] = sort(scores, 'descend');
    results = results(order(1:min(limit, end)));
end

function [results, ok] = searchGithub(query, limit, known)
    ok = false;
    results = uvm.internal.parseSearchResults('none', []);
    headers = {'Accept', 'application/vnd.github+json'; 'X-GitHub-Api-Version', '2022-11-28'};
    token = getenv('GITHUB_TOKEN');
    if isempty(token)
        token = getenv('GH_TOKEN');
    end
    if ~isempty(token)
        headers(end + 1, :) = {'Authorization', ['Bearer ' token]};
    end
    options = weboptions('Timeout', 20, 'ContentType', 'json', 'HeaderFields', headers);
    try
        response = webread('https://api.github.com/search/repositories', ...
            'q', [query ' language:MATLAB'], 'sort', 'stars', 'order', 'desc', ...
            'per_page', num2str(min(100, 3 * limit)), options);
    catch err
        message = err.message;
        if contains(message, {'403', '429', 'rate limit'})
            message = [message ' GitHub limits anonymous searches to about 10 per minute; ' ...
                'set the GITHUB_TOKEN environment variable to a personal access token to raise it.'];
        end
        warning('uvm:searchFailed', 'GitHub search failed: %s', message);
        return
    end
    ok = true;
    results = uvm.internal.parseSearchResults('github', response, query);
    for i = 1:numel(results)
        key = normalizeUrl(results(i).url);
        if known.isKey(key)
            entry = known(key);
            results(i).note = sprintf('listed as "%s" in registry "%s"', entry.name, entry.registry);
            results(i).add = ['uvm add ' entry.name];
        end
    end
    results = results(1:min(limit, end));
end

function [results, ok] = searchFileExchange(query, limit)
    ok = false;
    results = uvm.internal.parseSearchResults('none', []);
    options = weboptions('Timeout', 20, 'ContentType', 'json');
    try
        % The MATLAB Central community API, as used by mpm.
        response = webread('https://api.mathworks.com/community/v1/search', ...
            'query', query, 'scope', 'file-exchange', options);
    catch err
        warning('uvm:searchFailed', 'File Exchange search failed: %s', err.message);
        return
    end
    ok = true;
    results = uvm.internal.parseSearchResults('fex', response, query);
    results = results(1:min(limit, end));
end

function score = rank(name, query)
%RANK  Exact name matches first, then names containing the query.
    simplify = @(s) lower(regexprep(s, '[-_\s]', ''));
    score = 0;
    if strcmp(simplify(name), simplify(query))
        score = 2;
    elseif contains(simplify(name), simplify(query))
        score = 1;
    end
end

function url = normalizeUrl(url)
    url = lower(regexprep(strtrim(url), '(\.git)?/*$', ''));
end

function result = makeResult(source, name, url, description, stars, note, add)
    result = struct('source', source, 'name', name, 'url', url, 'description', description, ...
        'stars', stars, 'note', note, 'add', add);
end
