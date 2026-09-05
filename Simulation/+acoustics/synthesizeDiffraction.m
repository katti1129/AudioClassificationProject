function [diffractedPa, diffraction] = synthesizeDiffraction( ...
    sourcePa, sourceTimeSec, sourceConfig, receiverConfig, ...
    observationTimeSec, obstacles, candidateMask, config)
%SYNTHESIZEDIFFRACTION Synthesize broadband, time-varying knife-edge sound.
%   [Y, D] = SYNTHESIZEDIFFRACTION(SOURCEPA, SOURCETIMESEC, SOURCECONFIG,
%   RECEIVERCONFIG, OBSERVATIONTIMESEC, OBSTACLES, CANDIDATEMASK, CONFIG)
%   calculates a dominant path-equivalent diffracted component in Pa.
%
%   The Source emission time [s] is solved from
%       t = tau + Ldiff(tau,t) / c,
%   where Ldiff is the full broken-ray length [m].
%   At each geometry update, axis-aligned boxes intersecting the direct LOS
%   are considered. For finite box thickness, the shortest valid bypass
%   travels from an entry edge across one exposed face to an exit edge. The
%   documented fallback for serial blockers uses a vertical taut path over
%   their top constraints. It is a path-equivalent approximation rather
%   than a coherent multiple-edge solution.
%
%   For either geometry, total excess path delta [m] gives
%   v ~= 2*sqrt(delta/lambda).
%   ITU-R P.526's single knife-edge magnitude approximation is then applied
%   as a path-equivalent loss per FFT bin with weighted overlap-add. This is
%   an engineering scalar-acoustic approximation, not full UTD or a solved
%   coherent double-edge diffraction coefficient.
%
%   Inputs use SI units. SOURCEPA is calibrated pressure [Pa]. OBSTACLES is
%   a struct array of static 3D AABBs. CANDIDATEMASK is a logical vector
%   produced by the conservative Fresnel broad-phase selector.
%
%   Reference: ITU-R P.526-16, Sections 2.1 and 4.1.

arguments
    sourcePa (:,1) double
    sourceTimeSec (:,1) double
    sourceConfig (1,1) struct
    receiverConfig (1,1) struct
    observationTimeSec (:,1) double
    obstacles
    candidateMask
    config (1,1) struct
end

nSamples = numel(observationTimeSec);
diffractedPa = zeros(nSamples, 1);
nObstacles = numel(obstacles);

if isempty(candidateMask)
    candidateMask = true(nObstacles, 1);
else
    candidateMask = logical(candidateMask(:));
end
if numel(candidateMask) ~= nObstacles
    error('acoustics:CandidateSizeMismatch', ...
        'candidateMask must contain one value per obstacle.');
end

analysisTimeSec = geometryTimes(observationTimeSec, ...
    config.simulation.geometryTimeStepSec);
nFrames = numel(analysisTimeSec);

active = false(nFrames, 1);
obstacleIndex = nan(nFrames, 1);
pointM = nan(nFrames, 3);
secondPointM = nan(nFrames, 3);
sourceDistanceM = nan(nFrames, 1);
surfaceDistanceM = nan(nFrames, 1);
receiverDistanceM = nan(nFrames, 1);
pathLengthM = nan(nFrames, 1);
directDistanceM = nan(nFrames, 1);
excessPathM = nan(nFrames, 1);
emissionTimeSec = analysisTimeSec;
lossReferenceDb = nan(nFrames, 1);
converged = true(nFrames, 1);
residualSec = nan(nFrames, 1);
blockingObstacleCount = zeros(nFrames, 1);
unsupportedMultiplePath = false(nFrames, 1);
multiplePathApproximationUsed = false(nFrames,1);
usedObstacleMask = false(nFrames,nObstacles);
pathPointsM = cell(nFrames,1);

