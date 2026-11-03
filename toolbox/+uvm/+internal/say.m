function out = say(varargin)
%SAY  Print a progress message unless uvm runs quietly.
%   uvm.internal.say(FMT, ...) prints one line.
%   OLD = uvm.internal.say('quiet', TF) sets quiet mode and returns the old setting.

    persistent quiet
    if isempty(quiet)
        quiet = false;
    end
    if nargin == 2 && strcmp(varargin{1}, 'quiet') && islogical(varargin{2})
        out = quiet;
        quiet = varargin{2};
        return
    end
    if ~quiet
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
