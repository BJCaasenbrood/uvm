function fields = lockFields()
%LOCKFIELDS  Fields of each package entry in uvm.lock, in file order.
%   name          package name (the key used in "dependencies")
%   version       resolved version, '' if the source has none
%   source        git URL or path
%   kind          'semver', 'tag', 'branch' or 'rev'
%   ref           tag, branch or revision that was resolved
%   commit        exact commit installed
%   paths         folders of the package that go on the path
%   toolboxes     MathWorks toolboxes the package needs
%   matlab        MATLAB release constraint of the package
%   dependencies  names of the packages it depends on

    fields = {'name', 'version', 'source', 'kind', 'ref', 'commit', ...
        'paths', 'toolboxes', 'matlab', 'dependencies'};
end
