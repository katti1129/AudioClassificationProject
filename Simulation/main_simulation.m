%% MAIN_SIMULATION Integrated ambulance acoustic simulation entry point.
% Edit only the CONFIG fields below for a new experiment. All distances are
% in metres, time in seconds, velocity in m/s, acceleration in m/s^2,
% frequency in Hz, and calibrated acoustic signals in Pa.

clear; clc;

config = default_config();

% Example experiment overrides:

% 救急車：時速60 km
% config.source.initialVelocityMps = [60/3.6, 0, 0];

% 受信者：時速30 km
% config.receiver.initialVelocityMps = [0, 0, 0];
% config.obstacle.seed = 1;
% config.reflection.planes(1).pressureReflectionCoefficient = 0.6;

results = acoustics.runSimulation(config);

fprintf('\nSimulation complete: %s\n', results.simulationId);
fprintf('Output directory: %s\n', results.output.directory);
fprintf('Final peak pressure: %.6g Pa\n', max(abs(results.signals.finalPa)));
fprintf('WAV scale: %.6g Pa per digital full scale\n', results.output.paPerFullScale);
