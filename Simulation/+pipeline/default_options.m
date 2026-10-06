function options = default_options()
%DEFAULT_OPTIONS Return batch/output settings (no acoustic parameters).
%   OPTIONS contains dataset parent/name, collision policy and output flags.
root = fileparts(fileparts(mfilename('fullpath')));
options.datasetParent = fullfile(root,'datasets');
options.datasetName = 'Dataset_001';
options.collisionPolicy = 'Rename'; % Rename | Skip | Overwrite (archives old files)
options.writeFigures = true;
options.writeMat = true;
options.progressFcn = [];           % Callback(event struct), once per row boundary
options.cancelFcn = [];             % Callback() -> logical, checked between rows
end