if config.diffraction.enabled && nObstacles > 0 && any(candidateMask)
    for frameIndex = 1:nFrames
        tReceive = analysisTimeSec(frameIndex);
        receiverState = acoustics.computeTrajectory(receiverConfig, tReceive);
        receiverPositionM = receiverState.positionM(1, :);

        sourceNow = acoustics.computeTrajectory(sourceConfig, tReceive);
        tau = tReceive - norm(receiverPositionM - sourceNow.positionM(1, :)) ...
            / config.physics.soundSpeedMps;
        frameGeometry = emptyGeometry();

        for iteration = 1:config.solver.maxIterations
            sourceState = acoustics.computeTrajectory(sourceConfig, tau);
            sourcePositionM = sourceState.positionM(1, :);
            frameGeometry = selectDominantEdge(sourcePositionM, ...
                receiverPositionM, obstacles, candidateMask, config);

            if ~frameGeometry.valid
                break;
            end

            tauNew = tReceive - frameGeometry.pathLengthM ...
                / config.physics.soundSpeedMps;
            if abs(tauNew - tau) <= config.solver.timeToleranceSec
                tau = tauNew;
                break;
            end
            tau = tauNew;
        end

        emissionTimeSec(frameIndex) = tau;
        blockingObstacleCount(frameIndex) = frameGeometry.blockingObstacleCount;
        unsupportedMultiplePath(frameIndex) = frameGeometry.unsupportedMultiplePath;
        if frameGeometry.valid
            residualSec(frameIndex)=tau+frameGeometry.pathLengthM ...
                /config.physics.soundSpeedMps-tReceive;
            converged(frameIndex)=abs(residualSec(frameIndex)) ...
                <=config.solver.timeToleranceSec;
        end
        if frameGeometry.valid && converged(frameIndex)
            active(frameIndex) = true;
            obstacleIndex(frameIndex) = frameGeometry.obstacleIndex;
            usedObstacleMask(frameIndex,frameGeometry.obstacleIndices)=true;
            pathPointsM{frameIndex}=frameGeometry.diffractionPointsM;
            multiplePathApproximationUsed(frameIndex)= ...
                frameGeometry.multiplePathApproximation;
            pointM(frameIndex, :) = frameGeometry.pointM;
            secondPointM(frameIndex, :) = frameGeometry.secondPointM;
            sourceDistanceM(frameIndex) = frameGeometry.sourceDistanceM;
            surfaceDistanceM(frameIndex) = frameGeometry.surfaceDistanceM;
            receiverDistanceM(frameIndex) = frameGeometry.receiverDistanceM;
            pathLengthM(frameIndex) = frameGeometry.pathLengthM;
            directDistanceM(frameIndex) = frameGeometry.directDistanceM;
            excessPathM(frameIndex) = frameGeometry.excessPathM;
            lossReferenceDb(frameIndex) = frameGeometry.lossReferenceDb;
        end
    end
end

if any(multiplePathApproximationUsed)
    message=sprintf(['%d geometry frames use the documented vertical ' ...
        'taut-path, path-equivalent knife-edge approximation for serial AABBs.'], ...
        nnz(multiplePathApproximationUsed));
    switch lower(string(config.diffraction.unsupportedMultiplePathAction))
        case "error"
            error('acoustics:MultipleDiffractionApproximation','%s',message);
        case "warning"
            warning('acoustics:MultipleDiffractionApproximation','%s',message);
    end
end

if any(~converged)
    warning('acoustics:DiffractionRetardedTimeNotConverged', ...
        ['%d diffraction geometry frames did not meet the retarded-time ' ...
         'tolerance and were excluded.'],nnz(~converged));
end

if any(unsupportedMultiplePath)
    message=sprintf(['%d geometry frames contain serial blockers for which ' ...
        'no unobstructed finite-box single-path diffraction ray exists.'], ...
        nnz(unsupportedMultiplePath));
    switch lower(string(config.diffraction.unsupportedMultiplePathAction))
        case "error"
            error('acoustics:UnsupportedMultipleDiffraction','%s',message);
        case "warning"
            warning('acoustics:UnsupportedMultipleDiffraction','%s',message);
    end
end

if any(active)
    activeAudio = logical(interp1(analysisTimeSec, double(active), ...
        observationTimeSec, 'previous', 0));
    tauAudio = interpFinite(analysisTimeSec, emissionTimeSec, observationTimeSec, ...
        observationTimeSec);
    directDistanceAudio = interpFinite(analysisTimeSec, directDistanceM, ...
        observationTimeSec, ...
        config.physics.minimumDistanceM);
    deltaAudio = interpFinite(analysisTimeSec, excessPathM, observationTimeSec, 0);

    warpedPa = interp1(sourceTimeSec, sourcePa, tauAudio, 'linear', 0);
    % ITU J(v) is an insertion loss relative to the unobstructed free-space
    % field at the same Source-Receiver separation. Use 1/directDistance
    % for that reference field; the longer bypass length remains in tau and
    % therefore in propagation delay/phase.
    spreading = config.audio.referenceDistanceM ./ max(directDistanceAudio, ...
        config.physics.minimumDistanceM);
    baseDiffractedPa = warpedPa .* spreading .* double(activeAudio);
    diffractedPa = applyFrequencyDependentLoss(baseDiffractedPa, deltaAudio, ...
        activeAudio, config.audio.processingSampleRateHz, config);
