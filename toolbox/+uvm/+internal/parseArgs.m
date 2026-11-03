function [opts, positional] = parseArgs(args, flags, options)
%PARSEARGS  Split command arguments into flags, options and positionals.
%   FLAGS are switches such as '--upgrade' (logical in OPTS); OPTIONS take a
%   value, such as '--tag v1.0' ('' when absent). Field names drop the
%   leading dashes and use underscores, so '--dry-run' becomes OPTS.dry_run.

    opts = struct();
    for f = flags
        opts.(fieldName(f{1})) = false;
    end
    for o = options
        opts.(fieldName(o{1})) = '';
    end
    positional = {};
    i = 1;
    while i <= numel(args)
        arg = args{i};
        if any(strcmp(arg, flags))
            opts.(fieldName(arg)) = true;
        elseif any(strcmp(arg, options))
            if i == numel(args)
                error('uvm:badArgs', 'Option %s needs a value.', arg);
            end
            opts.(fieldName(arg)) = args{i + 1};
            i = i + 1;
        elseif startsWith(arg, '--')
            error('uvm:badArgs', 'Unknown option %s.', arg);
        else
            positional{end + 1} = arg; %#ok<AGROW>
        end
        i = i + 1;
    end
end

function name = fieldName(flag)
    name = strrep(flag(3:end), '-', '_');
end
