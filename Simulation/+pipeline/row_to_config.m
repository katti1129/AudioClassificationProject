function config = row_to_config(row, baseConfig, validateAcoustics)
%ROW_TO_CONFIG Map one GUI condition to the existing acoustic config.
%   X-only velocity/acceleration [km/h -> m/s, m/s^2]. Source position and
%   Receiver x/z remain from BASECONFIG. Receiver y = Source y + CPA_m [m].
%   Ground coefficient changes only the plane with ID ground. Other plane
%   and material coefficients, solver, Fresnel, calibration etc. are retained.
%   VALIDATEACOUSTICS defaults true. Batch uses false to name/snapshot a
%   mapped condition even when its input WAV is missing; run_single validates.
if nargin<3, validateAcoustics=true; end
assert(istable(row)&&height(row)==1,'pipeline:RowType','Expected one table row.');
schema = pipeline.condition_schema();
assert(all(ismember(schema.names,row.Properties.VariableNames)), ...
    'pipeline:RowSchema','Condition columns do not match the schema.');
for k=1:numel(schema.numericNames)
    field = schema.numericNames{k};
    if strcmp(field,'GroundReflectionCoeff') && isnan(row.(field))
        continue;
    end
    validateattributes(row.(field),{'numeric'},{'scalar','real','finite'},mfilename,field);
end
for k=1:numel(schema.logicalNames)
    value=row.(schema.logicalNames{k});
    assert(isscalar(value)&&(islogical(value)||isnumeric(value)) ...
        && ismember(value,[0 1]),'pipeline:LogicalValue','ON/OFF must be 0 or 1.');
end
validateattributes(row.CPA_m,{'numeric'},{'nonnegative'});
validateattributes(row.DurationSec,{'numeric'},{'positive'});
validateattributes(row.ObstacleCount,{'numeric'},{'integer','nonnegative'});
validateattributes(row.Seed,{'numeric'},{'integer','>=',0,'<=',2^32-1});
profile = string(row.Profile);
assert(isscalar(profile)&&ismember(profile,string(schema.profiles)), ...
    'pipeline:Profile','Unknown velocity profile.');
config=baseConfig;
config.audio.inputFile=char(string(row.InputWAV));
config.source.initialVelocityMps=[row.SourceVelocityKmh/3.6 0 0];
config.receiver.initialVelocityMps=[row.ReceiverVelocityKmh/3.6 0 0];
config.source.accelerationMps2=[row.SourceAccelerationMps2 0 0];
config.receiver.accelerationMps2=[row.ReceiverAccelerationMps2 0 0];
if profile=="constant_velocity"
    assert(row.SourceAccelerationMps2==0 && row.ReceiverAccelerationMps2==0, ...
        'pipeline:ProfileAcceleration', ...
        'constant_velocity requires both accelerations to be zero.');
end
config.receiver.initialPositionM(2)=config.source.initialPositionM(2)+row.CPA_m;
config.simulation.durationSec=row.DurationSec;
config.simulation.id="";
config.obstacle.enabled=logical(row.Obstacle);
config.obstacle.count=row.ObstacleCount;
config.obstacle.seed=row.Seed;
config.reflection.enabled=logical(row.Reflection);
config.diffraction.enabled=logical(row.Diffraction);
p=pipeline.ground_plane_index(config);
if isempty(p)
    assert(isnan(row.GroundReflectionCoeff),'pipeline:NoGroundPlane', ...
        'Base config has no ground plane. GroundReflectionCoeff must be NaN.');
else
    validateattributes(row.GroundReflectionCoeff,{'numeric'},{'scalar','real','finite'});
    config.reflection.planes(p).pressureReflectionCoefficient=row.GroundReflectionCoeff;
end
% Manual obstacles would silently ignore the row's count and seed controls.
assert(isempty(config.obstacle.manualObstacles),'pipeline:ManualObstacles', ...
    'The condition-table preset requires empty manualObstacles. Use run_single for manual geometry.');
if validateAcoustics, config=acoustics.validateConfig(config); end
assert(strcmpi(config.output.wavClippingPolicy,'error'), ...
    'pipeline:FixedScale','Dataset generation requires wavClippingPolicy=error.');
end
