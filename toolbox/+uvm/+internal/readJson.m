function data = readJson(file)
%READJSON  Decode a JSON file, naming the file if it is malformed.

    try
        data = jsondecode(fileread(file));
    catch err
        error('uvm:badJson', 'Could not parse %s: %s', file, err.message);
    end
end
