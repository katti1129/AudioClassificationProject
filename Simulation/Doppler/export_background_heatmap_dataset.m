function [manifest,datasetDir] = export_background_heatmap_dataset(batchDir,report)
%EXPORT_BACKGROUND_HEATMAP_DATASET Copy successful final WAVs for AI evaluation.
% Inputs: batchDir containing conditions.csv; optional in-memory report table.
% Outputs: manifest (original conditions + export status/path), datasetDir.
% CPA filename tag = requested horizontal closest distance [m]; V = source
% speed [km/h]. Copies are byte-identical: no resampling or normalization.
% Each invocation creates a new folder; original WAVs/results are untouched.
if nargin<2
    report=readtable(fullfile(batchDir,'conditions.csv'),'TextType','string');
end
required={'Status','OutputWav','HorizontalCpaRequestedM','SourceSpeedKmh'};
if ~all(ismember(required,report.Properties.VariableNames))
    error('heatmapExport:Columns','Batch report is missing required columns.');
end
eligible=string(report.Status)=="SUCCESS";
names=strings(height(report),1);
for k=find(eligible)'
    d=report.HorizontalCpaRequestedM(k); v=report.SourceSpeedKmh(k);
    validateattributes(d,{'numeric'},{'scalar','real','finite','nonnegative'});
    validateattributes(v,{'numeric'},{'scalar','real','finite','nonnegative'});
    distance=sprintf('%.15f',d); distance=regexprep(distance,'\.?0+$','');
    if isempty(distance), distance='0'; end
    if v==fix(v)
        speed=sprintf('%03.0f',v);
    else
        speed=sprintf('%.15f',v); speed=regexprep(speed,'0+$','');
    end
    names(k)=string(sprintf('ambulance_CPA%sm_V%s.wav',distance,speed));
end
if numel(unique(names(eligible)))~=sum(eligible)
    error('heatmapExport:Duplicate','CPA/V filenames collide. Export each batch separately.');
end
datasetDir=fullfile(batchDir,'heatmap_wavs');
while isfolder(datasetDir) || isfile(datasetDir)
    [~,token]=fileparts(tempname(batchDir));
    datasetDir=fullfile(batchDir,['heatmap_wavs_' token(end-7:end)]);
end
mkdir(datasetDir);
manifest=report;
manifest.EvaluationFileName=names;
manifest.EvaluationWav=strings(height(report),1);
manifest.ExportStatus=repmat("SKIPPED",height(report),1);
manifest.ExportError=strings(height(report),1);
for k=find(eligible)'
    % Stage without a .wav suffix so incomplete copies are not evaluated.
    temporary=fullfile(datasetDir,'copy.pending');
    cleanup=onCleanup(@()removeTemporary(temporary));
    try
        source=char(report.OutputWav(k));
        if ~isfile(source), error('heatmapExport:MissingSource','Missing final WAV: %s',source); end
        target=fullfile(datasetDir,names(k));
        [ok,message]=copyfile(source,temporary);
        if ~ok, error('heatmapExport:Copy','%s',message); end
        if ~isequal(readBytes(source),readBytes(temporary))
            error('heatmapExport:Verify','Copied bytes differ from source: %s',source);
        end
        [ok,message]=movefile(temporary,target);
        if ~ok, error('heatmapExport:Move','%s',message); end
        manifest.EvaluationWav(k)=string(target);
        manifest.ExportStatus(k)="COPIED";
    catch exception
        manifest.ExportStatus(k)="FAIL";
        manifest.ExportError(k)=string(exception.identifier)+": "+string(exception.message);
    end
    clear cleanup;
end
writetable(manifest,fullfile(datasetDir,'evaluation_manifest.csv'));
fprintf('AI evaluation WAVs: %d copied / %d failed / %d skipped\n%s\n', ...
    sum(manifest.ExportStatus=="COPIED"),sum(manifest.ExportStatus=="FAIL"), ...
    sum(manifest.ExportStatus=="SKIPPED"),datasetDir);
if any(manifest.ExportStatus=="FAIL")
    warning('heatmapExport:Partial','Some copies failed. Inspect evaluation_manifest.csv. Original outputs are unchanged.');
end
end

function bytes = readBytes(path)
% Read one WAV as bytes for exact-copy verification; no audio decoding.
fid=fopen(path,'rb');
if fid<0, error('heatmapExport:Read','Cannot read %s',path); end
cleanup=onCleanup(@()fclose(fid));
bytes=fread(fid,Inf,'*uint8');
end

function removeTemporary(path)
% Remove only this invocation's incomplete staging file, never source WAVs.
if isfile(path), delete(path); end
end
