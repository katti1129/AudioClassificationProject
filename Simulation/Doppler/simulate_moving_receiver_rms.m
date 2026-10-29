function result = simulate_moving_receiver_rms(config, inputSignal, inputFs)
%SIMULATE_MOVING_RECEIVER_RMS Constant-velocity point source/receiver renderer.
% Inputs: config from moving_receiver_rms_config; optional samples and fs [Hz]
% (tests). Without samples, read config.inputFile. Output: signal components
% [Pa], times [s], paths [m], RMS calibration and settings. No files written.
% Reuses acoustics.solveDirectPath/computeTrajectory, with acceleration=0.
% Inherits Doppler folder models: linear interpolation, d_ref/r pressure
% spreading, and one infinite planar-ground image source (z -> -z).
% tau solves t=tau+|R(t)-S(tau)|/c; do NOT apply another pitch shift.
% This is a kinematic delayed-waveform model, not an exact moving-monopole
% radiation solution. No convective amplitude correction/air absorption.
root = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
cleanup = onCleanup(@() path(oldPath));
addpath(root);
validateattributes(config.fs, {'numeric'}, {'scalar','integer','positive','finite'});
validateattributes(config.c, {'numeric'}, {'scalar','positive','finite'});
validateattributes(config.sourceSplDb, {'numeric'}, {'scalar','real','finite'});
validateattributes(config.referenceDistanceM, {'numeric'}, {'scalar','positive','finite'});
validateattributes(config.minimumDistanceM, {'numeric'}, {'scalar','positive','finite'});
validateattributes(config.wavFullScalePa, {'numeric'}, {'scalar','positive','finite'});
validateattributes(config.reflection.coefficient, {'numeric'}, ...
    {'scalar','real','finite','>=',-1,'<=',1});
source = entity(config.source, config.c);
receiver = entity(config.receiver, config.c);
if nargin < 2
    [inputSignal, inputFs] = audioread(config.inputFile);
elseif nargin < 3
    error('doppler:InputFs', 'Specify inputFs with inputSignal.');
end
validateattributes(inputFs, {'numeric'}, {'scalar','integer','positive','finite'});
validateattributes(inputSignal, {'numeric'}, {'2d','nonempty','real','finite'});
inputSignal = mean(double(inputSignal), 2);
if inputFs ~= config.fs
    inputSignal = resample(inputSignal, config.fs, inputFs);
end
if numel(inputSignal) < 2
    error('doppler:ShortInput', 'At least two mono input samples are required.');
end
inputRms = sqrt(mean(inputSignal.^2));
if inputRms <= 0
    error('doppler:SilentInput', 'Cannot RMS-calibrate a silent input.');
end
referenceRmsPa = 2e-5 * 10^(config.sourceSplDb/20);
sourceSignalPa = inputSignal / inputRms * referenceRmsPa;
inputTime = (0:numel(inputSignal)-1)' / config.fs;
duration = numel(inputSignal) / config.fs;
imageSource = source;
imageSource.initialPositionM(3) = -source.initialPositionM(3);
% Vertical velocities are zero; both entities stay above the ground.
% Upper bound on arrival of final emission: receiver can retreat at |v_r|.
endReceiver = receiver.initialPositionM + duration*receiver.initialVelocityMps;
endSource = source.initialPositionM + duration*source.initialVelocityMps;
endImage = imageSource.initialPositionM + duration*imageSource.initialVelocityMps;
endDistance = norm(endReceiver-endSource);
if config.reflection.enabled
    endDistance = max(endDistance, norm(endReceiver-endImage));
end
endTime = duration + endDistance/(config.c-norm(receiver.initialVelocityMps));
t = (0:ceil(endTime*config.fs))' / config.fs;
solver.maxIterations = 50;
solver.timeToleranceSec = 1e-11;
directPath = acoustics.solveDirectPath(source, receiver, t, config.c, solver);
direct = renderPath(directPath, inputTime, sourceSignalPa, config);
reflected = zeros(size(t));
reflectedPath = [];
if config.reflection.enabled
    reflectedPath = acoustics.solveDirectPath(imageSource, receiver, t, config.c, solver);
    reflected = config.reflection.coefficient * ...
        renderPath(reflectedPath, inputTime, sourceSignalPa, config);
    fraction = -reflectedPath.sourcePositionM(:,3) ./ ...
        (reflectedPath.receiverPositionM(:,3)-reflectedPath.sourcePositionM(:,3));
    reflectedPath.reflectionPointM = reflectedPath.sourcePositionM + fraction .* ...
        (reflectedPath.receiverPositionM-reflectedPath.sourcePositionM);
end
result.config = config;
result.fs = config.fs;
result.timeSec = t;
result.inputTimeSec = inputTime;
result.inputDurationSec = duration;
result.input_signal = inputSignal;
result.source_signal_pa = sourceSignalPa;
result.referenceRmsPa = referenceRmsPa;
result.inputOriginalFs = inputFs;
result.sourceCalibrationGainPa = referenceRmsPa/inputRms;
result.direct_signal = direct;
result.reflected_signal = reflected;
result.final_signal = direct+reflected;
result.directPath = directPath;
result.reflectedPath = reflectedPath;
% Rectangular 125 ms RMS; this is NOT an exponential sound-level-meter Fast.
result.shortTimeRmsPa = sqrt(movmean(result.final_signal.^2, round(0.125*config.fs)));
% Exact silence is -Inf dB, not an arbitrary finite acoustic floor.
result.shortTimeSplDb = 20*log10(result.shortTimeRmsPa/2e-5);
end

function value = entity(settings, soundSpeed)
% Convert position [m]/constant velocity [m/s] to existing trajectory schema.
validateattributes(settings.positionM, {'numeric'}, {'vector','numel',3,'real','finite'});
validateattributes(settings.velocityMps, {'numeric'}, {'vector','numel',3,'real','finite'});
value.initialPositionM = reshape(double(settings.positionM),1,3);
value.initialVelocityMps = reshape(double(settings.velocityMps),1,3);
value.accelerationMps2 = [0,0,0]; % Required by reused API, not user-configurable.
if norm(value.initialVelocityMps) >= soundSpeed
    error('doppler:Supersonic', 'Only subsonic constant velocities are supported.');
end
if value.initialPositionM(3) <= 0 || value.initialVelocityMps(3) ~= 0
    error('doppler:GroundGeometry', 'Use positive heights and horizontal velocities.');
end
end

function signal = renderPath(propagation, inputTime, sourcePa, config)
% Render pressure [Pa] at retarded times with linear interpolation and 1/r.
if any(~propagation.valid)
    error('doppler:InvalidPath', 'Propagation-time solver did not produce valid paths.');
end
if any(propagation.distanceM < config.minimumDistanceM)
    error('doppler:NearField', 'Path is below minimumDistanceM; point-source model rejected.');
end
signal = interp1(inputTime, sourcePa, propagation.emissionTimeSec, 'linear', 0) ...
    .* (config.referenceDistanceM ./ propagation.distanceM);
end
