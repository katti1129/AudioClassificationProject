function config = moving_receiver_rms_config()
%MOVING_RECEIVER_RMS_CONFIG Default SI-unit settings; no acceleration.
% Input: none. Output: editable configuration for moving_receiver_rms.
root = fileparts(fileparts(mfilename('fullpath')));
config.inputFile = fullfile(root, 'data', 'input', 'ambulance.wav');
config.outputRoot = fullfile(root, 'data', 'output', 'doppler_moving_receiver_rms');
config.fs = 16000;                         % Output/processing sample rate [Hz]
config.c = 343;                            % Sound speed in stationary air [m/s]
config.source.positionM = [-60, 0, 1.5];    % Position at emission t=0 [m]
config.source.velocityMps = [60/3.6, 0, 0]; % Constant velocity [m/s]
config.receiver.positionM = [0, 10, 1.2];   % Position at reception t=0 [m]
config.receiver.velocityMps = [1.4, 0, 0];  % Walking in the same +x direction
config.referenceDistanceM = 1;             % Free-field reference distance [m]
config.sourceSplDb = 136;                   % Assumed whole-file RMS SPL at reference
config.minimumDistanceM = 0.1;             % Reject closer paths (not a near-field model)
config.reflection.enabled = true;
config.reflection.coefficient = 0.8;        % Real pressure coefficient, not energy
config.wavFullScalePa = 2e-5 * 10^(154/20);  % Fixed Pa per WAV amplitude 1; no peak scaling
config.makeFigures = true;
config.figureVisible = 'on';
end
