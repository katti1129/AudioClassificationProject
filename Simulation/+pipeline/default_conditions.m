function rows = default_conditions(count, baseConfig)
%DEFAULT_CONDITIONS Create one table row per requested final WAV.
%   ROWS = DEFAULT_CONDITIONS(N,CONFIG) maps existing x-axis trajectory
%   settings. CPA_m is positive receiver-source y separation [m].
if nargin < 2, baseConfig = default_config(); end
validateattributes(count,{'numeric'},{'scalar','integer','>=',1,'<=',100000});
p = pipeline.ground_plane_index(baseConfig);
coefficient = NaN;
if ~isempty(p)
    coefficient = baseConfig.reflection.planes(p).pressureReflectionCoefficient;
end
profile = "constant_velocity";
if any([baseConfig.source.accelerationMps2,baseConfig.receiver.accelerationMps2]~=0)
    profile = "constant_acceleration";
end
row = table(1,string(baseConfig.audio.inputFile), ...
    abs(baseConfig.receiver.initialPositionM(2)-baseConfig.source.initialPositionM(2)), ...
    baseConfig.source.initialVelocityMps(1)*3.6, ...
    baseConfig.receiver.initialVelocityMps(1)*3.6,profile, ...
    baseConfig.source.accelerationMps2(1),baseConfig.receiver.accelerationMps2(1), ...
    baseConfig.simulation.durationSec,coefficient,logical(baseConfig.obstacle.enabled), ...
    baseConfig.obstacle.count,baseConfig.obstacle.seed, ...
    logical(baseConfig.diffraction.enabled),logical(baseConfig.reflection.enabled), ...
    'VariableNames',pipeline.condition_schema().names);
rows = row(ones(count,1),:);
rows.No = (1:count)';
rows = pipeline.assign_seeds(rows,baseConfig.obstacle.seed);
end

