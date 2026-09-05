function config = validateConfig(config)
%VALIDATECONFIG Validate and normalize the integrated simulation settings.
%   CONFIG = VALIDATECONFIG(CONFIG) validates required fields, vector shapes,
%   physical ranges, and output settings. SI units are used throughout.

arguments
    config (1,1) struct
end

mustBePositiveScalar(config.audio.sampleRateHz, 'audio.sampleRateHz');
validateattributes(config.audio.internalOversampleFactor, {'numeric'}, ...
    {'scalar','integer','positive'}, mfilename, 'audio.internalOversampleFactor');
mustBePositiveScalar(config.simulation.durationSec, 'simulation.durationSec');
mustBePositiveScalar(config.simulation.geometryTimeStepSec, 'simulation.geometryTimeStepSec');
mustBePositiveScalar(config.physics.soundSpeedMps, 'physics.soundSpeedMps');
mustBePositiveScalar(config.physics.minimumDistanceM, 'physics.minimumDistanceM');
mustBePositiveScalar(config.audio.referenceDistanceM, 'audio.referenceDistanceM');
mustBeFiniteScalar(config.audio.referenceSPLdB, 'audio.referenceSPLdB');

config.source = validateEntity(config.source, 'source');
config.receiver = validateEntity(config.receiver, 'receiver');

if ~isfile(config.audio.inputFile)
    error('acoustics:InputNotFound', 'Input WAV does not exist: %s', config.audio.inputFile);
end

if config.physics.minimumDistanceM > config.audio.referenceDistanceM
    warning('acoustics:LargeMinimumDistance', ...
        ['minimumDistanceM exceeds referenceDistanceM. Nearer ranges use the ' ...
         'clamped point-source gain.']);
end

if config.obstacle.enabled
    validateattributes(config.obstacle.count, {'numeric'}, ...
        {'scalar','integer','nonnegative'}, mfilename, 'obstacle.count');
    validateattributes(config.obstacle.seed, {'numeric'}, ...
        {'scalar','integer','nonnegative','finite'}, mfilename, 'obstacle.seed');
    validateRange(config.obstacle.widthRangeM, 'obstacle.widthRangeM');
    validateRange(config.obstacle.depthRangeM, 'obstacle.depthRangeM');
    validateRange(config.obstacle.heightRangeM, 'obstacle.heightRangeM');
    config.obstacle.boundsMinM = row3(config.obstacle.boundsMinM, 'obstacle.boundsMinM');
    config.obstacle.boundsMaxM = row3(config.obstacle.boundsMaxM, 'obstacle.boundsMaxM');
    if any(config.obstacle.boundsMaxM(1:2) <= config.obstacle.boundsMinM(1:2))
        error('acoustics:InvalidObstacleBounds', ...
            'Obstacle x/y maximum bounds must exceed minimum bounds.');
    end
    if ~isempty(config.obstacle.manualObstacles)
        config.obstacle.manualObstacles=validateManualObstacles( ...
            config.obstacle.manualObstacles);
    elseif config.obstacle.count>0
        if isempty(config.obstacle.materials)
            error('acoustics:MissingObstacleMaterials', ...
                'At least one obstacle material is required for random generation.');
        end
        for materialIndex=1:numel(config.obstacle.materials)
            coefficient=config.obstacle.materials(materialIndex) ...
                .pressureReflectionCoefficient;
            validateattributes(coefficient,{'numeric'}, ...
                {'scalar','real','finite'},mfilename, ...
                'obstacle.materials.pressureReflectionCoefficient');
            if abs(coefficient)>1
                warning('acoustics:ObstacleReflectionMagnitudeAboveOne', ...
                    'Obstacle material %s has |pressure coefficient| > 1.', ...
                    string(config.obstacle.materials(materialIndex).name));
            end
        end
    end
end

if ~isfield(config.reflection,'obstacleFacesEnabled')
    config.reflection.obstacleFacesEnabled=false;
