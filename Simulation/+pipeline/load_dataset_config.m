function [rows, baseConfig, options] = load_dataset_config(filename)
%LOAD_DATASET_CONFIG Load and check a saved table/base config/options snapshot.
%   Acoustic row validation is deferred until batch execution.
data=load(filename,'datasetConfig');
assert(isfield(data,'datasetConfig')&&data.datasetConfig.schemaVersion==1, ...
    'pipeline:ConfigVersion','Unsupported or missing datasetConfig schema.');
baseConfig=data.datasetConfig.baseConfig;
[rows,options]=pipeline.validate_config(data.datasetConfig.rows,data.datasetConfig.options);
options.progressFcn=[]; options.cancelFcn=[];
end

