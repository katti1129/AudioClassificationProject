function results = writeMetadataExcel(results, config)
%WRITEMETADATAEXCEL Write experiment, obstacle, and path metadata to XLSX.
%   RESULTS = WRITEMETADATAEXCEL(RESULTS, CONFIG) creates Conditions,
%   Obstacles, and Paths sheets. Unavailable geometric quantities are NaN.
%   Distances use [m], time [s], velocity [m/s], acceleration [m/s^2],
%   frequency [Hz], pressure [Pa], and level [dB SPL].

arguments
    results (1,1) struct
    config (1,1) struct
end

if ~config.output.writeExcel
    return;
end

filename = results.output.excelFile;
if isfile(filename)
    delete(filename);
end
conditions = makeConditions(results, config);
obstacles = makeObstacleTable(results, config);
paths = makePathTable(results);
reflections = makeReflectionTable(results);

writetable(conditions, filename, 'Sheet', 'Conditions');
writetable(obstacles, filename, 'Sheet', 'Obstacles');
writetable(paths, filename, 'Sheet', 'Paths');
writetable(reflections, filename, 'Sheet', 'Reflections');
end

function output = makeConditions(results, config)
name = strings(0,1); value = strings(0,1); unit = strings(0,1);
add('SimulationID', results.simulationId, '');
add('ModelVersion', config.metadata.modelVersion, '');
add('ModelNotes', config.metadata.notes, '');
add('InputWAV', config.audio.inputFile, '');
add('InputWAVBytes', getNested(results, {'audio','inputFileBytes'}, NaN), 'bytes');
add('InputWAVModified', getNested(results, {'audio','inputFileModified'}, ""), '');
if isfield(results.audio, 'inputSampleRateHz')
    add('InputSampleRate', results.audio.inputSampleRateHz, 'Hz');
end
add('OutputWAV_Final', getNested(results, {'output','audioFiles','final'}, ""), '');
add('OutputWAV_Direct', getNested(results, {'output','audioFiles','direct'}, ""), '');
add('OutputWAV_Reflected', getNested(results, {'output','audioFiles','reflected'}, ""), '');
add('OutputWAV_Diffracted', getNested(results, {'output','audioFiles','diffracted'}, ""), '');
add('OutputSampleRate', results.sampleRateHz, 'Hz');
add('InternalProcessingSampleRate', getField(results, 'processingSampleRateHz', results.sampleRateHz), 'Hz');
add('SimulationDuration', config.simulation.durationSec, 's');
add('GeometryTimeStep', config.simulation.geometryTimeStepSec, 's');
add('SoundSpeed', config.physics.soundSpeedMps, 'm/s');
add('MinimumDistance', config.physics.minimumDistanceM, 'm');
add('ReferenceDistance', config.audio.referenceDistanceM, 'm');
add('ReferenceSPL_RMS', config.audio.referenceSPLdB, 'dB SPL');
add('UsedInputSegmentReferenceSPL_RMS', ...
    getNested(results, {'audio','usedSegmentReferenceSPLdB'}, NaN), 'dB SPL');
add('UsedInputSegmentReferenceRMSPressure', ...
    getNested(results, {'audio','usedSegmentReferenceRMSPressurePa'}, NaN), 'Pa');
add('SourceInitialPosition', config.source.initialPositionM, 'm [x y z]');
add('SourceInitialVelocity', config.source.initialVelocityMps, 'm/s [x y z]');
add('SourceAcceleration', config.source.accelerationMps2, 'm/s^2 [x y z]');
add('ReceiverInitialPosition', config.receiver.initialPositionM, 'm [x y z]');
add('ReceiverInitialVelocity', config.receiver.initialVelocityMps, 'm/s [x y z]');
add('ReceiverAcceleration', config.receiver.accelerationMps2, 'm/s^2 [x y z]');
add('ObstacleEnabled', config.obstacle.enabled, 'logical');
add('ObstacleCount', numel(results.obstacles), '');
add('RandomSeed', config.obstacle.seed, '');
add('RandomGenerator', 'twister', '');
add('FresnelFrequency', config.fresnel.frequencyHz, 'Hz');
add('DiffractionModel', config.diffraction.model, '');
add('UnsupportedMultipleDiffractionFrames', ...
    nnz(getNested(results, {'diffraction','unsupportedMultiplePath'}, false)), 'frames');
add('MultiplePathApproximationFrames', ...
    nnz(getNested(results, {'diffraction','multiplePathApproximationUsed'}, false)), ...
    'frames');
add('ReflectionPlaneCount', numel(config.reflection.planes) * config.reflection.enabled, '');
add('ObstacleFaceReflectionsEnabled', ...
    config.reflection.enabled && config.reflection.obstacleFacesEnabled, 'logical');
add('ObstacleReflectionPathCount', ...
    numel(getNested(results, {'paths','obstacleReflections'}, struct([]))), 'faces');