else
    activeAudio = false(nSamples, 1);
    tauAudio = observationTimeSec;
end

perObstacle = makePerObstacleTable(obstacles, obstacleIndex, usedObstacleMask, pointM, ...
    secondPointM, sourceDistanceM, surfaceDistanceM, receiverDistanceM, ...
    pathLengthM, lossReferenceDb, active);

diffraction.model = ...
    "finite_AABB_with_serial_vertical_fallback_path_equivalent_ITU_R_P526_magnitude";
diffraction.analysisTimeSec = analysisTimeSec;
diffraction.active = active;
diffraction.activeAudio = activeAudio;
diffraction.obstacleIndex = obstacleIndex;
diffraction.pointM = pointM;
diffraction.secondPointM = secondPointM;
diffraction.pathPointsM = pathPointsM;
diffraction.sourceDistanceM = sourceDistanceM;
diffraction.surfaceDistanceM = surfaceDistanceM;
diffraction.receiverDistanceM = receiverDistanceM;
diffraction.pathLengthM = pathLengthM;
diffraction.directDistanceM = directDistanceM;
diffraction.excessPathM = excessPathM;
diffraction.emissionTimeSec = emissionTimeSec;
diffraction.emissionTimeAudioSec = tauAudio;
diffraction.lossReferenceDb = lossReferenceDb;
diffraction.referenceFrequencyHz = config.diffraction.referenceFrequencyHz;
diffraction.converged = converged;
diffraction.residualSec = residualSec;
diffraction.blockingObstacleCount = blockingObstacleCount;
diffraction.unsupportedMultiplePath = unsupportedMultiplePath;
diffraction.multiplePathApproximationUsed = multiplePathApproximationUsed;
diffraction.usedObstacleMask = usedObstacleMask;
diffraction.perObstacle = perObstacle;
end

function selected = selectDominantEdge(sourcePositionM, receiverPositionM, ...
    obstacles, candidateMask, config)
selected = emptyGeometry();
selectedLossDb = -Inf;
directDistanceM = norm(receiverPositionM - sourcePositionM);
blockingObstacleCount = 0;
rejectedByOtherObstacle = false;
blockingIndices=zeros(1,numel(obstacles));

for obstacleIndex = find(candidateMask(:)).'
    [minimumM, maximumM] = obstacleBounds(obstacles(obstacleIndex));
    intersects = acoustics.segmentAABB(sourcePositionM, receiverPositionM, ...
        minimumM, maximumM);
    if ~intersects
        continue;
    end
    blockingObstacleCount = blockingObstacleCount + 1;
    blockingIndices(blockingObstacleCount)=obstacleIndex;

    geometry = acoustics.chooseDiffractionEdge(sourcePositionM, ...
        receiverPositionM, obstacles(obstacleIndex));
    if ~geometry.valid
        continue;
    end
    if pathIntersectsOtherObstacle(sourcePositionM, ...
            geometry.diffractionPointsM, receiverPositionM, obstacles, ...
            obstacleIndex)
        % A single-box finite-thickness path is invalid if any polyline leg
        % crosses another box. Reject it here; the serial-blocker fallback
        % below will attempt one documented vertical taut path.
        rejectedByOtherObstacle = true;
        continue;
    end

    geometry.directDistanceM = directDistanceM;
    geometry.excessPathM = max(geometry.pathLengthM - directDistanceM, 0);
    wavelengthM = config.physics.soundSpeedMps ...
        / config.diffraction.referenceFrequencyHz;
    v = 2 * sqrt(geometry.excessPathM / wavelengthM);
    lossDb = acoustics.knifeEdgeLoss(v);

    if lossDb > selectedLossDb
        selected = geometry;
        selected.obstacleIndex = obstacleIndex;
        selected.obstacleIndices = obstacleIndex;
        selected.multiplePathApproximation = false;
        selected.lossReferenceDb = lossDb;
        selectedLossDb = lossDb;
    end
