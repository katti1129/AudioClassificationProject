function results = runSimulation(config)
%RUNSIMULATION Execute the complete integrated acoustic simulation pipeline.
%   RESULTS = RUNSIMULATION(CONFIG) loads and calibrates a source WAV,
%   creates Source/Receiver trajectories, generates and filters obstacles,
%   solves direct/reflected/diffracted propagation paths, synthesizes and
%   combines calibrated pressure signals [Pa], and writes WAV, XLSX, MAT,
%   and PNG products according to CONFIG.
%
%   All geometry uses [m], time [s], velocity [m/s], acceleration [m/s^2],
%   frequency [Hz], and pressure [Pa]. No component-wise peak
%   normalization is performed.

arguments
    config (1,1) struct
end

config = acoustics.validateConfig(config);
simulationId = acoustics.createSimulationId(config);

targetFs = config.audio.sampleRateHz;
processingFs = targetFs * config.audio.internalOversampleFactor;
config.audio.processingSampleRateHz = processingFs;

[sourcePa, sourceTimeSec, audioInfo] = acoustics.loadSourceAudio(config);
if audioInfo.processingSampleRateHz ~= processingFs
    processingFs = audioInfo.processingSampleRateHz;
    config.audio.processingSampleRateHz = processingFs;
end

nProcessingSamples = round(config.simulation.durationSec * processingFs);
observationTimeSec = (0:nProcessingSamples-1).' / processingFs;

sourceTrajectory = acoustics.computeTrajectory(config.source, observationTimeSec);
receiverTrajectory = acoustics.computeTrajectory(config.receiver, observationTimeSec);
assertSubsonic(sourceTrajectory.velocityMps, receiverTrajectory.velocityMps, ...
    config.physics.soundSpeedMps);

directPath = acoustics.solveDirectPath(config.source, config.receiver, ...
    observationTimeSec, config.physics.soundSpeedMps, config.solver);

analysisTimeSec = geometryTimes(observationTimeSec, ...
    config.simulation.geometryTimeStepSec);
sourceAnalysis = acoustics.computeTrajectory(config.source, analysisTimeSec);
receiverAnalysis = acoustics.computeTrajectory(config.receiver, analysisTimeSec);
directEmissionTimeAnalysis = interp1(observationTimeSec, ...
    directPath.emissionTimeSec, analysisTimeSec, 'linear', 'extrap');
directEmissionAnalysis = acoustics.computeTrajectory(config.source, ...
    directEmissionTimeAnalysis);

if config.obstacle.enabled
    if ~isempty(config.obstacle.manualObstacles)
        obstacles = config.obstacle.manualObstacles;
    else
        obstacles = acoustics.generateObstacles(config.obstacle, ...
            sourceAnalysis.positionM, receiverAnalysis.positionM);
    end
else
    obstacles = struct([]);
end

if isempty(obstacles)
    fresnel = emptyFresnel(0, analysisTimeSec);
else
    if config.fresnel.enabled
        [~, fresnel] = acoustics.fresnelSelect(obstacles, ...
            directEmissionAnalysis.positionM, receiverAnalysis.positionM, ...
            config.fresnel.frequencyHz, config.physics.soundSpeedMps, ...
            config.fresnel.zoneNumber);
        fresnel = normalizeFresnel(fresnel, numel(obstacles), analysisTimeSec);
    else
        fresnel = emptyFresnel(numel(obstacles), analysisTimeSec);
        fresnel.candidateMask(:) = true;
        fresnel.intersectsMask(:) = true;
    end
end

obstruction = acoustics.computeObstruction(directEmissionAnalysis.positionM, ...
    receiverAnalysis.positionM, obstacles, analysisTimeSec);
obstruction = normalizeObstruction(obstruction, numel(obstacles), analysisTimeSec);

blockedAudio = logical(interp1(analysisTimeSec, double(obstruction.blocked), ...
    observationTimeSec, 'previous', 0));
visibilityAudio = ~blockedAudio;

directPa = acoustics.synthesizeDirect(sourcePa, sourceTimeSec, directPath, ...
    config.audio.referenceDistanceM, config.physics.minimumDistanceM, ...
    visibilityAudio);

if config.reflection.enabled && ~isempty(config.reflection.planes)
    [reflectionPaths, reflectedPa] = acoustics.synthesizeReflections( ...
        sourcePa, sourceTimeSec, config.source, config.receiver, ...
        observationTimeSec, config.reflection.planes, ...
        config.physics.soundSpeedMps, config.solver, ...
        config.audio.referenceDistanceM, config.physics.minimumDistanceM, ...
        obstacles, config.simulation.geometryTimeStepSec);
