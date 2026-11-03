function [v, parts] = versionParse(str)
%VERSIONPARSE  Parse 'v1.2.3', '1.2' or '1' into [major minor patch].
%   V is [] when STR is not a plain version (pre-release tags such as
%   v2.0.0-rc1 are ignored on purpose). PARTS is how many numbers were given.

    v = [];
    parts = 0;
    str = regexprep(strtrim(char(str)), '^[vV]', '');
    if isempty(regexp(str, '^\d+(\.\d+){0,2}$', 'once'))
        return
    end
    numbers = str2double(strsplit(str, '.'));
    parts = numel(numbers);
    v = [numbers, zeros(1, 3 - parts)];
end
