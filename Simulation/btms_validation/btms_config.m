function cfg = btms_config()
%BTMS_CONFIG Configuration for stationary rigid-edge validation.
% Output cfg: SI units throughout; angles rad, fs Hz, duration s.
root = fileparts(mfilename('fullpath'));
cfg.c = 343;
cfg.fs = 48000;
cfg.irDuration = 0.08;
cfg.quadratureOrder = 64; % 32 nodes failed the near-boundary convergence test.
cfg.frequencies = [125 500 1000 2000 4000];
cfg.geometry.alpha = 3*pi/2; % Exterior opening: solid wedge is 90 degrees.
cfg.geometry.source = [5 pi/6 -0.4]; % [radius m, azimuth rad, edge-axis z m]
cfg.geometry.receiver = [6 7*pi/6 0.7];
cfg.geometry.edgeLimits = [-Inf Inf];
cfg.finiteEdgeLimits = [-3 3]; % Finite contribution, NOT a complete finite wall.
cfg.boundaryOffsets = [1e-2 1e-3 1e-4 1e-5 1e-6]; % rad
cfg.outputDir = fullfile(root,'output');
end
