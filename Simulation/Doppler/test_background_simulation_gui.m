function [checks,reportDir] = test_background_simulation_gui()
%TEST_BACKGROUND_SIMULATION_GUI UI wiring, errors, export and physics identity.
% Input: none. Outputs: checks table and unique report folder containing CSV,
% GUI screenshots, settings MAT and a real ambulance/background output folder.
% Tests programmatic callbacks, NOT human hearing or native file-dialog clicks.
config=background_simulation_config();
root=fullfile(fileparts(fileparts(mfilename('fullpath'))),'data','output','doppler_background_gui_tests');
if ~isfolder(root), mkdir(root); end
[~,id]=fileparts(tempname(root)); reportDir=fullfile(root,['GUI_' id]); mkdir(reportDir);
config.outputRoot=fullfile(reportDir,'audio'); config.figureVisible='off';
rows=cell(0,4);
a=background_simulation_gui(config,'off'); cleanup=onCleanup(@()delete(a.figure));
c=a.getConfig(); expected=config; expected.figureVisible='off';
record('default_config_roundtrip',double(~isequaln(c,expected)),0);
record('source_kmh_to_mps',abs(c.source.velocityMps(1)-60/3.6),1e-12);
record('receiver_mps',abs(c.receiver.velocityMps(1)-1.4),1e-12);
record('fade_ms_to_sec',abs(c.background.fadeSec-.02),0);
record('default_fixed_rms_enabled',double(~strcmp(a.controls.backgroundSpl.Enable,'on')),0);
record('default_snr_disabled',double(~strcmp(a.controls.snr.Enable,'off')),0);
a.controls.sourceHeading.Value=90; a.controls.receiverHeading.Value=-90;
c=a.getConfig(); record('source_heading_y',norm(c.source.velocityMps-[0,60/3.6,0]),1e-12);
record('receiver_heading_minus_y',norm(c.receiver.velocityMps-[0,-1.4,0]),1e-12);
for sourceStop=[false,true]
    for receiverStop=[false,true]
        a.controls.sourceStationary.Value=sourceStop; a.controls.receiverStationary.Value=receiverStop;
        c=a.getConfig();
        record(sprintf('source_stationary_%d_receiver_%d',sourceStop,receiverStop), ...
            abs(norm(c.source.velocityMps)-(~sourceStop)*60/3.6)+abs(norm(c.receiver.velocityMps)-(~receiverStop)*1.4),1e-12);
    end
end
a.setConfig(config);
settingsFile=fullfile(reportDir,'gui_settings.mat'); a.saveConfig(settingsFile);
a.controls.sourceSpeed.Value=30; a.loadConfig(settingsFile);
record('settings_mat_roundtrip',double(~isequaln(a.getConfig(),expected)),0);
bad=config; bad.source.velocityMps(3)=1;
reject('reject_vertical_velocity',@()a.setConfig(bad),'backgroundGUI:Vertical');
record('invalid_load_preserves_config',double(~isequaln(a.getConfig(),expected)),0);
bad=config; bad.background.mode='invalid';
reject('reject_unknown_level_mode',@()a.setConfig(bad),'backgroundGUI:Config');
a.controls.fs.Value=16000.5;
reject('reject_fractional_fs',a.getConfig,'backgroundGUI:Fs'); a.setConfig(config);
% Real input check uses full renderer but must not create an audio directory.
dry=a.check();
record('dry_run_does_not_export',double(isfolder(config.outputRoot)),0);
record('dry_run_releases_lock',double(a.getState().busy),0);
record('real_cpa_time',abs(dry.backgroundInfo.GeometricCpaTimeSec-60/(60/3.6-1.4)),1e-12);
record('real_background_spl_db',abs(dry.backgroundInfo.ActualBackgroundSplDb-80),1e-10);
% Capture actual MATLAB GUI, not an HTML mockup.
exportapp(a.figure,fullfile(reportDir,'gui_inputs.png'));
a.tabs.SelectedTab=a.controls.sourceX.Parent.Parent;
exportapp(a.figure,fullfile(reportDir,'gui_motion.png'));
a.tabs.SelectedTab=a.controls.backgroundMode.Parent.Parent;
exportapp(a.figure,fullfile(reportDir,'gui_background.png'));
bad=config; bad.source.velocityMps=[0,0,0]; bad.receiver.velocityMps=[0,0,0]; a.setConfig(bad);
reject('reject_undefined_cpa',a.check,'background:UndefinedCPA');
record('error_releases_lock',double(a.getState().busy),0);
bad=config; bad.background.durationSec=20; a.setConfig(bad);
reject('reject_output_overrun',a.check,'background:OutputRange');
bad=config; bad.background.sourceStartSec=3; a.setConfig(bad);
reject('reject_short_background',a.check,'background:SourceRange');
bad=config; bad.wavFullScalePa=.001; a.setConfig(bad);
reject('reject_clipping_before_export',a.check,'background:Clipping');
record('errors_do_not_export',double(isfolder(config.outputRoot)),0);
% Invoke the actual button error wrapper; it must display an error and recover.
a.controls.checkButton.ButtonPushedFcn([],[]);
record('button_displays_error',double(~strcmp(a.getState().lastError,'background:Clipping')),0);
record('button_error_reenables_generate',double(~strcmp(a.controls.generateButton.Enable,'on')),0);
% Headless runner cancellation at all three supported pre-save checkpoints.
for stage={'simulation','mixing','saving'}
    stopStage=stage{1};
    reject(['cancel_at_' stopStage],@()run_background_simulation(config,@(current,~)~strcmp(current,stopStage)),'background:Cancelled');
    record(['cancel_no_export_' stopStage],double(isfolder(config.outputRoot)),0);
