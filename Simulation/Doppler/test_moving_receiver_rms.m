function [checks, outputDir] = test_moving_receiver_rms()
%TEST_MOVING_RECEIVER_RMS Verify analytic controls and run the real siren WAV.
% Input: none. Outputs: checks table and real-WAV output directory.
% Saves checks.csv alongside WAV/MAT/figures. Tests numerical model behavior,
% not agreement with measured outdoor sound or perceptual audio quality.
base = moving_receiver_rms_config();
base.reflection.enabled = false;
base.source.positionM = [0,0,1.5];
base.receiver.positionM = [100,0,1.5];
fs = base.fs;
toneTime = (0:fs-1)'/fs;
tone = sin(2*pi*400*toneTime);
rows = cell(0,5);
% All trajectories remain collinear with n=[1,0,0] during the test.
velocities = [0,0; 60/3.6,0; 0,-1.4; 60/3.6,1.4; -60/3.6,1.4];
caseNames = ["static", "source_approach", "receiver_approach", ...
    "both_same_direction", "both_separating"];
for k = 1:size(velocities,1)
    c = base;
    vs = velocities(k,1); vr = velocities(k,2);
    c.source.velocityMps = [vs,0,0];
    c.receiver.velocityMps = [vr,0,0];
    r = simulate_moving_receiver_rms(c,tone,fs);
    expectedTau = ((c.c-vr)*r.timeSec-100)/(c.c-vs);
    expectedFactor = (c.c-vr)/(c.c-vs);
    record(caseNames(k)+"_emission_time_s",max(abs(r.directPath.emissionTimeSec-expectedTau)),1e-10);
    record(caseNames(k)+"_doppler_factor",max(abs(r.directPath.dopplerFactor-expectedFactor)),1e-12);
    record(caseNames(k)+"_delay_residual_s",max(abs(r.directPath.residualSec)),1e-10);
    record(caseNames(k)+"_rms_calibration_relative", ...
        abs(sqrt(mean(r.source_signal_pa.^2))/r.referenceRmsPa-1),1e-12);
    valid = expectedTau>.05 & expectedTau<.95;
    distance = 100 + vr*r.timeSec-vs*expectedTau;
    expected = sqrt(2)*r.referenceRmsPa*sin(2*pi*400*expectedTau) ...
        .*c.referenceDistanceM./distance;
    record(caseNames(k)+"_analytic_waveform_nrmse", ...
        norm(r.direct_signal(valid)-expected(valid))/norm(expected(valid)),.004);
    record(caseNames(k)+"_tail_complete",double(r.directPath.emissionTimeSec(end)<toneTime(end)),0);
    record(caseNames(k)+"_reflection_off",max(abs(r.reflected_signal)),0);
end
% Static ground image: analytic reflected distance and fractional delay.
c = base;
c.source.velocityMps = [0,0,0]; c.receiver.velocityMps = [0,0,0];
c.receiver.positionM = [0,10,1.2];
c.reflection.enabled = true;
r = simulate_moving_receiver_rms(c,tone,fs);
imageDistance = hypot(10,2.7);
record("ground_image_distance_m",max(abs(r.reflectedPath.distanceM-imageDistance)),1e-12);
record("ground_reflection_point_z_m",max(abs(r.reflectedPath.reflectionPointM(:,3))),1e-12);
tau = r.timeSec-imageDistance/c.c;
valid = tau>.05 & tau<.95;
expected = c.reflection.coefficient*sqrt(2)*r.referenceRmsPa/imageDistance*sin(2*pi*400*tau);
record("ground_analytic_waveform_nrmse", ...
    norm(r.reflected_signal(valid)-expected(valid))/norm(expected(valid)),.004);
