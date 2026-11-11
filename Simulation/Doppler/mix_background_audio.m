function result = mix_background_audio(clean, settings, samples, inputFs)
%MIX_BACKGROUND_AUDIO Add receiver-side background without altering propagation.
% Inputs: CLEAN from simulate_moving_receiver_rms, SETTINGS=config.background;
% optional SAMPLES + INPUTFS [Hz] allow deterministic tests without file I/O.
% Output: existing result fields plus siren_signal/background_signal [Pa],
% final_signal [Pa], background_interval_mask and backgroundInfo (table).
% Background is already-recorded receiver-side sound, not a new point source.
% It receives NO ambulance distance attenuation, reflection or Doppler.
% RMS is measured AFTER crop/resampling/fade on the whole inserted interval.
fs = clean.fs;
count = numel(clean.final_signal);
validateattributes(clean.final_signal,{'numeric'},{'column','real','finite','nonempty'});
validateattributes(settings.enabled,{'logical','numeric'},{'scalar','binary'});
result = clean;
result.siren_signal = clean.final_signal;
result.background_signal = zeros(count,1);
result.background_interval_mask = false(count,1);
result.backgroundConfig = settings;
% CPA is simultaneous geometric separation, not minimum retarded path length.
delta = reshape(clean.config.source.positionM,1,3)-reshape(clean.config.receiver.positionM,1,3);
velocity = reshape(clean.config.source.velocityMps,1,3)-reshape(clean.config.receiver.velocityMps,1,3);
cpaTime = NaN;
if dot(velocity,velocity)>0
    cpaTime = -dot(delta,velocity)/dot(velocity,velocity);
end
info = struct('Enabled',logical(settings.enabled),'File',string(settings.file), ...
    'TimeReference',string(settings.timeReference),'GeometricCpaTimeSec',cpaTime, ...
    'RequestedStartOffsetSec',settings.startOffsetSec,'RequestedSourceStartSec',settings.sourceStartSec, ...
    'RequestedDurationSec',settings.durationSec,'RequestedFadeSec',settings.fadeSec, ...
    'Mode',string(settings.mode),'RequestedSplDb',settings.splDb,'RequestedSnrDb',settings.snrDb, ...
    'InputFsHz',NaN,'StartSampleZeroBased',NaN,'SampleCount',0,'ActualStartSec',NaN, ...
    'ActualEndExclusiveSec',NaN,'ActualSourceStartSec',NaN,'ActualDurationSec',0, ...
    'ActualFadeSec',0,'CalibrationGainPa',0,'SirenIntervalRmsPa',NaN, ...
    'BackgroundIntervalRmsPa',0,'ActualBackgroundSplDb',-Inf,'ActualSnrDb',NaN);
if ~settings.enabled
    result.backgroundInfo = struct2table(info);
    return;
end
validateattributes(settings.sourceStartSec,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(settings.startOffsetSec,{'numeric'},{'scalar','real','finite'});
validateattributes(settings.durationSec,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(settings.fadeSec,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(settings.splDb,{'numeric'},{'scalar','real','finite'});
validateattributes(settings.snrDb,{'numeric'},{'scalar','real','finite'});
if ~ismember(string(settings.mode),["fixed_rms","snr"])
    error('background:Mode','mode must be fixed_rms or snr.');
end
switch string(settings.timeReference)
    case "start"
        requestedStart = settings.startOffsetSec;
    case "cpa"
        if ~isfinite(cpaTime) || cpaTime<0 || cpaTime>clean.timeSec(end)
            error('background:UndefinedCPA','No unique geometric CPA inside the observation interval; use timeReference=start.');
        end
        requestedStart = cpaTime+settings.startOffsetSec;
    otherwise
        error('background:TimeReference','timeReference must be start or cpa.');
end
if requestedStart<0 || requestedStart+settings.durationSec>count/fs+1e-12
    error('background:OutputRange','Requested background interval exceeds the received audio.');
end
first = round(requestedStart*fs)+1;
n = round(settings.durationSec*fs);
if n<2 || first+n-1>count
    error('background:OutputRange','Invalid sample-quantized background interval.');
end
if nargin<3
    [samples,inputFs] = audioread(settings.file);
elseif nargin<4
    error('background:InputFs','Provide inputFs with samples.');
end
validateattributes(inputFs,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(samples,{'numeric'},{'2d','real','finite','nonempty'});
samples = mean(double(samples),2);
if inputFs~=fs, samples = resample(samples,fs,inputFs); end
sourceFirst = round(settings.sourceStartSec*fs)+1;
if settings.sourceStartSec+settings.durationSec>numel(samples)/fs+1e-12 ...
        || sourceFirst+n-1>numel(samples)
    error('background:SourceRange','Background WAV is too short for the selected crop; no automatic looping.');
end
segment = samples(sourceFirst:sourceFirst+n-1);
fadeCount = round(settings.fadeSec*fs);
if 2*settings.fadeSec>settings.durationSec || 2*fadeCount>n || (settings.fadeSec>0 && fadeCount<2)
    error('background:Fade','Each fade must have at least two samples and occupy at most half the segment.');
end
if fadeCount>0
    ramp = (1-cos(pi*(0:fadeCount-1)'/(fadeCount-1)))/2;
    segment(1:fadeCount) = segment(1:fadeCount).*ramp;
    segment(end-fadeCount+1:end) = segment(end-fadeCount+1:end).*flipud(ramp);
end
segmentRms = sqrt(mean(segment.^2));
if segmentRms<=0
    error('background:SilentInput','Selected background segment has zero RMS after processing.');
end
indices = first:first+n-1;
sirenRms = sqrt(mean(result.siren_signal(indices).^2));
if strcmp(settings.mode,'fixed_rms')
    targetRms = 2e-5*10^(settings.splDb/20);
else
    if sirenRms<=0, error('background:SilentSiren','Cannot set SNR over a silent siren interval.'); end
    targetRms = sirenRms/10^(settings.snrDb/20);
end
gain = targetRms/segmentRms;
if ~isfinite(gain) || gain<=0
    error('background:Gain','Invalid background calibration gain.');
end
result.background_signal(indices) = segment*gain;
result.background_interval_mask(indices) = true;
result.final_signal = result.siren_signal+result.background_signal;
if any(~isfinite(result.final_signal)), error('background:Gain','Nonfinite mixed pressure.'); end
result.shortTimeRmsPa = sqrt(movmean(result.final_signal.^2,round(.125*fs)));
result.shortTimeSplDb = 20*log10(result.shortTimeRmsPa/2e-5);
actualRms = sqrt(mean(result.background_signal(indices).^2));
info.InputFsHz = inputFs;
info.StartSampleZeroBased = first-1;
info.SampleCount = n;
info.ActualStartSec = (first-1)/fs;
info.ActualEndExclusiveSec = (first-1+n)/fs;
info.ActualSourceStartSec = (sourceFirst-1)/fs;
info.ActualDurationSec = n/fs;
info.ActualFadeSec = fadeCount/fs;
info.CalibrationGainPa = gain;
info.SirenIntervalRmsPa = sirenRms;
info.BackgroundIntervalRmsPa = actualRms;
info.ActualBackgroundSplDb = 20*log10(actualRms/2e-5);
info.ActualSnrDb = 20*log10(sirenRms/actualRms);
result.backgroundInfo = struct2table(info);
end