end
% GUI cancellation + reentry is exercised via a one-shot event at drawnow.
a.setConfig(config); eventSeen=false; reentryBlocked=false;
t=timer('ExecutionMode','singleShot','StartDelay',.01,'TimerFcn',@interruptGui);
timerCleanup=onCleanup(@()deleteTimer(t));
start(t);
reject('gui_cancel',a.generate,'background:Cancelled');
record('gui_cancel_event_seen',double(~eventSeen),0);
record('gui_duplicate_run_rejected',double(~reentryBlocked),0);
record('gui_cancel_releases_lock',double(a.getState().busy),0);
record('gui_cancel_no_export',double(isfolder(config.outputRoot)),0);
% Generate through the actual WAV button callback and inspect its saved result.
a.setConfig(config); a.controls.generateButton.ButtonPushedFcn([],[]);
state=a.getState(); record('generate_button_no_error',double(~isempty(state.lastError)),0);
assert(isfolder(state.outputDir),'GUI did not produce an output folder.');
loaded=load(fullfile(state.outputDir,'result.mat'),'result'); r=loaded.result;
reference=mix_background_audio(simulate_moving_receiver_rms(r.config),r.config.background);
for component={'direct','reflected','siren','background','final'}
    name=component{1}; field=[name '_signal'];
    record(['physics_identity_' name],max(abs(r.(field)-reference.(field))),0);
    [y,fs]=audioread(fullfile(state.outputDir,[name '.wav']));
    record(['wav_fs_' name],abs(fs-r.fs),0);
    record(['wav_quantization_' name],max(abs(y-r.(field)/r.config.wavFullScalePa)),2^-23);
    record(['wav_not_clipped_' name],double(any(abs(y)>=1)),0);
end
for filename={'background_settings.csv','signal_summary.csv','calibration.csv','window_metrics.csv'}
    tab=readtable(fullfile(state.outputDir,filename{1}));
    record(['nonempty_' filename{1}],double(isempty(tab)),0);
end
record('waveform_png_readable',double(isempty(imread(fullfile(state.outputDir,'background_waveforms.png')))),0);
record('spectrogram_png_readable',double(isempty(imread(fullfile(state.outputDir,'background_spectrograms.png')))),0);
record('gui_waveform_image_set',double(isempty(a.controls.waveImage.ImageSource)),0);
record('generate_releases_lock',double(state.busy),0);
exportapp(a.figure,fullfile(reportDir,'gui_results.png'));
% Setting changes must not relabel/replace an already generated result.
a.controls.sourceSpeed.Value=30; a.controls.sourceSpeed.ValueChangedFcn([],[]);
record('settings_change_preserves_result_id',double(~strcmp(a.getState().outputDir,state.outputDir)),0);
% SNR mode and background-off paths use the same GUI wiring.
mode=config; mode.background.mode='snr'; a.setConfig(mode); snrResult=a.check();
record('snr_mode_db',abs(snrResult.backgroundInfo.ActualSnrDb-mode.background.snrDb),1e-10);
record('snr_field_enabled',double(~strcmp(a.controls.snr.Enable,'on')),0);
mode.background.enabled=false; mode.background.file='missing.wav'; a.setConfig(mode); disabled=a.check();
record('disabled_background_identity',max(abs(disabled.final_signal-disabled.siren_signal)),0);
record('disabled_background_zero',max(abs(disabled.background_signal)),0);
checks=cell2table(rows,'VariableNames',{'Test','Value','Tolerance','Status'});
writetable(checks,fullfile(reportDir,'gui_checks.csv'));
writetable(table(string(state.outputDir),'VariableNames',{'RealWavOutputDirectory'}),fullfile(reportDir,'output_directory.csv'));
fprintf('GUI tests: %d PASS, %d FAIL\nReport: %s\n',sum(strcmp(checks.Status,'PASS')),sum(strcmp(checks.Status,'FAIL')),reportDir);
assert(all(strcmp(checks.Status,'PASS')),'GUI regression failures: see gui_checks.csv.');

    function record(name,value,tolerance)
        % Append a numeric criterion and flush CSV so interrupted runs remain auditable.
        status='FAIL'; if isfinite(value) && value<=tolerance, status='PASS'; end
        rows(end+1,:)={name,value,tolerance,status};
        writetable(cell2table(rows,'VariableNames',{'Test','Value','Tolerance','Status'}),fullfile(reportDir,'gui_checks.csv'));
    end
    function reject(name,callback,identifier)
        % Expect a specific identifier (a different exception must not count as PASS).
        matched=false;
        try
            callback();
        catch exception
            matched=strcmp(exception.identifier,identifier);
        end
        record(name,double(~matched),0);
    end
    function interruptGui(~,~)
        % Timer emulates a queued user cancel while validating the busy lock.
        if ~a.getState().busy, return; end
        eventSeen=true;
        try
            a.generate();
        catch exception
            reentryBlocked=strcmp(exception.identifier,'backgroundGUI:Busy');
        end
        a.cancel();
    end
end

function deleteTimer(t)
% Stop/delete only this test's timer, including on exceptions.
if isvalid(t), stop(t); delete(t); end
end