add('NominalFullScalePressure', results.output.nominalPaPerFullScale, 'Pa/digital-full-scale');
add('ActualFullScalePressure', results.output.paPerFullScale, 'Pa/digital-full-scale');
add('AdaptiveWAVScaleUsed', results.output.adaptiveScaleUsed, 'logical');
add('WAVClippingPolicy', results.output.wavClippingPolicy, '');
add('FinalPeakPressure', max(abs(results.signals.finalPa)), 'Pa');
add('FinalRMSPressure', sqrt(mean(results.signals.finalPa.^2)), 'Pa');

if config.reflection.enabled
    for planeIndex=1:numel(config.reflection.planes)
        plane=config.reflection.planes(planeIndex);
        prefix="ReflectionPlane"+compose('%02d_',planeIndex);
        add(prefix+"ID",plane.id,'');
        add(prefix+"Point",plane.pointM,'m [x y z]');
        add(prefix+"Normal",plane.normal,'unit vector [x y z]');
        add(prefix+"PressureCoefficient", ...
            plane.pressureReflectionCoefficient,'pressure amplitude ratio');
        add(prefix+"BoundsMin",plane.boundsMinM,'m [x y z]');
        add(prefix+"BoundsMax",plane.boundsMaxM,'m [x y z]');
        add(prefix+"OneSided",plane.oneSided,'logical');
    end
end

output = table(name, value, unit, 'VariableNames', {'Condition','Value','Unit'});

    function add(rowName, rowValue, rowUnit)
        name(end+1,1) = string(rowName);
        value(end+1,1) = stringify(rowValue);
        unit(end+1,1) = string(rowUnit);
    end
end

function output = makeObstacleTable(results, config)
n = numel(results.obstacles);
SimulationID = repmat(string(results.simulationId), n, 1);
ObstacleID = strings(n,1);
RandomSeed = repmat(config.obstacle.seed, n, 1);
X_M = nan(n,1); Y_M = nan(n,1); Z_M = nan(n,1);
Width_M = nan(n,1); Depth_M = nan(n,1); Height_M = nan(n,1);
Material = strings(n,1); ReflectionCoefficient = nan(n,1);
ReflectionUsed = false(n,1); ReflectionFaceCount = zeros(n,1);
BetweenSourceReceiver = false(n,1); LOSBlocked = false(n,1);
InsideFresnel = false(n,1); FresnelSelected = false(n,1);
DiffractionUsed = false(n,1);
DiffractionPointX_M = nan(n,1); DiffractionPointY_M = nan(n,1);
DiffractionPointZ_M = nan(n,1);
SecondDiffractionPointX_M = nan(n,1); SecondDiffractionPointY_M = nan(n,1);
SecondDiffractionPointZ_M = nan(n,1); SourceToObstacle_M = nan(n,1);
ObstacleSurfacePath_M = nan(n,1);
ObstacleToReceiver_M = nan(n,1); DiffractionPath_M = nan(n,1);
DiffractionLoss_dB = nan(n,1);

for k = 1:n
    obstacle = results.obstacles(k);
    ObstacleID(k) = string(fieldOr(obstacle, {'id','obstacleId'}, k));
    center = fieldOr(obstacle, {'centerM','center'}, [NaN NaN NaN]);
    center = reshape(center, 1, []);
    if numel(center) >= 3
        X_M(k)=center(1); Y_M(k)=center(2); Z_M(k)=center(3);
    end
    Width_M(k) = fieldOr(obstacle, {'widthM','width'}, NaN);
    Depth_M(k) = fieldOr(obstacle, {'depthM','depth'}, NaN);
    Height_M(k) = fieldOr(obstacle, {'heightM','height'}, NaN);
    Material(k) = string(fieldOr(obstacle, {'material','materialName'}, ""));
    ReflectionCoefficient(k) = fieldOr(obstacle, ...
        {'pressureReflectionCoefficient','reflectionCoefficient'}, NaN);
end

if isfield(results,'paths') && isfield(results.paths,'obstacleReflections')
    reflectionPaths=results.paths.obstacleReflections;
    for pathIndex=1:numel(reflectionPaths)
        obstacleIndex=reflectionPaths(pathIndex).obstacleIndex;
        if obstacleIndex<1 || obstacleIndex>n, continue; end
        used=any(reflectionPaths(pathIndex).valid);
        ReflectionUsed(obstacleIndex)=ReflectionUsed(obstacleIndex) || used;
        ReflectionFaceCount(obstacleIndex)=ReflectionFaceCount(obstacleIndex)+double(used);
    end
end

