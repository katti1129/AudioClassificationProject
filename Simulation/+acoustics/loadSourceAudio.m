function [sourcePa, sourceTimeSec, info] = loadSourceAudio(config)
%LOADSOURCEAUDIO Read, resample, mono-convert, and calibrate the Source WAV.
%   [SOURCEPA,T,INFO] = LOADSOURCEAUDIO(CONFIG) reads CONFIG.audio.inputFile,
%   averages channels, uses polyphase antialiasing resampling when needed,
%   trims/zero-pads (or loops) to simulation duration, and scales the active
%   waveform RMS to CONFIG.audio.referenceSPLdB at the configured reference
%   distance. SOURCEPA is physical pressure [Pa], T is [s].
%
%   A WAV has no inherent absolute SPL. The configured SPL/distance pair is
%   therefore an explicit calibration assumption that is recorded in INFO.

arguments
    config (1,1) struct
end

fileInfo=audioinfo(config.audio.inputFile);
fileSystemInfo=dir(config.audio.inputFile);
[inputSignal,inputFs]=audioread(config.audio.inputFile);
if size(inputSignal,2)>1
    switch lower(string(config.audio.monoMethod))
        case "mean"
            inputSignal=mean(inputSignal,2);
        otherwise
            error('acoustics:MonoMethod','Unsupported monoMethod: %s',config.audio.monoMethod);
    end
end

processingFs=config.audio.processingSampleRateHz;
if inputFs~=processingFs
    [p,q]=rat(processingFs/inputFs,1e-12);
    inputSignal=resample(inputSignal,p,q);
end
inputSignal=inputSignal(:);
activeRms=sqrt(mean(inputSignal.^2));
if ~(isfinite(activeRms)&&activeRms>0)
    error('acoustics:SilentInput','Input WAV is silent or contains invalid samples.');
end

nSamples=round(config.simulation.durationSec*processingFs);
if numel(inputSignal)<nSamples
    if config.audio.loopInput
        repeats=ceil(nSamples/numel(inputSignal));
        inputSignal=repmat(inputSignal,repeats,1);
    else
        inputSignal(end+1:nSamples,1)=0;
    end
end
inputSignal=inputSignal(1:nSamples);
usedDigitalRms=sqrt(mean(inputSignal.^2));

targetRmsPa=config.physics.referencePressurePa ...
    *10^(config.audio.referenceSPLdB/20);
sourcePa=inputSignal/activeRms*targetRmsPa;
usedReferenceRmsPa=sqrt(mean(sourcePa.^2));
usedReferenceSPLdB=20*log10(max(usedReferenceRmsPa,realmin) ...
    /config.physics.referencePressurePa);
sourceTimeSec=(0:nSamples-1).'/processingFs;

info.inputFile=char(config.audio.inputFile);
info.inputSampleRateHz=inputFs;
info.inputChannels=fileInfo.NumChannels;
info.inputDurationSec=fileInfo.Duration;
info.inputFileBytes=fileSystemInfo.bytes;
info.inputFileModified=string(fileSystemInfo.date);
info.processingSampleRateHz=processingFs;
info.outputSampleRateHz=config.audio.sampleRateHz;
info.referenceDistanceM=config.audio.referenceDistanceM;
info.referenceSPLdB=config.audio.referenceSPLdB;
info.referenceRMSPressurePa=targetRmsPa;
info.calibrationDigitalRMS=activeRms;
info.usedSegmentDigitalRMS=usedDigitalRms;
info.usedSegmentReferenceRMSPressurePa=usedReferenceRmsPa;
info.usedSegmentReferenceSPLdB=usedReferenceSPLdB;
info.looped=config.audio.loopInput && fileInfo.Duration<config.simulation.durationSec;
end