end
blockingIndices=blockingIndices(1:blockingObstacleCount);
if ~selected.valid && blockingObstacleCount>=1 && rejectedByOtherObstacle
    geometry=acoustics.chooseMultipleObstacleDiffractionPath( ...
        sourcePositionM,receiverPositionM,obstacles,blockingIndices(:));
    if geometry.valid
        geometry.directDistanceM=directDistanceM;
        geometry.excessPathM=max(geometry.pathLengthM-directDistanceM,0);
        wavelengthM=config.physics.soundSpeedMps ...
            /config.diffraction.referenceFrequencyHz;
        v=2*sqrt(geometry.excessPathM/wavelengthM);
        geometry.lossReferenceDb=acoustics.knifeEdgeLoss(v);
        selected=geometry;
    end
end
selected.blockingObstacleCount = blockingObstacleCount;
selected.rejectedByOtherObstacle = rejectedByOtherObstacle;
selected.unsupportedMultiplePath = blockingObstacleCount>0 ...
    && ~selected.valid && rejectedByOtherObstacle;
end

function outputPa = applyFrequencyDependentLoss(inputPa, deltaM, active, fs, config)
windowLength = config.diffraction.windowLengthSamples;
overlap = config.diffraction.overlapSamples;
fftLength = config.diffraction.fftLength;
hop = windowLength - overlap;

if hop <= 0 || fftLength ~= windowLength
    error('acoustics:InvalidDiffractionSTFT', ...
        ['Diffraction currently requires 0 <= overlap < windowLength and ' ...
         'fftLength == windowLength.']);
end

n = (0:windowLength-1).';
window = sqrt(max(0, 0.5 - 0.5*cos(2*pi*n/windowLength)));
nSamples = numel(inputPa);
outputAccumulator = zeros(nSamples + windowLength, 1);
normalization = zeros(nSamples + windowLength, 1);

bin = (0:fftLength-1).';
frequencyHz = min(bin, fftLength-bin) * fs / fftLength;
frequencyForModelHz = max(frequencyHz, config.diffraction.minimumFrequencyHz);

for firstSample = 1:hop:nSamples
    indices = firstSample:min(firstSample + windowLength - 1, nSamples);
    frame = zeros(windowLength, 1);
    frame(1:numel(indices)) = inputPa(indices);
    activeFrame = active(indices);
    if ~any(activeFrame)
        continue;
    end

    representativeDeltaM = median(deltaM(indices(activeFrame)), 'omitnan');
    representativeDeltaM = max(representativeDeltaM, 0);
    v = 2 * sqrt(representativeDeltaM .* frequencyForModelHz ...
        / config.physics.soundSpeedMps);
    lossDb = acoustics.knifeEdgeLoss(v);
    transferMagnitude = 10.^(-lossDb / 20);

    spectrum = fft(frame .* window, fftLength);
    filtered = real(ifft(spectrum .* transferMagnitude, fftLength));
    outputIndices = firstSample:firstSample + windowLength - 1;
    outputAccumulator(outputIndices) = outputAccumulator(outputIndices) ...
        + filtered .* window;
    normalization(outputIndices) = normalization(outputIndices) + window.^2;
end

valid = normalization > 100*eps;
outputAccumulator(valid) = outputAccumulator(valid) ./ normalization(valid);
% WOLA frames straddle visibility transitions. Reapply the geometric mask
% so filtering cannot leak a diffracted component into LOS-clear intervals.
outputPa = outputAccumulator(1:nSamples) .* double(active(:));
end

function blocked = pathIntersectsOtherObstacle(sourcePositionM, edgePointsM, ...
    receiverPositionM, obstacles, selectedObstacleIndex)
%PATHINTERSECTSOTHEROBSTACLE Detect when a single-box path meets another AABB.
blocked = false;
polyline=[sourcePositionM;edgePointsM;receiverPositionM];
for obstacleIndex = 1:numel(obstacles)
    if obstacleIndex == selectedObstacleIndex
        continue;
    end
    [minimumM, maximumM] = obstacleBounds(obstacles(obstacleIndex));
    for legIndex=1:size(polyline,1)-1
        legBlocked=acoustics.segmentAABB(polyline(legIndex,:), ...
            polyline(legIndex+1,:),minimumM,maximumM);
        if legBlocked
            blocked = true;
            return;
        end
    end
end
end

function values = interpFinite(time, valuesAtTime, queryTime, fallback)
valid = isfinite(valuesAtTime);
if nnz(valid) >= 2
    values = interp1(time(valid), valuesAtTime(valid), queryTime, 'linear', 'extrap');
elseif nnz(valid) == 1
    values = repmat(valuesAtTime(valid), size(queryTime));
else
    if isscalar(fallback)
        values = repmat(fallback, size(queryTime));
    else
        values = fallback;
    end