end
if config.reflection.enabled
    planes = config.reflection.planes;
    for k = 1:numel(planes)
        planes(k).pointM = row3(planes(k).pointM, sprintf('reflection.planes(%d).pointM', k));
        planes(k).normal = row3(planes(k).normal, sprintf('reflection.planes(%d).normal', k));
        n = norm(planes(k).normal);
        if n <= eps
            error('acoustics:InvalidPlaneNormal', 'Reflection plane %d has a zero normal.', k);
        end
        planes(k).normal = planes(k).normal / n;
        validateattributes(planes(k).pressureReflectionCoefficient, {'numeric'}, ...
            {'scalar','real','finite'}, mfilename, 'pressureReflectionCoefficient');
        if abs(planes(k).pressureReflectionCoefficient) > 1
            warning('acoustics:ReflectionMagnitudeAboveOne', ...
                'Plane %s has |pressure reflection coefficient| > 1.', string(planes(k).id));
        end
        if ~isfield(planes(k),'oneSided')
            planes(k).oneSided=false;
        else
            validateattributes(planes(k).oneSided,{'logical','numeric'}, ...
                {'scalar'},mfilename,'oneSided');
            planes(k).oneSided=logical(planes(k).oneSided);
        end
    end
    config.reflection.planes = planes;
    validateattributes(config.reflection.obstacleFacesEnabled, ...
        {'logical','numeric'},{'scalar'},mfilename,'reflection.obstacleFacesEnabled');
    config.reflection.obstacleFacesEnabled=logical( ...
        config.reflection.obstacleFacesEnabled);
end

if config.fresnel.enabled
    mustBePositiveScalar(config.fresnel.frequencyHz, 'fresnel.frequencyHz');
    validateattributes(config.fresnel.zoneNumber, {'numeric'}, ...
        {'scalar','integer','positive'}, mfilename, 'fresnel.zoneNumber');
end

if config.diffraction.enabled
    mustBePositiveScalar(config.diffraction.referenceFrequencyHz, ...
        'diffraction.referenceFrequencyHz');
    mustBePositiveScalar(config.diffraction.minimumFrequencyHz, ...
        'diffraction.minimumFrequencyHz');
    validateattributes(config.diffraction.windowLengthSamples, {'numeric'}, ...
        {'scalar','integer','positive'}, mfilename, 'diffraction.windowLengthSamples');
    validateattributes(config.diffraction.overlapSamples, {'numeric'}, ...
        {'scalar','integer','nonnegative'}, mfilename, 'diffraction.overlapSamples');
    validateattributes(config.diffraction.fftLength, {'numeric'}, ...
        {'scalar','integer','positive'}, mfilename, 'diffraction.fftLength');
    if config.diffraction.overlapSamples >= config.diffraction.windowLengthSamples
        error('acoustics:InvalidDiffractionOverlap', ...
            'diffraction.overlapSamples must be less than windowLengthSamples.');
    end
    if config.diffraction.fftLength ~= config.diffraction.windowLengthSamples
        error('acoustics:InvalidDiffractionFFT', ...
            'The current WOLA implementation requires fftLength == windowLengthSamples.');
    end
    allowedActions=["warning","error","ignore"];
    action=lower(string(config.diffraction.unsupportedMultiplePathAction));
    if ~isscalar(action) || ~ismember(action,allowedActions)
        error('acoustics:InvalidMultipleDiffractionAction', ...
            ['diffraction.unsupportedMultiplePathAction must be ' ...
             '"warning", "error", or "ignore".']);
    end
    config.diffraction.unsupportedMultiplePathAction=action;
end

validateattributes(config.solver.maxIterations, {'numeric'}, ...
    {'scalar','integer','positive'}, mfilename, 'solver.maxIterations');
mustBePositiveScalar(config.solver.timeToleranceSec, 'solver.timeToleranceSec');

validateattributes(config.output.wavBitsPerSample, {'numeric'}, ...
    {'scalar','integer'}, mfilename, 'output.wavBitsPerSample');
if ~ismember(config.output.wavBitsPerSample, [16, 24, 32, 64])
    error('acoustics:InvalidWavDepth', 'wavBitsPerSample must be 16, 24, 32, or 64.');
end
mustBeFiniteScalar(config.output.fullScaleSPLdB, 'output.fullScaleSPLdB');
validateattributes(config.output.clippingHeadroom, {'numeric'}, ...
    {'scalar','>',0,'<=',1}, mfilename, 'output.clippingHeadroom');
wavPolicies=["error","adaptive_shared"];
wavPolicy=lower(string(config.output.wavClippingPolicy));
if ~isscalar(wavPolicy) || ~ismember(wavPolicy,wavPolicies)
    error('acoustics:InvalidWavClippingPolicy', ...
        'output.wavClippingPolicy must be "error" or "adaptive_shared".');
