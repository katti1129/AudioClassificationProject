function [checks,reportDir] = test_background_batch()
%TEST_BACKGROUND_BATCH Analytic geometry, cancellation, export and real WAV sweep.
% Input: none. Outputs: checks CSV and report folder. Creates short deterministic
% fixtures plus the full 12-condition real ambulance/engine sweep (PNG off).
% Numerical/UI/I-O tests only, not listening tests or validation against field data.
config=background_simulation_config(); config.figureVisible='off';
parent=fullfile(fileparts(fileparts(mfilename('fullpath'))),'data','output','doppler_batch_tests');
if ~isfolder(parent), mkdir(parent); end
[~,id]=fileparts(tempname(parent)); token=regexprep(id,'[^a-zA-Z0-9]','');
reportDir=fullfile(parent,['T_' token(end-11:end)]); mkdir(reportDir);
rows=cell(0,4); batch=background_batch_config();
record('parse_literal_list',norm(parse_background_batch_values('5, 10;20 40')-[5,10,20,40]),0);
reject('reject_expression',@()parse_background_batch_values('1:3'),'backgroundBatch:List');
reject('reject_code_string',@()parse_background_batch_values('system(1)'),'backgroundBatch:List');
reject('reject_nan',@()parse_background_batch_values('1, NaN'),'backgroundBatch:List');
reject('reject_duplicates',@()parse_background_batch_values('5,5'),'backgroundBatch:Duplicate');
[plan,configs]=background_batch_plan(config,batch);
record('default_12_conditions',abs(height(plan)-12),0);
record('default_all_ready',sum(plan.Status~="READY"),0);
for k=1:numel(configs)
    c=configs{k}; t=plan.CpaRequestedSec(k); s=c.source.positionM+t*c.source.velocityMps; r=c.receiver.positionM+t*c.receiver.velocityMps;
    delta=s-r; v=c.source.velocityMps-c.receiver.velocityMps;
    record(sprintf('geometry_distance_%02d',k),abs(norm(delta(1:2))-plan.HorizontalCpaRequestedM(k)),1e-11);
    record(sprintf('geometry_orthogonal_%02d',k),abs(dot(delta,v)),1e-10);
    record(sprintf('geometry_time_%02d',k),abs(plan.GeometricCpaTimeSec(k)-batch.cpaTimeSec),1e-12);
    record(sprintf('geometry_3d_%02d',k),abs(norm(delta)-hypot(plan.HorizontalCpaRequestedM(k),.3)),1e-11);
    record(sprintf('local_minimum_%02d',k),double(norm(delta+v*.1)<=norm(delta) || norm(delta-v*.1)<=norm(delta)),0);
    record(sprintf('receiver_unchanged_%02d',k),double(~isequal(c.receiver,config.receiver)),0);
    record(sprintf('common_background_%02d',k),double(~isequal(c.background,config.background)),0);
    record(sprintf('common_scale_%02d',k),abs(c.wavFullScalePa-config.wavFullScalePa),0);
end
cross=config; cross.receiver.velocityMps=[.4,1.3,0]; diagonal=batch; diagonal.sourceHeadingDeg=37;
[p,cc]=background_batch_plan(cross,diagonal);
for k=1:numel(cc)
    c=cc{k}; d=c.source.positionM-c.receiver.positionM+(c.source.velocityMps-c.receiver.velocityMps)*diagonal.cpaTimeSec;
    record(sprintf('crossing_receiver_geometry_%02d',k),abs(norm(d(1:2))-p.HorizontalCpaRequestedM(k)),1e-10);
