function [checks,outputDir] = test_background_simulation()
%TEST_BACKGROUND_SIMULATION Test mix timing/levels, errors and actual recordings.
% Input: none. Output: checks and the fixed-RMS real-WAV output directory.
% Uses deterministic synthetic controls plus ambulance + engine/rain WAVs.
% Results are numerical/I/O checks, not listening tests or AI evaluation.
config = background_simulation_config();
fs = config.fs; t = (0:6*fs-1)'/fs;
clean = struct('fs',fs,'timeSec',t,'config',config, ...
    'final_signal',sin(2*pi*400*t),'direct_signal',sin(2*pi*400*t), ...
    'reflected_signal',zeros(size(t)));
clean.config.source.positionM = [-20,0,1.5];
clean.config.source.velocityMps = [10,0,0];
clean.config.receiver.positionM = [0,10,1.2];
clean.config.receiver.velocityMps = [0,0,0];
bt = (0:4*fs-1)'/fs;
sound = .4*sin(2*pi*220*bt);
b = config.background; b.startOffsetSec = -1; b.durationSec = 2;
b.splDb = 80; b.fadeSec = .02;
rows = cell(0,4);
r = mix_background_audio(clean,b,sound,fs);
info = r.backgroundInfo;
record('cpa_time_sec',abs(info.GeometricCpaTimeSec-2),1e-12);
record('cpa_relative_start_sec',abs(info.ActualStartSec-1),0);
record('cpa_relative_end_sec',abs(info.ActualEndExclusiveSec-3),0);
record('interval_sample_count',abs(nnz(r.background_interval_mask)-2*fs),0);
record('fixed_rms_spl_db',abs(info.ActualBackgroundSplDb-80),1e-10);
record('siren_unchanged',max(abs(r.siren_signal-clean.final_signal)),0);
record('direct_unchanged',max(abs(r.direct_signal-clean.direct_signal)),0);
record('reflection_unchanged',max(abs(r.reflected_signal-clean.reflected_signal)),0);
record('outside_interval_exact_zero',max(abs(r.background_signal(~r.background_interval_mask))),0);
record('sum_error_pa',max(abs(r.final_signal-r.siren_signal-r.background_signal)),1e-12);
indices = find(r.background_interval_mask);
record('fade_endpoints_zero',max(abs(r.background_signal(indices([1,end])))),0);
repeat = mix_background_audio(clean,b,sound,fs);
record('deterministic_repeat',double(~isequaln(r,repeat)),0);
louder = clean; louder.final_signal = 2*clean.final_signal;
fixedLouder = mix_background_audio(louder,b,sound,fs);
record('fixed_background_independent_of_siren',max(abs(fixedLouder.background_signal-r.background_signal)),0);
record('fixed_snr_change_db',abs(fixedLouder.backgroundInfo.ActualSnrDb-info.ActualSnrDb-20*log10(2)),1e-10);
for snrDb = [-10,0,10,20]
    bs = b; bs.mode = 'snr'; bs.snrDb = snrDb;
    rs = mix_background_audio(clean,bs,sound,fs);
    record("snr_target_"+snrDb+"_db",abs(rs.backgroundInfo.ActualSnrDb-snrDb),1e-10);