end
config.output.wavClippingPolicy=wavPolicy;

config.audio.inputFile = char(config.audio.inputFile);
config.output.rootDir = char(config.output.rootDir);
end

function entity = validateEntity(entity, label)
label = string(label);
entity.initialPositionM = row3(entity.initialPositionM, label + ".initialPositionM");
entity.initialVelocityMps = row3(entity.initialVelocityMps, label + ".initialVelocityMps");
entity.accelerationMps2 = row3(entity.accelerationMps2, label + ".accelerationMps2");
end

function value = row3(value, label)
validateattributes(value, {'numeric'}, {'vector','numel',3,'real','finite'}, mfilename, char(label));
value = reshape(double(value), 1, 3);
end

function validateRange(value, label)
validateattributes(value, {'numeric'}, {'vector','numel',2,'real','finite','positive'}, mfilename, label);
if value(2) < value(1)
    error('acoustics:InvalidRange', '%s must be [minimum maximum].', label);
end
end

function mustBePositiveScalar(value, label)
validateattributes(value, {'numeric'}, {'scalar','real','finite','positive'}, mfilename, label);
end

function mustBeFiniteScalar(value, label)
validateattributes(value, {'numeric'}, {'scalar','real','finite'}, mfilename, label);
end

function obstacles=validateManualObstacles(obstacles)
%VALIDATEMANUALOBSTACLES Normalize manually supplied AABB fields and units.
required={'centerM','widthM','depthM','heightM','minCornerM','maxCornerM', ...
    'pressureReflectionCoefficient'};
for obstacleIndex=1:numel(obstacles)
    for fieldIndex=1:numel(required)
        if ~isfield(obstacles,required{fieldIndex})
            error('acoustics:InvalidManualObstacle', ...
                'Manual obstacle %d is missing field %s.', ...
                obstacleIndex,required{fieldIndex});
        end
    end
    obstacles(obstacleIndex).centerM=row3(obstacles(obstacleIndex).centerM, ...
        sprintf('manualObstacles(%d).centerM',obstacleIndex));
    obstacles(obstacleIndex).minCornerM=row3( ...
        obstacles(obstacleIndex).minCornerM, ...
        sprintf('manualObstacles(%d).minCornerM',obstacleIndex));
    obstacles(obstacleIndex).maxCornerM=row3( ...
        obstacles(obstacleIndex).maxCornerM, ...
        sprintf('manualObstacles(%d).maxCornerM',obstacleIndex));
    if any(obstacles(obstacleIndex).maxCornerM ...
            <=obstacles(obstacleIndex).minCornerM)
        error('acoustics:InvalidManualObstacleBounds', ...
            'Manual obstacle %d must have positive extent on x, y, and z.', ...
            obstacleIndex);
    end
    dimensions=obstacles(obstacleIndex).maxCornerM ...
        -obstacles(obstacleIndex).minCornerM;
    supplied=[obstacles(obstacleIndex).widthM, ...
        obstacles(obstacleIndex).depthM,obstacles(obstacleIndex).heightM];
    validateattributes(supplied,{'numeric'}, ...
        {'vector','numel',3,'real','finite','positive'},mfilename, ...
        'manual obstacle dimensions');
    if max(abs(double(supplied)-dimensions))>1e-8
        error('acoustics:InconsistentManualObstacle', ...
            'Manual obstacle %d dimensions do not match its AABB corners.', ...
            obstacleIndex);
    end
    expectedCenter=(obstacles(obstacleIndex).minCornerM ...
        +obstacles(obstacleIndex).maxCornerM)/2;
    if norm(obstacles(obstacleIndex).centerM-expectedCenter)>1e-8
        error('acoustics:InconsistentManualObstacleCenter', ...
            'Manual obstacle %d center does not match its AABB corners.', ...
            obstacleIndex);
    end
    validateattributes(obstacles(obstacleIndex).pressureReflectionCoefficient, ...
        {'numeric'},{'scalar','real','finite'},mfilename, ...
        'manual obstacle pressureReflectionCoefficient');
    if ~isfield(obstacles,'id') || isempty(obstacles(obstacleIndex).id)
        obstacles(obstacleIndex).id="OBS_"+compose('%03d',obstacleIndex);
    end
    if ~isfield(obstacles,'material') || isempty(obstacles(obstacleIndex).material)
        obstacles(obstacleIndex).material="manual";
    end
end
end