end
end

function times = geometryTimes(observationTimeSec, stepSec)
firstTime = observationTimeSec(1);
lastTime = observationTimeSec(end);
times = (firstTime:stepSec:lastTime).';
if isempty(times) || times(end) < lastTime
    times(end+1, 1) = lastTime;
end
if isscalar(times)
    times(end+1, 1) = lastTime + eps(max(1, abs(lastTime)));
end
end

function geometry = emptyGeometry()
geometry.valid = false;
geometry.pointM = [NaN, NaN, NaN];
geometry.secondPointM = [NaN, NaN, NaN];
geometry.diffractionPointsM = nan(2,3);
geometry.sourceDistanceM = NaN;
geometry.surfaceDistanceM = NaN;
geometry.receiverDistanceM = NaN;
geometry.pathLengthM = NaN;
geometry.directDistanceM = NaN;
geometry.excessPathM = NaN;
geometry.obstacleIndex = NaN;
geometry.lossReferenceDb = NaN;
geometry.blockingObstacleCount = 0;
geometry.rejectedByOtherObstacle = false;
geometry.unsupportedMultiplePath = false;
geometry.obstacleIndices = zeros(1,0);
geometry.multiplePathApproximation = false;
end

function [minimumM, maximumM] = obstacleBounds(obstacle)
if isfield(obstacle, 'minCornerM')
    minimumM = obstacle.minCornerM;
    maximumM = obstacle.maxCornerM;
elseif isfield(obstacle, 'minimumM')
    minimumM = obstacle.minimumM;
    maximumM = obstacle.maximumM;
else
    halfSize = [obstacle.widthM/2, obstacle.depthM/2, obstacle.heightM/2];
    minimumM = obstacle.centerM - halfSize;
    maximumM = obstacle.centerM + halfSize;
end
end

function tableOut = makePerObstacleTable(obstacles, usedIndex, usedObstacleMask, pointM, ...
    secondPointM, d1, surfaceDistanceM, d2, pathLengthM, lossDb, active)
nObstacles = numel(obstacles);
ObstacleIndex = (1:nObstacles).';
DiffractionUsed = false(nObstacles, 1);
DiffractionPointX_M = nan(nObstacles, 1);
DiffractionPointY_M = nan(nObstacles, 1);
DiffractionPointZ_M = nan(nObstacles, 1);
SecondDiffractionPointX_M = nan(nObstacles, 1);
SecondDiffractionPointY_M = nan(nObstacles, 1);
SecondDiffractionPointZ_M = nan(nObstacles, 1);
SourceToEdgeM = nan(nObstacles, 1);
SurfacePathM = nan(nObstacles, 1);
EdgeToReceiverM = nan(nObstacles, 1);
DiffractionPathM = nan(nObstacles, 1);
DiffractionLossDb = nan(nObstacles, 1);

for obstacleIndex = 1:nObstacles
    frames = find(active & (usedIndex == obstacleIndex ...
        | usedObstacleMask(:,obstacleIndex)));
    if isempty(frames)
        continue;
    end
    DiffractionUsed(obstacleIndex) = true;
    [DiffractionLossDb(obstacleIndex), localIndex] = max(lossDb(frames));
    frame = frames(localIndex);
    DiffractionPointX_M(obstacleIndex) = pointM(frame, 1);
    DiffractionPointY_M(obstacleIndex) = pointM(frame, 2);
    DiffractionPointZ_M(obstacleIndex) = pointM(frame, 3);
    SecondDiffractionPointX_M(obstacleIndex) = secondPointM(frame, 1);
    SecondDiffractionPointY_M(obstacleIndex) = secondPointM(frame, 2);
    SecondDiffractionPointZ_M(obstacleIndex) = secondPointM(frame, 3);
    SourceToEdgeM(obstacleIndex) = d1(frame);
    SurfacePathM(obstacleIndex) = surfaceDistanceM(frame);
    EdgeToReceiverM(obstacleIndex) = d2(frame);
    DiffractionPathM(obstacleIndex) = pathLengthM(frame);
end

tableOut = table(ObstacleIndex, DiffractionUsed, DiffractionPointX_M, ...
    DiffractionPointY_M, DiffractionPointZ_M, SecondDiffractionPointX_M, ...
    SecondDiffractionPointY_M, SecondDiffractionPointZ_M, SourceToEdgeM, ...
    SurfacePathM, EdgeToReceiverM, DiffractionPathM, DiffractionLossDb);
end