end
bad=batch; bad.sourceSpeedsKmh=1.4*3.6; [p,cc]=background_batch_plan(config,bad);
record('equal_velocity_invalid',sum(p.Status~="INVALID")+sum(~cellfun(@isempty,cc)),0);
bad=batch; bad.sourceSpeedsKmh=config.c*3.6;
p=background_batch_plan(config,bad); record('sonic_source_invalid',sum(p.Status~="INVALID"),0);
bad=batch; bad.cpaTimeSec=100; reject('cpa_outside_emission',@()background_batch_plan(config,bad),'backgroundBatch:CpaRange');
bad=batch; bad.distancesM=[5,5]; reject('duplicate_plan',@()background_batch_plan(config,bad),'backgroundBatch:Duplicate');
bad=batch; bad.distancesM=1:1001; reject('condition_limit',@()background_batch_plan(config,bad),'backgroundBatch:TooMany');
% Short deterministic fixtures keep lifecycle/error tests inexpensive.
fs=config.fs; t=(0:fs-1)'/fs;
fixture=fullfile(reportDir,'fixture.wav'); bg=fullfile(reportDir,'background_fixture.wav');
audiowrite(fixture,.3*sin(2*pi*500*t),fs); audiowrite(bg,.2*sin(2*pi*211*t),fs);
small=config; small.inputFile=fixture; small.makeFigures=false; small.outputRoot=fullfile(reportDir,'synthetic');
small.background.file=bg; small.background.durationSec=.2; small.background.startOffsetSec=-.1;
sweep=batch; sweep.distancesM=[5,10]; sweep.sourceSpeedsKmh=[20,60]; sweep.cpaTimeSec=.4;
[dry,folder]=run_background_batch(small,sweep,'check');
record('dry_4_pass',sum(dry.Status~="PASS"),0);
record('dry_no_wavs',numel(dir(fullfile(folder,'**','*.wav'))),0);
record('dry_manifest_readable',abs(height(readtable(fullfile(folder,'conditions.csv')))-4),0);
for stage={'condition_start','simulation','mixing','saving'}
    stopStage=stage{1};
    [cancelled,folder]=run_background_batch(small,sweep,'generate',@(current,~,~,~)~strcmp(current,stopStage));
    record(['cancel_no_wav_' stopStage],numel(dir(fullfile(folder,'**','*.wav'))),0);
    record(['cancel_all_accounted_' stopStage],sum(~ismember(cancelled.Status,["CANCELLED","NOT_RUN"])),0);
