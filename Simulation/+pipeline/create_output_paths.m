function paths = create_output_paths(datasetDir, name)
%CREATE_OUTPUT_PATHS Return canonical per-experiment paths without writing.
%   Final WAVs are flat in audio/; all diagnostics share NAME below
%   simulation_results/. NAME cannot contain separators or traversal.
name=char(string(name));
assert(~isempty(regexp(name,'^[A-Za-z0-9_-]+$','once')), ...
    'pipeline:UnsafeName','Experiment names must contain only A-Z, 0-9, _ or -.');
datasetDir=char(java.io.File(char(datasetDir)).getCanonicalPath());
paths.datasetDir=datasetDir;
paths.name=string(name);
paths.audioDir=fullfile(datasetDir,'audio');
paths.resultDir=fullfile(datasetDir,'simulation_results',name);
paths.wavFile=fullfile(paths.audioDir,[name,'.wav']);
paths.excelDir=fullfile(paths.resultDir,'excel');
paths.excelFile=fullfile(paths.excelDir,'metadata.xlsx');
paths.figureDir=fullfile(paths.resultDir,'figures');
paths.matFile=fullfile(paths.resultDir,'physical_results.mat');
paths.configFile=fullfile(paths.resultDir,'config.mat');
paths.logFile=fullfile(paths.resultDir,'run_info.txt');
end