record("component_sum_pa",max(abs(r.final_signal-r.direct_signal-r.reflected_signal)),1e-12);
rScaled = simulate_moving_receiver_rms(c,0.17*tone,fs);
record("input_gain_invariance_relative",norm(rScaled.final_signal-r.final_signal)/norm(r.final_signal),1e-12);
c.reflection.coefficient = 0;
rZero = simulate_moving_receiver_rms(c,tone,fs);
record("zero_reflection_coefficient",max(abs(rZero.reflected_signal)),0);
% Stationary 1 m free field: calibrated source RMS must be preserved, even
% for noninteger delay within linear interpolation's stated error tolerance.
c = base; c.source.velocityMps = [0,0,0]; c.receiver.velocityMps = [0,0,0];
c.receiver.positionM = [1,0,1.5];
rNear = simulate_moving_receiver_rms(c,tone,fs);
c.receiver.positionM = [2,0,1.5];
rFar = simulate_moving_receiver_rms(c,tone,fs);
near = rNear.directPath.emissionTimeSec>.1 & rNear.directPath.emissionTimeSec<.9;
far = rFar.directPath.emissionTimeSec>.1 & rFar.directPath.emissionTimeSec<.9;
nearRms = sqrt(mean(rNear.direct_signal(near).^2));
farRms = sqrt(mean(rFar.direct_signal(far).^2));
record("one_metre_rms_relative",abs(nearRms/rNear.referenceRmsPa-1),.004);
record("distance_doubling_amplitude_ratio",abs(nearRms/farRms-2),.01);
rStereo = simulate_moving_receiver_rms(c,[tone,tone],fs);
record("stereo_to_mono",max(abs(rStereo.final_signal-rFar.final_signal)),1e-12);
lowTime = (0:7999)'/8000;
rResampled = simulate_moving_receiver_rms(c,sin(2*pi*400*lowTime),8000);
record("resample_output_fs",abs(rResampled.fs-16000),0);
record("resample_rms_relative",abs(sqrt(mean(rResampled.source_signal_pa.^2))/rResampled.referenceRmsPa-1),1e-12);
record("reject_silence",double(~throws(@() simulate_moving_receiver_rms(c,zeros(fs,1),fs),'doppler:SilentInput')),0);
bad = c; bad.source.velocityMps = [bad.c,0,0];
record("reject_sonic_velocity",double(~throws(@() simulate_moving_receiver_rms(bad,tone,fs),'doppler:Supersonic')),0);
bad = c; bad.receiver.positionM = bad.source.positionM;
record("reject_coincident_positions",double(~throws(@() simulate_moving_receiver_rms(bad,tone,fs),'doppler:NearField')),0);
bad = c; bad.receiver.velocityMps = [0,0,-1];
record("reject_vertical_motion",double(~throws(@() simulate_moving_receiver_rms(bad,tone,fs),'doppler:GroundGeometry')),0);
% Full actual siren run: 60 km/h source, 1.4 m/s receiver, ground reflection.
c = moving_receiver_rms_config(); c.figureVisible = 'off';
[realResult,outputDir] = moving_receiver_rms(c);
record("real_wav_rms_calibration_relative", ...
    abs(sqrt(mean(realResult.source_signal_pa.^2))/realResult.referenceRmsPa-1),1e-12);
record("real_wav_direct_residual_s",max(abs(realResult.directPath.residualSec)),1e-10);
record("real_wav_reflected_residual_s",max(abs(realResult.reflectedPath.residualSec)),1e-10);
record("real_wav_component_sum_pa", ...
    max(abs(realResult.final_signal-realResult.direct_signal-realResult.reflected_signal)),1e-12);
record("real_wav_tail_complete",double(min([realResult.directPath.emissionTimeSec(end), ...
    realResult.reflectedPath.emissionTimeSec(end)])<realResult.inputTimeSec(end)),0);
for name = ["direct","reflected","final"]
    [saved,savedFs] = audioread(fullfile(outputDir,name+".wav"));
    reference = realResult.(char(name+"_signal"))/c.wavFullScalePa;
    record("real_wav_"+name+"_sample_rate",abs(savedFs-c.fs),0);
    record("real_wav_"+name+"_readback_error",max(abs(saved-reference)),2^-23);
    record("real_wav_"+name+"_clipped_samples",nnz(abs(saved)>=1),0);
end
loaded = load(fullfile(outputDir,'result.mat'),'result');
record("mat_pa_roundtrip",max(abs(loaded.result.final_signal-realResult.final_signal)),0);
for name = ["geometry_doppler","waveforms_rms","spectrograms"]
    picture = imread(fullfile(outputDir,name+".png"));
    record(name+"_png_readable",double(isempty(picture)),0);
end
% Explicitly verify clipping is rejected, not silently normalized.
bad = c; bad.wavFullScalePa = 1e-9; bad.makeFigures = false;
record("reject_wav_clipping",double(~throws(@() moving_receiver_rms(bad),'doppler:Clipping')),0);
checks = cell2table(rows,'VariableNames',{'Check','Status','Error','Tolerance','Criterion'});
writetable(checks,fullfile(outputDir,'checks.csv'));
fprintf('%d PASS; %d FAIL. Checks: %s\n',nnz(checks.Status=="PASS"), ...
    nnz(checks.Status=="FAIL"),fullfile(outputDir,'checks.csv'));
assert(all(checks.Status=="PASS"),'doppler:TestsFailed','Some tests failed; inspect checks.csv.');

    function record(name, measured, tolerance)
        % Append an absolute-error <= tolerance check to the audit table.
        status = "FAIL";
        if isfinite(measured) && measured<=tolerance, status = "PASS"; end
        rows(end+1,:) = {name,status,measured,tolerance,"absolute error <= tolerance"};
    end
end

function yes = throws(action, identifier)
% Return true only if the action raises the expected MATLAB error identifier.
yes = false;
try
    action();
catch exception
    yes = strcmp(exception.identifier,identifier);
end
end
