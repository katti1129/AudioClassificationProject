function reports = run_all_tests()
%RUN_ALL_TESTS Run analytic, scenario, and output validation suites.
%   REPORTS = RUN_ALL_TESTS() executes all simulator checks. REPORTS.unit
%   contains analytic/function tests, REPORTS.scenario contains short
%   full-pipeline cases, and REPORTS.output contains real-WAV artifact
%   read-back checks. The output test leaves its products under
%   data/output/validation/VALIDATION_OUTPUT_SMOKE.

rootDirectory=fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(rootDirectory));
reports.unit=run_validation_tests();
reports.scenario=run_scenario_tests();
reports.output=run_output_validation();
end
