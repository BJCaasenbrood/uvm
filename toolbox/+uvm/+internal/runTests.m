function results = runTests(project, target, junitFile)
%RUNTESTS  Run the tests in TARGET (default: the project's tests folder).
%   JUNITFILE, if not empty, receives a JUnit XML report that CI servers
%   such as GitLab and Jenkins display.

    if isempty(target)
        target = fullfile(project.root, 'tests');
        if ~isfolder(target)
            target = project.root;
        end
    end
    suite = testsuite(target, 'IncludeSubfolders', true);
    if isempty(suite)
        warning('uvm:noTests', 'No tests found in %s.', target);
    end
    runner = matlab.unittest.TestRunner.withTextOutput();
    if ~isempty(junitFile)
        runner.addPlugin(matlab.unittest.plugins.XMLPlugin.producingJUnitFormat(junitFile));
    end
    results = runner.run(suite);
    uvm.internal.say('%d passed, %d failed, %d incomplete', ...
        nnz([results.Passed]), nnz([results.Failed]), nnz([results.Incomplete]));
end
