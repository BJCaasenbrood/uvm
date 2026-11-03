function setupStartup(file, remove)
%SETUPSTARTUP  Add the uvm hook to startup.m, or REMOVE it.
%   The hook puts uvm itself on the path and activates the project in the
%   folder MATLAB starts in. FILE defaults to the startup.m on the path, or
%   one in userpath. Running it again replaces the existing hook.

    if isempty(file)
        file = which('startup');
        if isempty(file)
            folder = userpath;
            if isempty(folder)
                error('uvm:noUserpath', 'No userpath is set; choose a file with "uvm setup --file PATH".');
            end
            file = fullfile(folder, 'startup.m');
        end
    end

    text = '';
    if isfile(file)
        text = fileread(file);
    end
    [first, last] = regexp(text, '% >>> uvm >>>.*?% <<< uvm <<<\r?\n?', 'start', 'end', 'once');
    if ~isempty(first)
        text = [text(1:first - 1), text(last + 1:end)];
    end

    if ~remove
        toolboxDir = fileparts(which('uvm'));
        block = strjoin({
            '% >>> uvm >>>'
            '% Added by "uvm setup"; remove with "uvm setup --remove".'
            sprintf('addpath(''%s'');', strrep(toolboxDir, '''', ''''''))
            'try'
            '    uvm(''activate'', ''--quiet'');'
            'catch uvmError'
            '    warning(uvmError.identifier, ''%s'', uvmError.message);'
            'end'
            '% <<< uvm <<<'
            ''}, newline);
        if ~isempty(text) && ~endsWith(text, newline)
            text = [text newline];
        end
        text = [text block];
    end

    fid = fopen(file, 'w', 'n', 'UTF-8');
    if fid < 0
        error('uvm:writeFailed', 'Could not write %s.', file);
    end
    fwrite(fid, text, 'char');
    fclose(fid);
    if remove
        uvm.internal.say('Removed the uvm hook from %s', file);
    else
        uvm.internal.say('Added the uvm hook to %s', file);
    end
end