if isfield(results, 'fresnel')
    BetweenSourceReceiver = logicalVector(results.fresnel, ...
        {'betweenEndpointsMask','betweenSourceReceiver','betweenMask'}, n, false);
    InsideFresnel = logicalVector(results.fresnel, ...
        {'intersectsMask','insideFresnelMask','candidateMask'}, n, false);
    FresnelSelected = logicalVector(results.fresnel, ...
        {'candidateMask','selectedMask','adoptedMask'}, n, InsideFresnel);
end
if isfield(results, 'obstruction')
    LOSBlocked = logicalVector(results.obstruction, ...
        {'blockedByObstacle','everBlockedByObstacle','obstacleBlockedMask'}, n, false);
end

if isfield(results, 'diffraction') && isfield(results.diffraction, 'perObstacle')
    dTable = results.diffraction.perObstacle;
    for row = 1:height(dTable)
        if ismember('ObstacleIndex', dTable.Properties.VariableNames)
            k = dTable.ObstacleIndex(row);
        else
            k = row;
        end
        if k < 1 || k > n, continue; end
        DiffractionUsed(k) = tableValue(dTable, row, 'DiffractionUsed', false);
        DiffractionPointX_M(k) = tableValue(dTable, row, 'DiffractionPointX_M', NaN);
        DiffractionPointY_M(k) = tableValue(dTable, row, 'DiffractionPointY_M', NaN);
        DiffractionPointZ_M(k) = tableValue(dTable, row, 'DiffractionPointZ_M', NaN);
        SecondDiffractionPointX_M(k) = tableValue(dTable, row, ...
            'SecondDiffractionPointX_M', NaN);
        SecondDiffractionPointY_M(k) = tableValue(dTable, row, ...
            'SecondDiffractionPointY_M', NaN);
        SecondDiffractionPointZ_M(k) = tableValue(dTable, row, ...
            'SecondDiffractionPointZ_M', NaN);
        SourceToObstacle_M(k) = tableValue(dTable, row, 'SourceToEdgeM', NaN);
        ObstacleSurfacePath_M(k) = tableValue(dTable, row, 'SurfacePathM', NaN);
        ObstacleToReceiver_M(k) = tableValue(dTable, row, 'EdgeToReceiverM', NaN);
        DiffractionPath_M(k) = tableValue(dTable, row, 'DiffractionPathM', NaN);
        DiffractionLoss_dB(k) = tableValue(dTable, row, 'DiffractionLossDb', NaN);
    end
end

output = table(SimulationID, ObstacleID, RandomSeed, X_M, Y_M, Z_M, ...
    Width_M, Depth_M, Height_M, Material, ReflectionCoefficient, ...
    ReflectionUsed, ReflectionFaceCount, ...
    BetweenSourceReceiver, LOSBlocked, InsideFresnel, FresnelSelected, ...
    DiffractionUsed, DiffractionPointX_M, DiffractionPointY_M, ...
    DiffractionPointZ_M, SecondDiffractionPointX_M, ...
    SecondDiffractionPointY_M, SecondDiffractionPointZ_M, ...
    SourceToObstacle_M, ObstacleSurfacePath_M, ObstacleToReceiver_M, ...
    DiffractionPath_M, DiffractionLoss_dB);
end

function output = makePathTable(results)
Component = ["direct"; "reflected"; "diffracted"; "final"];
MinimumPath_M = nan(4,1); MaximumPath_M = nan(4,1);
MinimumDelay_s = nan(4,1); MaximumDelay_s = nan(4,1);
PeakPressure_Pa = nan(4,1); RMSPressure_Pa = nan(4,1);

if isfield(results.paths, 'direct')
    MinimumPath_M(1) = min(results.paths.direct.distanceM, [], 'omitnan');
    MaximumPath_M(1) = max(results.paths.direct.distanceM, [], 'omitnan');
    MinimumDelay_s(1) = min(results.paths.direct.delaySec, [], 'omitnan');
    MaximumDelay_s(1) = max(results.paths.direct.delaySec, [], 'omitnan');
end
reflectionDistances=[];
reflectionDelays=[];
reflectionGroups={getNested(results,{'paths','reflections'},struct([])), ...
    getNested(results,{'paths','obstacleReflections'},struct([]))};
for groupIndex=1:numel(reflectionGroups)
    group=reflectionGroups{groupIndex};
    for pathIndex=1:numel(group)
        valid=logical(group(pathIndex).valid(:));
        if any(valid)
            reflectionDistances=[reflectionDistances;group(pathIndex).distanceM(valid)]; %#ok<AGROW>
            reflectionDelays=[reflectionDelays;group(pathIndex).delaySec(valid)]; %#ok<AGROW>
        end
    end
end
if ~isempty(reflectionDistances)
    MinimumPath_M(2)=min(reflectionDistances,[],'omitnan');
    MaximumPath_M(2)=max(reflectionDistances,[],'omitnan');
    MinimumDelay_s(2)=min(reflectionDelays,[],'omitnan');
    MaximumDelay_s(2)=max(reflectionDelays,[],'omitnan');