end
bs = b; bs.mode = 'snr';
rs = mix_background_audio(clean,bs,sound,fs);
rs2 = mix_background_audio(louder,bs,sound,fs);
record('snr_mode_scales_background',max(abs(rs2.background_signal-2*rs.background_signal)),1e-12);
start = b; start.timeReference = 'start'; start.startOffsetSec = .25;
start.sourceStartSec = .5; start.durationSec = 1; start.fadeSec = 0;
rs = mix_background_audio(clean,start,(1:4*fs)',fs);
expected = (fs/2+1:fs/2+fs)';
expected = expected/sqrt(mean(expected.^2))*(2e-5*10^(start.splDb/20));
record('source_crop_before_scaling',max(abs(rs.background_signal(rs.background_interval_mask)-expected)),1e-12);
record('start_reference_sec',abs(rs.backgroundInfo.ActualStartSec-.25),0);
record('source_offset_sec',abs(rs.backgroundInfo.ActualSourceStartSec-.5),0);
fractional = start; fractional.startOffsetSec = .25003; fractional.sourceStartSec = .50003;
rf = mix_background_audio(clean,fractional,sound,fs);
record('insertion_rounding_half_sample',abs(rf.backgroundInfo.ActualStartSec-fractional.startOffsetSec),.5/fs);
record('source_rounding_half_sample',abs(rf.backgroundInfo.ActualSourceStartSec-fractional.sourceStartSec),.5/fs);
stereo = mix_background_audio(clean,b,[sound,2*sound],fs);
mono = mix_background_audio(clean,b,1.5*sound,fs);
record('stereo_average',max(abs(stereo.background_signal-mono.background_signal)),1e-12);
lowFs = 8000; low = sin(2*pi*220*(0:4*lowFs-1)'/lowFs);
converted = mix_background_audio(clean,b,low,lowFs);
record('resampled_rms_db',abs(converted.backgroundInfo.ActualBackgroundSplDb-80),1e-10);
record('resampled_length',abs(numel(converted.final_signal)-numel(t)),0);
disabled = b; disabled.enabled = false; disabled.file = 'nonexistent.wav';
rd = mix_background_audio(clean,disabled);
record('disabled_exact_identity',max(abs(rd.final_signal-clean.final_signal)),0);
record('disabled_empty_mask',nnz(rd.background_interval_mask),0);
bad = b; bad.startOffsetSec = -3;
reject('negative_start',@() mix_background_audio(clean,bad,sound,fs),'background:OutputRange');
bad = start; bad.startOffsetSec = 5.5;
reject('past_end',@() mix_background_audio(clean,bad,sound,fs),'background:OutputRange');
bad = start; bad.sourceStartSec = 3.5;
reject('short_source',@() mix_background_audio(clean,bad,sound,fs),'background:SourceRange');
bad = b; bad.fadeSec = 1.1;
reject('long_fade',@() mix_background_audio(clean,bad,sound,fs),'background:Fade');
bad = b; bad.mode = 'unknown';
reject('unknown_mode',@() mix_background_audio(clean,bad,sound,fs),'background:Mode');
bad = b; bad.timeReference = 'unknown';
reject('unknown_reference',@() mix_background_audio(clean,bad,sound,fs),'background:TimeReference');
reject('silent_background',@() mix_background_audio(clean,b,zeros(size(sound)),fs),'background:SilentInput');
silent = clean; silent.final_signal(:) = 0;
reject('silent_siren_snr',@() mix_background_audio(silent,bs,sound,fs),'background:SilentSiren');
stationary = clean; stationary.config.source.velocityMps(:) = 0;
reject('undefined_cpa',@() mix_background_audio(stationary,b,sound,fs),'background:UndefinedCPA');
outside = clean; outside.config.source.positionM = [20,0,1.5];
reject('cpa_before_recording',@() mix_background_audio(outside,b,sound,fs),'background:UndefinedCPA');
rr = mix_background_audio(stationary,start,sound,fs);
record('stationary_start_supported',abs(rr.backgroundInfo.ActualStartSec-.25),0);
% End-to-end: the original simulation and new wrapper must render identical siren.
config.figureVisible = 'off';
[realFixed,outputDir] = run_background_simulation(config);
plain = simulate_moving_receiver_rms(moving_receiver_rms_config());
record('real_siren_bit_identical_to_original',max(abs(realFixed.siren_signal-plain.final_signal)),0);
record('real_direct_bit_identical_to_original',max(abs(realFixed.direct_signal-plain.direct_signal)),0);
record('real_reflection_bit_identical_to_original',max(abs(realFixed.reflected_signal-plain.reflected_signal)),0);
record('real_fixed_rms_db',abs(realFixed.backgroundInfo.ActualBackgroundSplDb-config.background.splDb),1e-10);
record('real_sum_error_pa',max(abs(realFixed.final_signal-realFixed.siren_signal-realFixed.background_signal)),1e-12);
for name = ["direct","reflected","siren","background","final"]
    [saved,savedFs] = audioread(fullfile(outputDir,name+".wav"));
    expected = realFixed.(char(name+"_signal"))/config.wavFullScalePa;
    record("wav_"+name+"_fs",abs(savedFs-config.fs),0);
    record("wav_"+name+"_readback",max(abs(saved-expected)),2^-23);
    record("wav_"+name+"_clip_count",nnz(abs(saved)>=1),0);
end
stored = load(fullfile(outputDir,'result.mat'),'result');
record('mat_pa_roundtrip',max(abs(stored.result.final_signal-realFixed.final_signal)),0);
record('mat_mask_roundtrip',nnz(stored.result.background_interval_mask~=realFixed.background_interval_mask),0);
for name = ["background_waveforms","background_spectrograms"]
    picture = imread(fullfile(outputDir,name+".png"));
    record(name+"_readable",double(isempty(picture)),0);
end
settings = readtable(fullfile(outputDir,'background_settings.csv'));
record('metadata_interval_roundtrip',abs(settings.ActualStartSec-realFixed.backgroundInfo.ActualStartSec),1e-12);
windows = readtable(fullfile(outputDir,'window_metrics.csv'));
record('window_coverage_integral',abs(sum((windows.EndExclusiveSec-windows.StartSec).*windows.BackgroundCoverage)-4),1e-10);
config.makeFigures = false; config.background.mode = 'snr'; config.background.snrDb = 0;
[realSnr,snrDir] = run_background_simulation(config);
record('real_snr_target_db',abs(realSnr.backgroundInfo.ActualSnrDb),1e-10);
record('real_snr_keeps_siren',max(abs(realSnr.siren_signal-realFixed.siren_signal)),0);
% Another actual dataset: first registered ESC rain, no original files changed.
root = fileparts(fileparts(mfilename('fullpath')));
meta = readtable(fullfile(root,'data','background_audio','metadata','selected_audio_manifest.csv'),'TextType','string');
row = find(meta.dataset=="ESC-50" & meta.class=="rain",1);
config.background.file = fullfile(root,'data','background_audio',meta.relative_path(row));
config.background.mode = 'fixed_rms';
[rain,rainDir] = run_background_simulation(config);
record('real_esc_rain_rms_db',abs(rain.backgroundInfo.ActualBackgroundSplDb-config.background.splDb),1e-10);
record('real_esc_rain_keeps_siren',max(abs(rain.siren_signal-realFixed.siren_signal)),0);
config.wavFullScalePa = 1e-9;
reject('output_clipping',@() run_background_simulation(config),'background:Clipping');
checks = cell2table(rows,'VariableNames',{'Check','Status','AbsoluteError','Tolerance'});
writetable(checks,fullfile(outputDir,'checks.csv'));
examples = table(["fixed_rms_engine";"snr_0_engine";"fixed_rms_rain"], ...
    string({outputDir;snrDir;rainDir}),'VariableNames',{'Case','OutputDirectory'});
writetable(examples,fullfile(outputDir,'example_outputs.csv'));
fprintf('Background tests: %d PASS; %d FAIL. %s\n',nnz(checks.Status=="PASS"), ...
    nnz(checks.Status=="FAIL"),fullfile(outputDir,'checks.csv'));
assert(all(checks.Status=="PASS"),'background:TestsFailed','Inspect checks.csv.');

    function record(name,value,tolerance)
        % Append finite absolute-error <= tolerance result.
        status = "FAIL";
        if isfinite(value) && value<=tolerance, status = "PASS"; end
        rows(end+1,:) = {string(name),status,value,tolerance};
    end
    function reject(name,action,identifier)
        % Record success only for the specifically expected validation error.
        caught = false;
        try
            action();
        catch exception
            caught = strcmp(exception.identifier,identifier);
        end
        record("reject_"+name,double(~caught),0);
    end
end
