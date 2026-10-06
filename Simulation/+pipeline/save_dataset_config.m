function save_dataset_config(filename, rows, baseConfig, options)
%SAVE_DATASET_CONFIG Save reproducible condition table/base config/options to MAT.
%   Callback handles are excluded. A temporary file protects previous snapshots.
[rows,options]=pipeline.validate_config(rows,options);
options.progressFcn=[]; options.cancelFcn=[];
datasetConfig.schemaVersion=1;
datasetConfig.rows=rows;
datasetConfig.baseConfig=baseConfig;
datasetConfig.options=options;
datasetConfig.savedAt=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
parent=fileparts(char(filename));
if isempty(parent), parent=pwd; end
if ~isfolder(parent), mkdir(parent); end
temporary=[tempname(parent),'.mat'];
save(temporary,'datasetConfig','-v7');
movefile(temporary,filename,'f');
end