end
if isfield(results, 'diffraction') && any(results.diffraction.active)
    MinimumPath_M(3) = min(results.diffraction.pathLengthM, [], 'omitnan');
    MaximumPath_M(3) = max(results.diffraction.pathLengthM, [], 'omitnan');
    delays = results.diffraction.pathLengthM / results.config.physics.soundSpeedMps;
    MinimumDelay_s(3) = min(delays, [], 'omitnan');
    MaximumDelay_s(3) = max(delays, [], 'omitnan');
end

signalNames = {'directPa','reflectedPa','diffractedPa','finalPa'};
for k = 1:4
    values = results.signals.(signalNames{k});
    PeakPressure_Pa(k) = max(abs(values));
    RMSPressure_Pa(k) = sqrt(mean(values.^2));
end
output = table(Component, MinimumPath_M, MaximumPath_M, MinimumDelay_s, ...
    MaximumDelay_s, PeakPressure_Pa, RMSPressure_Pa);
end

function output=makeReflectionTable(results)
%MAKEREFLECTIONTABLE Summarize every configured-plane and obstacle-face path.
groups={getNested(results,{'paths','reflections'},struct([])), ...
    getNested(results,{'paths','obstacleReflections'},struct([]))};
types=["configured_plane","obstacle_face"];
nRows=numel(groups{1})+numel(groups{2});
ReflectionID=strings(nRows,1); ReflectionType=strings(nRows,1);
ObstacleID=strings(nRows,1); FaceName=strings(nRows,1);
PressureReflectionCoefficient=nan(nRows,1); ValidFrameCount=zeros(nRows,1);
OccludedFrameCount=zeros(nRows,1); MinimumPath_M=nan(nRows,1);
MaximumPath_M=nan(nRows,1); MinimumDelay_s=nan(nRows,1); MaximumDelay_s=nan(nRows,1);

row=0;
for groupIndex=1:numel(groups)
    group=groups{groupIndex};
    for pathIndex=1:numel(group)
        row=row+1;
        path=group(pathIndex);
        valid=logical(path.valid(:));
        ReflectionID(row)=string(fieldOr(path,{'id'},pathIndex));
        ReflectionType(row)=types(groupIndex);
        ObstacleID(row)=string(fieldOr(path,{'obstacleId'},""));
        FaceName(row)=string(fieldOr(path,{'faceName'},""));
        PressureReflectionCoefficient(row)= ...
            fieldOr(path,{'pressureReflectionCoefficient'},NaN);
        ValidFrameCount(row)=nnz(valid);
        if isfield(path,'blockedByObstacleAnalysis')
            OccludedFrameCount(row)=nnz(any(path.blockedByObstacleAnalysis,2));
        elseif isfield(path,'blockedByObstacle')
            OccludedFrameCount(row)=nnz(any(path.blockedByObstacle,2));
        end
        if any(valid)
            MinimumPath_M(row)=min(path.distanceM(valid),[],'omitnan');
            MaximumPath_M(row)=max(path.distanceM(valid),[],'omitnan');
            MinimumDelay_s(row)=min(path.delaySec(valid),[],'omitnan');
            MaximumDelay_s(row)=max(path.delaySec(valid),[],'omitnan');
        end
    end
end
output=table(ReflectionID,ReflectionType,ObstacleID,FaceName, ...
    PressureReflectionCoefficient,ValidFrameCount,OccludedFrameCount, ...
    MinimumPath_M,MaximumPath_M,MinimumDelay_s,MaximumDelay_s);
end

function result = stringify(value)
if ischar(value) || isstring(value)
    result = string(value);
elseif islogical(value) && isscalar(value)
    result = string(double(value));
elseif isnumeric(value)
    result = string(mat2str(value, 15));
else
    result = string(jsonencode(value));
end
end

function value = fieldOr(item, names, fallback)
value = fallback;
for k = 1:numel(names)
    if isfield(item, names{k})
        value = item.(names{k});
        return;
    end
end
end

function value = getField(item, name, fallback)
if isfield(item, name), value = item.(name); else, value = fallback; end
end

function value = getNested(item, names, fallback)
value = item;
for k = 1:numel(names)
    if ~isstruct(value) || ~isfield(value, names{k})
        value = fallback; return;
    end
    value = value.(names{k});
end
end

function values = logicalVector(item, names, n, fallback)
values = fallback;
if isscalar(values), values = repmat(logical(values), n, 1); end
for k = 1:numel(names)
    if isfield(item, names{k})
        candidate = logical(item.(names{k})(:));
        if numel(candidate) == n, values = candidate; end
        return;
    end
end
end

function value = tableValue(input, row, variable, fallback)
if ismember(variable, input.Properties.VariableNames)
    value = input.(variable)(row);
else
    value = fallback;
end
end