end
[partial,folder]=run_background_batch(small,sweep,'generate',@(stage,k,~,~)~(strcmp(stage,'condition_done') && k==1));
record('cancel_after_save_keeps_success',double(partial.Status(1)~="SUCCESS"),0);
record('cancel_after_save_remaining_not_run',sum(partial.Status(2:end)~="NOT_RUN"),0);
record('cancel_after_save_keeps_5_components_and_1_copy',abs(numel(dir(fullfile(folder,'**','*.wav')))-6),0);
exported=readtable(fullfile(folder,'heatmap_wavs','evaluation_manifest.csv'),'TextType','string');
record('partial_export_success_only',abs(sum(exported.ExportStatus=="COPIED")-1)+abs(sum(exported.ExportStatus=="SKIPPED")-3),0);
record('export_expected_filename',double(exported.EvaluationFileName(1)~="ambulance_CPA5m_V020.wav"),0);
[~,again]=export_background_heatmap_dataset(folder,partial);
record('repeat_export_does_not_overwrite',double(strcmp(again,fullfile(folder,'heatmap_wavs'))),0);
missing=partial; missing.OutputWav(1)=string(fullfile(folder,'missing.wav'));
failedCopy=export_background_heatmap_dataset(folder,missing);
record('missing_copy_is_reported',double(failedCopy.ExportStatus(1)~="FAIL"),0);
duplicate=partial([1,1],:);
reject('duplicate_export_names_rejected',@()export_background_heatmap_dataset(folder,duplicate),'heatmapExport:Duplicate');
decimal=partial(1,:); decimal.HorizontalCpaRequestedM=10.5; decimal.SourceSpeedKmh=20.5;
decimalCopy=export_background_heatmap_dataset(folder,decimal);
record('decimal_export_name',double(decimalCopy.EvaluationFileName~="ambulance_CPA10.5m_V20.5.wav"),0);
invalid=sweep; invalid.sourceSpeedsKmh=[1.4*3.6,60];
[p,~]=run_background_batch(small,invalid,'check');
record('invalid_rows_fail_valid_rows_continue',abs(sum(p.Status=="FAIL")-2)+abs(sum(p.Status=="PASS")-2),0);
clipping=small; clipping.wavFullScalePa=10; clipSweep=sweep; clipSweep.distancesM=[1,100]; clipSweep.sourceSpeedsKmh=60;
[p,~]=run_background_batch(clipping,clipSweep,'generate');
record('clip_near_fails_far_continues',double(p.Status(1)~="FAIL" || p.Status(2)~="SUCCESS"),0);
record('clip_error_id',double(p.ErrorID(1)~="background:Clipping"),0);
record('failed_clip_no_output',double(strlength(p.OutputWav(1))~=0),0);
record('clip_common_scale_preserved',max(abs(p.WavFullScalePa-10)),0);
% Actual GUI tab, shared settings, stale state, input errors and save/load.
a=background_simulation_gui(small,'off'); guiCleanup=onCleanup(@()delete(a.figure));
a.batch.setSettings(sweep); a.tabs.SelectedTab=a.batch.tab;
p=a.batch.plan(); record('gui_4_conditions',abs(height(p)-4),0);
record('gui_single_config_not_overwritten',double(~isequal(a.getConfig().source,small.source)),0);
settingsFile=fullfile(reportDir,'batch_gui_settings.mat'); a.saveConfig(settingsFile);
a.batch.controls.distance.Value='99'; a.loadConfig(settingsFile);
record('gui_batch_settings_roundtrip',double(~isequal(a.batch.getSettings(),sweep)),0);
a.batch.controls.distance.Value='1:3'; a.batch.controls.planButton.ButtonPushedFcn([],[]);
record('gui_invalid_list_shown',double(~strcmp(a.batch.getState().lastError,'backgroundBatch:List')),0);
a.batch.setSettings(sweep);
[p,~]=a.batch.check(); record('gui_check_4_pass',sum(p.Status~="PASS"),0);
record('gui_check_releases_shared_lock',double(a.getState().busy),0);
record('gui_check_reenables_single',double(~strcmp(a.controls.generateButton.Enable,'on')),0);
% Cancel via queued GUI event and reject a concurrent single-condition run.
eventSeen=false; locked=false;
timerObject=timer('ExecutionMode','fixedSpacing','Period',.02,'StartDelay',.01,'TimerFcn',@cancelGui);
timerCleanup=onCleanup(@()deleteTimer(timerObject));
start(timerObject); [p,~]=a.batch.generate(); stop(timerObject);
record('gui_cancel_event',double(~eventSeen),0); record('gui_prevents_single_overlap',double(~locked),0);
record('gui_cancel_releases_lock',double(a.getState().busy),0);
record('gui_cancel_leaves_unrun',sum(~ismember(p.Status,["CANCELLED","NOT_RUN"])),0);
% Generate the proposed 4 distances x 3 speeds with the full real ambulance WAV.
realConfig=config; realConfig.makeFigures=false; realConfig.outputRoot=fullfile(reportDir,'real_wav');
a.setConfig(realConfig); a.batch.setSettings(batch);
a.batch.plan(); exportapp(a.figure,fullfile(reportDir,'batch_plan_gui.png'));
[realReport,realDir]=a.batch.generate();
record('real_12_success',sum(realReport.Status~="SUCCESS"),0);
assert(all(realReport.Status=="SUCCESS"),'Real sweep failed; inspect batch manifest before loading WAV results.');
record('real_fixed_background_spl',max(abs(realReport.ActualBackgroundSplDb-80)),1e-10);
record('real_cpa_common',max(abs(realReport.GeometricCpaTimeSec-4)),1e-12);
record('real_insertion_start_common',max(abs(realReport.ActualBackgroundStartSec-2)),1/config.fs);
record('real_12_wav_paths_unique',abs(numel(unique(realReport.OutputWav))-12),0);
exported=readtable(fullfile(realDir,'heatmap_wavs','evaluation_manifest.csv'),'TextType','string');
record('real_12_exported',sum(exported.ExportStatus~="COPIED"),0);
record('real_flat_12_wavs',abs(numel(dir(fullfile(realDir,'heatmap_wavs','*.wav')))-12),0);
referenceBackground=[];
for k=1:height(realReport)
    loaded=load(fullfile(realReport.OutputDirectory(k),'result.mat'),'result'); r=loaded.result;
    b=r.background_signal(r.background_interval_mask);
    if isempty(referenceBackground), referenceBackground=b; end
    record(sprintf('real_same_background_samples_%02d',k),max(abs(b-referenceBackground)),0);
    [wav,actualFs]=audioread(realReport.OutputWav(k));
    [copied,copyFs]=audioread(exported.EvaluationWav(k));
    record(sprintf('real_export_sample_identity_%02d',k),double(~isequal(wav,copied) || copyFs~=actualFs),0);
    record(sprintf('real_wav_fs_%02d',k),abs(actualFs-config.fs),0);
    record(sprintf('real_wav_quantization_%02d',k),max(abs(wav-r.final_signal/config.wavFullScalePa)),2^-23);
    record(sprintf('real_wav_unclipped_%02d',k),double(any(abs(wav)>=1)),0);
    record(sprintf('real_sum_%02d',k),max(abs(r.final_signal-r.siren_signal-r.background_signal)),1e-12);
    if ismember(k,[1,height(realReport)])
        ref=mix_background_audio(simulate_moving_receiver_rms(r.config),r.config.background);
        record(sprintf('real_single_renderer_identity_%02d',k),max(abs(r.final_signal-ref.final_signal)),0);
    end