else
    reflectionPaths = struct([]);
    reflectedPa = zeros(size(observationTimeSec));
end


if config.reflection.enabled && config.reflection.obstacleFacesEnabled ...
        && ~isempty(obstacles)
    [obstacleReflectionPaths,obstacleReflectedPa] = ...
        acoustics.synthesizeObstacleReflections(sourcePa,sourceTimeSec, ...
        config.source,config.receiver,observationTimeSec,obstacles, ...
        config.physics.soundSpeedMps,config.solver, ...
        config.audio.referenceDistanceM,config.physics.minimumDistanceM, ...
        config.simulation.geometryTimeStepSec);
    reflectedPa=reflectedPa+obstacleReflectedPa;
else
    obstacleReflectionPaths=struct([]);
end

[diffractedPa, diffraction] = acoustics.synthesizeDiffraction( ...
    sourcePa, sourceTimeSec, config.source, config.receiver, ...
    observationTimeSec, obstacles, fresnel.candidateMask, config);

finalPa = directPa + reflectedPa + diffractedPa;

[signals, resultTimeSec, resultAudio, resultDirectPath, ...
    resultReflectionPaths, resultSourceTrajectory, resultReceiverTrajectory] = ...
    finalizeSampleRate(sourcePa, sourceTimeSec, directPa, reflectedPa, ...
    diffractedPa, finalPa, observationTimeSec, directPath, reflectionPaths, ...
    config.source, config.receiver, targetFs, processingFs, ...
    config.simulation.durationSec);

results.simulationId = simulationId;
results.sampleRateHz = targetFs;
results.processingSampleRateHz = processingFs;
results.timeSec = resultTimeSec;
results.audio = audioInfo;
results.audio.inputPa = resultAudio;
results.audio.sourceTimeSec = resultTimeSec;
results.trajectories.source = resultSourceTrajectory;
results.trajectories.receiver = resultReceiverTrajectory;
results.obstacles = obstacles;
results.fresnel = fresnel;
results.obstruction = obstruction;
results.paths.direct = resultDirectPath;
results.paths.reflections = resultReflectionPaths;
results.paths.obstacleReflections = obstacleReflectionPaths;
results.diffraction = diffraction;
results.signals = signals;
results.config = config;

results = acoustics.writeOutputs(results, config);
results = acoustics.writeMetadataExcel(results, config);
results = acoustics.createFigures(results, config);
end

function assertSubsonic(sourceVelocityMps, receiverVelocityMps, soundSpeedMps)
sourceSpeed = sqrt(sum(sourceVelocityMps.^2, 2));
receiverSpeed = sqrt(sum(receiverVelocityMps.^2, 2));
if any(sourceSpeed >= soundSpeedMps) || any(receiverSpeed >= soundSpeedMps)
    error('acoustics:SupersonicTrajectory', ...
        'This retarded-time solver supports only Source and Receiver speeds below c.');
end
end

function times = geometryTimes(observationTimeSec, stepSec)
times = (observationTimeSec(1):stepSec:observationTimeSec(end)).';
if isempty(times) || times(end) < observationTimeSec(end)
    times(end+1,1) = observationTimeSec(end);
end
if isscalar(times)
    times(end+1,1) = observationTimeSec(end) + eps;
end
end

function fresnel = emptyFresnel(nObstacles, analysisTimeSec)
fresnel.model = "conservative_AABB_bounding_sphere_first_Fresnel";
fresnel.analysisTimeSec = analysisTimeSec;
fresnel.candidateMask = false(nObstacles,1);
fresnel.intersectsMask = false(nObstacles,1);
fresnel.betweenEndpointsMask = false(nObstacles,1);
fresnel.minimumClearanceM = nan(nObstacles,1);
end

function fresnel = normalizeFresnel(fresnel, nObstacles, analysisTimeSec)
fresnel.analysisTimeSec = analysisTimeSec;
if ~isfield(fresnel,'candidateMask')
    if isfield(fresnel,'selectedMask')
        fresnel.candidateMask = fresnel.selectedMask(:);
    elseif isfield(fresnel,'isCandidate')
        fresnel.candidateMask = fresnel.isCandidate(:);
    else
        error('acoustics:MissingFresnelMask', ...
            'fresnelSelect did not return a per-obstacle candidate mask.');
    end
end
fresnel.candidateMask = logical(fresnel.candidateMask(:));
if numel(fresnel.candidateMask) ~= nObstacles
    error('acoustics:FresnelMaskSize', 'Fresnel mask size does not match obstacles.');
