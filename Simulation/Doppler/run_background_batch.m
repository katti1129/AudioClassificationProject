function [report,batchDir] = run_background_batch(config,batch,mode,progress)
%RUN_BACKGROUND_BATCH Sequential sweep using the unchanged acoustic renderer.
% Inputs: base config; sweep; mode='generate'/'check'; optional callback
% keepGoing=progress(stage,index,total,report). Called at safe phase boundaries.
% Outputs: per-condition table and unique batch directory (also for check).
% All conditions share Pa/FS and input/crop/calibration. No peak normalization.
% Cancel before saving aborts that condition; after saving keeps SUCCESS and
% leaves remaining conditions NOT_RUN. Saving one condition is not interrupted.
if nargin<3, mode='generate'; end
if nargin<4, progress=[]; end
if ~ismember(string(mode),["check","generate"]), error('backgroundBatch:Mode','mode must be check or generate.'); end
[report,configs]=background_batch_plan(config,batch);
parent=fullfile(config.outputRoot,'batches');
if ~isfolder(parent), mkdir(parent); end
% Keep IDs short: MATLAB's v7.3/HDF5 writer on Windows can fail beyond MAX_PATH.
batchDir=parent;
while isfolder(batchDir)
    [~,id]=fileparts(tempname(parent)); token=regexprep(id,'[^a-zA-Z0-9]','');
    batchId=string(['B_' token(end-11:end)]); batchDir=fullfile(parent,batchId);
end
mkdir(batchDir);
report.BatchID(:)=batchId;
invalid=report.Status=="INVALID"; report.Status(invalid)="FAIL"; report.Status(~invalid)="PENDING";
save(fullfile(batchDir,'batch_config.mat'),'config','batch','configs','mode');
persist(); total=height(report);
for index=1:total
    if ~notify('condition_start',index)
        cancelRemaining(index); break;
    end
    if isempty(configs{index})
        if ~notify('condition_done',index), cancelRemaining(index+1); break; end
        continue;
    end
    report.Status(index)="RUNNING"; persist();
    try
        c=configs{index};
        if strcmp(mode,'generate')
            c.outputRoot=fullfile(batchDir,report.ConditionID(index));
            if strlength(c.outputRoot)+80>=260
                error('backgroundBatch:PathTooLong','Choose a shorter outputRoot; nested WAV/MAT/PNG paths may exceed Windows limits.');
            end
            [r,output]=run_background_simulation(c,@phase);
            report.Status(index)="SUCCESS"; report.OutputDirectory(index)=string(output);
            report.OutputWav(index)=string(fullfile(output,'final.wav')); report.SimulationID(index)=r.simulationId;
        else
            if ~phase('simulation',0), error('background:Cancelled','Cancelled before simulation.'); end
            r=simulate_moving_receiver_rms(c);
            if ~phase('mixing',.55), error('background:Cancelled','Cancelled before mixing.'); end
            r=mix_background_audio(r,c.background);
            if ~phase('checking',.7), error('background:Cancelled','Cancelled during check.'); end
            report.Status(index)="PASS";
        end
        signals=[r.direct_signal,r.reflected_signal,r.siren_signal,r.background_signal,r.final_signal];
        peak=max(abs(signals),[],'all')/c.wavFullScalePa;
        if any(~isfinite(signals),'all') || ~isfinite(peak) || peak>=1
            error('background:Clipping','Common Pa/FS would clip; do not normalize individual conditions.');
        end
        report.PeakAllComponentsFS(index)=peak; report.OutputDurationSec(index)=numel(r.final_signal)/r.fs;
        b=r.backgroundInfo;
        report.ActualBackgroundStartSec(index)=b.ActualStartSec; report.ActualBackgroundEndSec(index)=b.ActualEndExclusiveSec;
        report.ActualBackgroundSplDb(index)=b.ActualBackgroundSplDb; report.ActualSnrDb(index)=b.ActualSnrDb;
        report.Message(index)="Completed";
        clear r signals;
    catch exception
        report.ErrorID(index)=string(exception.identifier); report.Message(index)=string(exception.message);
        if strcmp(exception.identifier,'background:Cancelled')
            report.Status(index)="CANCELLED"; cancelRemaining(index+1); persist(); break;
        end
        report.Status(index)="FAIL";
    end
    persist();
    if ~notify('condition_done',index)
        cancelRemaining(index+1); break;
    end
end
persist();
summary=table(batchId,string(mode),sum(report.Status=="SUCCESS"),sum(report.Status=="PASS"), ...
    sum(report.Status=="FAIL"),sum(report.Status=="CANCELLED"),sum(report.Status=="NOT_RUN"), ...
    'VariableNames',{'BatchID','Mode','Success','CheckPass','Fail','Cancelled','NotRun'});
writetable(summary,fullfile(batchDir,'batch_summary.csv'));
fprintf('Batch %s: %d success / %d check-pass / %d fail / %d cancelled / %d not-run\n%s\n', ...
    mode,summary.Success,summary.CheckPass,summary.Fail,summary.Cancelled,summary.NotRun,batchDir);
% Export only completed final signals; check mode never creates evaluation WAVs.
% A copy failure does not relabel a successful acoustic simulation as failed.
if strcmp(mode,'generate') && any(report.Status=="SUCCESS")
    try
        export_background_heatmap_dataset(batchDir,report);
    catch exception
        warning('backgroundBatch:HeatmapExport','WAV generation is retained, but AI export failed: %s',exception.message);
        exportFailure=table(string(exception.identifier),string(exception.message), ...
            'VariableNames',{'ErrorID','Message'});
        writetable(exportFailure,fullfile(batchDir,'heatmap_export_error.csv'));
    end
end

    function keepGoing = phase(stage,~)
        % Adapt the existing single-condition progress protocol (no signal edits).
        keepGoing=notify(stage,index);
    end
    function keepGoing = notify(stage,current)
        % Send immutable report snapshot to caller; empty callback always continues.
        keepGoing=true;
        if ~isempty(progress), keepGoing=progress(stage,current,total,report); end
    end
    function cancelRemaining(first)
        % Preserve completed/invalid rows; mark only pending rows unexecuted.
        pending=(1:height(report))'>=first & report.Status=="PENDING";
        report.Status(pending)="NOT_RUN"; report.Message(pending)="Cancelled before this condition.";
        persist();
    end
    function persist()
        % Replace only this run's manifest using a staged CSV in its own directory.
        temporary=fullfile(batchDir,'conditions.pending.csv');
        writetable(report,temporary);
        [ok,message]=movefile(temporary,fullfile(batchDir,'conditions.csv'),'f');
        if ~ok, error('backgroundBatch:Manifest','Cannot save manifest: %s',message); end
    end
end
