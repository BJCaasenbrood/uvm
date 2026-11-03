function writeJson(file, data)
%WRITEJSON  Write DATA as pretty-printed JSON.

    fid = fopen(file, 'w', 'n', 'UTF-8');
    if fid < 0
        error('uvm:writeFailed', 'Could not write %s.', file);
    end
    closer = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(data, 'PrettyPrint', true));
end
