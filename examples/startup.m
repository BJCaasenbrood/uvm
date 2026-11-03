% Example startup.m for uvm.
%
% MATLAB runs startup.m once at launch. Put this file in your userpath
% folder (run "userpath" to see where that is), or merge it into the
% startup.m you already have. "uvm setup" writes the core of this for you;
% this version adds a default project for when MATLAB starts outside one.

% Make the uvm command available. Change this to where you keep uvm.
% (Not needed if you installed uvm as a toolbox.)
addpath('/home/brandon/Documents/projects/UVmatlab/toolbox');

% Activate the project in the folder MATLAB starts in. If MATLAB does not
% start inside a project, fall back to the one you use most. Activation
% only reads local files, so this is fast and works offline.
defaultProject = fullfile(getenv('HOME'), 'work', 'my_analysis');
try
    if ~isempty(uvm.internal.findRoot(pwd))
        uvm('activate', '--quiet');
    elseif isfolder(defaultProject)
        uvm('activate', defaultProject, '--quiet');
    end
catch uvmError
    % Never let a uvm problem stop MATLAB from starting.
    warning(uvmError.identifier, '%s', uvmError.message);
end

clear defaultProject