end
if ~isfield(fresnel,'intersectsMask'), fresnel.intersectsMask=fresnel.candidateMask; end
if ~isfield(fresnel,'betweenEndpointsMask')
    fresnel.betweenEndpointsMask=fresnel.candidateMask;
end
end

function obstruction = normalizeObstruction(obstruction, nObstacles, analysisTimeSec)
obstruction.timeSec = analysisTimeSec;
if ~isfield(obstruction,'blocked')
    if isfield(obstruction,'isBlocked')
        obstruction.blocked = obstruction.isBlocked(:);
    else
        obstruction.blocked = false(numel(analysisTimeSec),1);
    end
end
obstruction.blocked = logical(obstruction.blocked(:));
if numel(obstruction.blocked) ~= numel(analysisTimeSec)
    error('acoustics:ObstructionTimeSize', ...
        'Obstruction mask must contain one value per analysis time.');
end
if ~isfield(obstruction,'blockedByObstacle')
    if isfield(obstruction,'everBlockedByObstacle')
        obstruction.blockedByObstacle = obstruction.everBlockedByObstacle(:);
    elseif isfield(obstruction,'intersectionMatrix')
        obstruction.blockedByObstacle = any(obstruction.intersectionMatrix,1).';
    else
        obstruction.blockedByObstacle = false(nObstacles,1);
    end
end
end

function [signals, timeSec, inputPa, directPath, reflectionPaths, ...
    sourceTrajectory, receiverTrajectory] = finalizeSampleRate( ...
    sourcePaProcessing, sourceTimeProcessing, directPa, reflectedPa, ...
    diffractedPa, finalPa, processingTimeSec, directPathProcessing, ...
    reflectionPathsProcessing, sourceConfig, receiverConfig, targetFs, ...
    processingFs, durationSec)

nTarget = round(durationSec * targetFs);
timeSec = (0:nTarget-1).' / targetFs;

if processingFs == targetFs
    directOut = fitLength(directPa,nTarget);
    reflectedOut = fitLength(reflectedPa,nTarget);
    diffractedOut = fitLength(diffractedPa,nTarget);
    finalOut = directOut + reflectedOut + diffractedOut;
    inputPa = fitLength(sourcePaProcessing,nTarget);
else
    [p,q] = rat(targetFs/processingFs,1e-12);
    directOut = fitLength(resample(directPa,p,q),nTarget);
    reflectedOut = fitLength(resample(reflectedPa,p,q),nTarget);
    diffractedOut = fitLength(resample(diffractedPa,p,q),nTarget);
    finalOut = directOut + reflectedOut + diffractedOut;
    inputPa = fitLength(resample(sourcePaProcessing,p,q),nTarget);
end

signals.directPa = directOut;
signals.reflectedPa = reflectedOut;
signals.diffractedPa = diffractedOut;
signals.finalPa = finalOut;

% FINALPA is accepted so this helper can verify that synthesis supplied a
% complete processing-rate sum before the linear rate conversion.
if numel(finalPa)~=numel(directPa) ...
        || max(abs(finalPa-(directPa+reflectedPa+diffractedPa)))>1e-10 ...
           *max(1,max(abs(finalPa)))
    error('acoustics:ComponentSumMismatch', ...
        'Processing-rate final signal does not equal its three components.');
end

directPath = interpolatePath(directPathProcessing, processingTimeSec, timeSec);
reflectionPaths = reflectionPathsProcessing;
for k=1:numel(reflectionPaths)
    reflectionPaths(k)=interpolatePath(reflectionPathsProcessing(k),processingTimeSec,timeSec);
end
sourceTrajectory = acoustics.computeTrajectory(sourceConfig,timeSec);
receiverTrajectory = acoustics.computeTrajectory(receiverConfig,timeSec);

% SOURCE_TIME_PROCESSING is accepted to document the resampling origin and
% to guard against mismatched loader output during development.
if numel(sourceTimeProcessing) ~= numel(sourcePaProcessing)
    error('acoustics:SourceTimeSize','Source time and pressure lengths differ.');
end
end

function output = interpolatePath(input, oldTime, newTime)
output = input;
fields=fieldnames(input);
for k=1:numel(fields)
    value=input.(fields{k});
    if isnumeric(value) || islogical(value)
        if size(value,1)==numel(oldTime)
            method='linear';
            if islogical(value), method='previous'; end
            output.(fields{k})=interp1(oldTime,double(value),newTime,method,'extrap');
            if islogical(value), output.(fields{k})=logical(output.(fields{k})); end
        end
    end
end
end

function output = fitLength(input,n)
input=input(:);
if numel(input)>=n
    output=input(1:n);
else
    output=[input;zeros(n-numel(input),1)];
end
end