end
exportapp(a.figure,fullfile(reportDir,'batch_results_gui.png'));
record('gui_after_generation_unlocked',double(a.getState().busy),0);
manifest=readtable(fullfile(realDir,'conditions.csv'),'TextType','string');
record('real_manifest_12_rows',abs(height(manifest)-12),0);
record('real_manifest_success',sum(manifest.Status~="SUCCESS"),0);
writetable(table(string(realDir),'VariableNames',{'RealBatchDirectory'}),fullfile(reportDir,'real_batch_directory.csv'));
checks=cell2table(rows,'VariableNames',{'Test','Value','Tolerance','Status'});
fprintf('Batch tests: %d PASS / %d FAIL\n%s\n',sum(strcmp(checks.Status,'PASS')),sum(strcmp(checks.Status,'FAIL')),reportDir);
assert(all(strcmp(checks.Status,'PASS')),'Batch regression failed; see batch_checks.csv.');

    function record(name,value,tolerance)
        % Flush each criterion for auditability even if a later test interrupts.
        status='FAIL'; if isfinite(value) && value<=tolerance, status='PASS'; end
        rows(end+1,:)={name,value,tolerance,status};
        writetable(cell2table(rows,'VariableNames',{'Test','Value','Tolerance','Status'}),fullfile(reportDir,'batch_checks.csv'));
    end
    function reject(name,callback,identifier)
        % Require the expected exception ID, not merely any exception.
        matched=false;
        try
            callback();
        catch exception
            matched=strcmp(exception.identifier,identifier);
        end
        record(name,double(~matched),0);
    end
    function cancelGui(~,~)
        % Simulate user cancellation at a safe event boundary and test shared lock.
        if ~a.getState().busy, return; end
        stop(timerObject);
        eventSeen=true;
        try
            a.generate();
        catch exception
            locked=strcmp(exception.identifier,'backgroundGUI:Busy');
        end
        a.cancel();
    end
end

function deleteTimer(timerObject)
% Clean up only the timer created by this test.
if isvalid(timerObject), stop(timerObject); delete(timerObject); end
end
