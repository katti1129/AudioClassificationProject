function [rows, options] = validate_config(rows, options)
%VALIDATE_CONFIG Validate batch shape/options; per-row errors are isolated later.
%   Returns normalized ROWS/OPTIONS, preserving invalid row values for FAILED logging.
assert(istable(rows)&&height(rows)>0,'pipeline:EmptyConditions','At least one row is required.');
schema=pipeline.condition_schema();
assert(all(ismember(schema.names,rows.Properties.VariableNames)), ...
    'pipeline:Schema','Missing condition columns.');
rows=rows(:,schema.names);
rows.InputWAV=string(rows.InputWAV);
rows.Profile=string(rows.Profile);
defaults=pipeline.default_options();
fields=fieldnames(defaults);
for k=1:numel(fields)
    if ~isfield(options,fields{k}), options.(fields{k})=defaults.(fields{k}); end
end
name=char(string(options.datasetName));
assert(~isempty(regexp(name,'^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$','once')), ...
    'pipeline:DatasetName','Dataset name: 1-48 ASCII letters/digits/_/-, starting with letter/digit.');
assert(isempty(regexp(upper(name),'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$','once')), ...
    'pipeline:DatasetName','Reserved Windows filename.');
assert(ismember(string(options.collisionPolicy),["Rename","Skip","Overwrite"]), ...
    'pipeline:CollisionPolicy','Choose Rename, Skip or Overwrite.');
options.datasetParent=char(java.io.File(char(options.datasetParent)).getCanonicalPath());
options.datasetName=name;
options.datasetDir=fullfile(options.datasetParent,name);
assert(isempty(options.progressFcn)||isa(options.progressFcn,'function_handle'), ...
    'pipeline:Callback','progressFcn must be a function handle.');
assert(isempty(options.cancelFcn)||isa(options.cancelFcn,'function_handle'), ...
    'pipeline:Callback','cancelFcn must be a function handle.');
for field={'writeFigures','writeMat'}
    validateattributes(options.(field{1}),{'logical','numeric'},{'scalar','binary'});
    options.(field{1})=logical(options.(field{1}));
end
end

