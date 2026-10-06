function results = run_dataset_tests()
%RUN_DATASET_TESTS Execute naming, paths, batch and GUI regression tests.
%   RESULTS is a matlab.unittest result array. Throws if any test fails.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,fullfile(root,'tests'));
files={'test_build_experiment_name.m','test_output_paths.m', ...
    'test_dataset_pipeline.m','test_dataset_gui.m'};
suite=testsuite(fullfile(root,'tests',files{1}));
for k=2:numel(files)
    suite=[suite,testsuite(fullfile(root,'tests',files{k}))]; %#ok<AGROW>
end
results=run(suite);
assert(all([results.Passed]),'pipeline:TestsFailed','Dataset tests failed or were incomplete.');
end
