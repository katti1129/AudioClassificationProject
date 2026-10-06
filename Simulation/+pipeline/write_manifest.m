function excelOK = write_manifest(datasetDir, manifest, attempts)
%WRITE_MANIFEST Checkpoint MAT/CSV and atomically replace the XLSX view.
%   Manifest has one current record per experiment name; Attempts retains
%   every requested row including Skip/Overwrite/failure. Locked XLSX does
%   not erase progress: MAT/CSV remain current and Excel can be regenerated.
stateFile=fullfile(datasetDir,'dataset_manifest.mat');
tempState=[tempname(datasetDir),'.mat'];
save(tempState,'manifest','attempts','-v7');
movefile(tempState,stateFile,'f');
tempCSV=[tempname(datasetDir),'.csv'];
writetable(manifest,tempCSV,'Encoding','UTF-8');
movefile(tempCSV,fullfile(datasetDir,'dataset_manifest.csv'),'f');
tempExcel=[tempname(datasetDir),'.xlsx'];
excelOK=true;
try
    writetable(manifest,tempExcel,'Sheet','Manifest');
    writetable(attempts,tempExcel,'Sheet','Attempts');
    movefile(tempExcel,fullfile(datasetDir,'dataset_manifest.xlsx'),'f');
catch exception
    excelOK=false;
    warning('pipeline:ExcelCheckpoint', ...
        'XLSX update failed; MAT/CSV checkpoint is current. %s',exception.message);
    if isfile(tempExcel), delete(tempExcel); end
end
end

