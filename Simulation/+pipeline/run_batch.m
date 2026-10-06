function [manifest, attempts] = run_batch(rows, baseConfig, options)
%RUN_BATCH Execute each condition sequentially and checkpoint every outcome.
%   [MANIFEST,ATTEMPTS] = RUN_BATCH(ROWS,BASECONFIG,OPTIONS) continues after
%   row failures. One dataset lock prevents concurrent writers. Cancellation
%   is honored between simulations and remaining rows are marked CANCELLED.
%   OPTIONS.progressFcn receives completed,total,row,name,status,message.
if nargin<2, baseConfig=default_config(); end
if nargin<3, options=pipeline.default_options(); end
[rows,options]=pipeline.validate_config(rows,options);
datasetDir=options.datasetDir;
if ~isfolder(datasetDir), mkdir(datasetDir); end
lockDir=fullfile(datasetDir,'.batch_lock');
lockFile=java.io.File(lockDir);
assert(lockFile.mkdir(),'pipeline:DatasetLocked', ...
    'Dataset is already running, or .batch_lock remains after an interrupted run: %s',lockDir);
lockCleanup=onCleanup(@()rmdir(lockDir));
runID="RUN_"+string(char(java.util.UUID.randomUUID()));
runDir=fullfile(datasetDir,'_runs',char(runID));
mkdir(runDir);
pipeline.save_dataset_config(fullfile(runDir,'dataset_config.mat'),rows,baseConfig,options);
pipeline.save_dataset_config(fullfile(datasetDir,'dataset_config.mat'),rows,baseConfig,options);
templatePaths=pipeline.create_output_paths(datasetDir,'template');
template=struct2table(pipeline.manifest_record(rows(1,:),'template',templatePaths,runID));
manifest=template([],:); attempts=manifest;
stateFile=fullfile(datasetDir,'dataset_manifest.mat');
if isfile(stateFile)
    prior=load(stateFile,'manifest','attempts');
    assert(isequal(prior.manifest.Properties.VariableNames,manifest.Properties.VariableNames), ...
        'pipeline:ManifestSchema','Existing manifest schema is incompatible.');
    manifest=prior.manifest; attempts=prior.attempts;
end
excelOK=true; cancelled=false;
for k=1:height(rows)
    clock=tic;
    drawnow;
    if ~cancelled && ~isempty(options.cancelFcn), cancelled=logical(options.cancelFcn()); end
    row=rows(k,:);
    name="INVALID_"+runID+"_ROW"+string(k);
    paths=pipeline.create_output_paths(datasetDir,name);
    record=pipeline.manifest_record(row,name,paths,runID);
    archiveDir=""; protected=false; config=[];
    try
        config=pipeline.row_to_config(row,baseConfig,false);
        name=pipeline.build_experiment_name(config);
        if cancelled
            paths=pipeline.create_output_paths(datasetDir,name);
            record=pipeline.manifest_record(row,name,paths,runID);
            record.Status="CANCELLED"; protected=true;
        else
            [paths,skip,archiveDir]=pipeline.resolve_collision(datasetDir,name,options.collisionPolicy);
            name=paths.name;
            record=pipeline.manifest_record(row,name,paths,runID);
            record.ArchiveFolder=archiveDir;
            if skip
                record.Status="SKIPPED"; protected=true;
            else
                notify(k-1,k,name,"RUNNING","");
                % Saved before computation so even a hard interruption has the
                % exact row/config and a diagnostic destination.
                if ~isfolder(paths.resultDir), mkdir(paths.resultDir); end
                save(fullfile(paths.resultDir,'requested_condition.mat'),'row','config','-v7');
                [result,transcript]=runWithLog(config,paths,options);
                try
                    writeText(fullfile(paths.resultDir,'matlab_log.txt'),transcript);
                catch logError
                    warning('pipeline:ConsoleLog','%s',logError.message);
                end
                record.Status="SUCCESS";
                record.SampleRateHz=result.sampleRateHz;
                record.PaPerFullScale=result.output.paPerFullScale;
                record.AdaptiveScaleUsed=result.output.adaptiveScaleUsed;
                record.ObstacleCount=numel(result.obstacles);
                record.ObservedHorizontalCPAM=result.pipeline.observedHorizontalCPAM;
                record.ObservedCPATimeSec=result.pipeline.observedCPATimeSec;
                record.Observed3DMinimumM=result.pipeline.observed3DMinimumM;
                record.MultipleDiffractionApproximationFrames=nnz(result.diffraction.multiplePathApproximationUsed);
                record.UnsupportedDiffractionFrames=nnz(result.diffraction.unsupportedMultiplePath);
                record.WarningText=string(transcript(1:min(end,8000)));
                clear result;
            end
        end
    catch exception
        record.Status="FAILED";
        record.ErrorIdentifier=string(exception.identifier);
        record.ErrorMessage=string(exception.message);
        record.ArchiveFolder=archiveDir;
        if ~isfolder(paths.resultDir), mkdir(paths.resultDir); end
        writeText(paths.logFile,sprintf('Experiment: %s\nStatus: FAILED\n%s', ...
            record.ID,getReport(exception,'extended','hyperlinks','off')));
        save(fullfile(paths.resultDir,'requested_condition.mat'),'row','baseConfig','config','-v7');
    end
    record.ElapsedSec=toc(clock);
    rowRecord=struct2table(record);
    attempts=[attempts;rowRecord]; %#ok<AGROW>
    found=find(manifest.ID==record.ID,1);
    % Skip/cancel cannot relabel or replace a previously successful artifact.
    if isempty(found)
        manifest=[manifest;rowRecord]; %#ok<AGROW>
    elseif ~protected
        manifest(found,:)=rowRecord;
    end
    excelOK=pipeline.write_manifest(datasetDir,manifest,attempts);
    notify(k,k,record.ID,record.Status,record.ErrorMessage);
end
if ~excelOK
    warning('pipeline:ManifestExcelStale', ...
        'Close Excel and call pipeline.write_manifest(datasetDir,manifest,attempts) to refresh XLSX.');
end

    function notify(completed,index,experiment,status,message)
        %NOTIFY Deliver progress without allowing a UI error to lose batch data.
        event=struct('completed',completed,'total',height(rows),'row',index, ...
            'name',string(experiment),'status',string(status),'message',string(message));
        if isempty(options.progressFcn)
            fprintf('%d / %d  %s  %s\n',completed,height(rows),status,experiment);
        else
            try
                options.progressFcn(event);
            catch callbackError
                warning('pipeline:ProgressCallback','%s',callbackError.message);
            end
        end
    end
end

function [result,transcript]=runWithLog(config,paths,options)
%RUNWITHLOG Capture MATLAB diagnostics outside the nested/static workspace.
runner=@()pipeline.run_single(config,paths,options); %#ok<NASGU> Used by evalc.
[transcript,result]=evalc('runner()');
end

function writeText(filename,value)
%WRITETEXT Write UTF-8 diagnostic text and close the stream on errors.
fid=fopen(filename,'w','n','UTF-8');
assert(fid>=0,'pipeline:LogWrite','Cannot write diagnostic: %s',filename);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s',value);
end
