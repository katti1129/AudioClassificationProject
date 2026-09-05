function config = default_config()
%DEFAULT_CONFIG Return the centralized configuration for the integrated simulator.
%   CONFIG = DEFAULT_CONFIG() returns a structure whose values use SI units:
%   position [m], velocity [m/s], acceleration [m/s^2], time [s],
%   frequency/sample rate [Hz], and sound pressure [Pa].

rootDir = fileparts(mfilename('fullpath'));

config.simulation.id = "";                 % Empty: deterministic ID from configuration.
config.simulation.durationSec = 6.0;        % Receiver observation duration [s].
config.simulation.geometryTimeStepSec = 0.01; % Geometry/visibility update interval [s].

config.physics.soundSpeedMps = 343.0;
config.physics.minimumDistanceM = 0.50;     % Point-source near-field safety clamp.
config.physics.referencePressurePa = 20e-6;

config.audio.inputFile = fullfile(rootDir, "data", "input", "ambulance.wav");
config.audio.sampleRateHz = 16000;
config.audio.internalOversampleFactor = 2;   % Reduces time-warp interpolation artefacts.
config.audio.referenceDistanceM = 1.0;
config.audio.referenceSPLdB = 136.0;        % RMS SPL at referenceDistanceM.
config.audio.monoMethod = "mean";
config.audio.loopInput = false;             % False: zero pad if duration exceeds WAV.

% Constant-acceleration Cartesian trajectories.
config.source.initialPositionM = [-50.0, 0.0, 1.5];
config.source.initialVelocityMps = [60/3.6, 0.0, 0.0];
config.source.accelerationMps2 = [0.0, 0.0, 0.0];

config.receiver.initialPositionM = [0.0, 10.0, 1.2];
config.receiver.initialVelocityMps = [0.0, 0.0, 0.0];
config.receiver.accelerationMps2 = [0.0, 0.0, 0.0];

config.solver.maxIterations = 20;
config.solver.timeToleranceSec = 1e-10;

% First-order specular reflections from configured static planes.
config.reflection.enabled = true;
config.reflection.planes = struct( ...
    'id', "ground", ...
    'pointM', [0.0, 0.0, 0.0], ...
    'normal', [0.0, 0.0, 1.0], ...
    'pressureReflectionCoefficient', 0.60, ...
    'boundsMinM', [-Inf, -Inf, -Inf], ...
    'boundsMaxM', [ Inf,  Inf,  Inf], ...
    'oneSided', true);
config.reflection.obstacleFacesEnabled = true;

% Seeded axis-aligned boxes resting on z=0.
config.obstacle.enabled = true;
config.obstacle.count = 24;
config.obstacle.seed = 1;
config.obstacle.boundsMinM = [-45.0, -5.0, 0.0];
config.obstacle.boundsMaxM = [ 45.0, 18.0, 0.0];
config.obstacle.widthRangeM = [0.8, 3.0];
config.obstacle.depthRangeM = [0.8, 3.0];
config.obstacle.heightRangeM = [1.0, 6.0];
config.obstacle.trajectoryClearanceM = 1.0;
config.obstacle.avoidObstacleOverlap = true;
config.obstacle.maximumPlacementAttempts = 10000;
config.obstacle.manualObstacles = struct([]); % Nonempty bypasses random generation.
config.obstacle.materials = struct( ...
    'name', {"concrete", "brick", "generic_hard"}, ...
    'pressureReflectionCoefficient', {0.80, 0.70, 0.60});

% A low analysis frequency gives a conservative (larger) first Fresnel zone.
config.fresnel.enabled = true;
config.fresnel.frequencyHz = 500.0;
config.fresnel.zoneNumber = 1;

% Frequency-dependent dominant single-knife-edge approximation.
config.diffraction.enabled = true;
config.diffraction.model = ...
    "finite_AABB_with_serial_vertical_fallback_path_equivalent_ITU_R_P526";
config.diffraction.windowLengthSamples = 512;
config.diffraction.overlapSamples = 384;
config.diffraction.fftLength = 512;
config.diffraction.referenceFrequencyHz = 1000.0;
config.diffraction.minimumFrequencyHz = 20.0;
config.diffraction.unsupportedMultiplePathAction = "warning"; % warning|error|ignore

config.output.rootDir = fullfile(rootDir, "data", "output", "integrated");
config.output.writeComponentWav = true;
config.output.writeMat = true;
config.output.writeExcel = true;
config.output.writeFigures = true;
config.output.wavBitsPerSample = 32;         % IEEE single for double/single input.
config.output.fullScaleSPLdB = 154.0;        % Fixed nominal Pa represented by WAV ±1.
config.output.clippingHeadroom = 0.99;
config.output.wavClippingPolicy = "error";   % error|adaptive_shared
config.output.closeFiguresAfterSave = true;
config.output.overwrite = true;

config.metadata.modelVersion = "1.0.0";
config.metadata.notes = "Integrated geometric-acoustics ambulance simulation";
end
