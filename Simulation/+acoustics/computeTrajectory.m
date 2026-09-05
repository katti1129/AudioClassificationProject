function trajectory = computeTrajectory(entity, timeSec)
%COMPUTETRAJECTORY Evaluate a Cartesian constant-acceleration trajectory.
%   TRAJECTORY = COMPUTETRAJECTORY(ENTITY, TIMESEC) returns position [m],
%   velocity [m/s], and acceleration [m/s^2] at each time [s]. ENTITY must
%   define initialPositionM, initialVelocityMps, and accelerationMps2 as
%   three-element vectors. Zero velocity/acceleration represents a static
%   Source or Receiver.

arguments
    entity (1,1) struct
    timeSec (:,1) double
end

t = timeSec(:);
p0 = reshape(double(entity.initialPositionM), 1, 3);
v0 = reshape(double(entity.initialVelocityMps), 1, 3);
a = reshape(double(entity.accelerationMps2), 1, 3);

trajectory.timeSec = t;
trajectory.positionM = p0 + t .* v0 + 0.5 .* (t.^2) .* a;
trajectory.velocityMps = v0 + t .* a;
trajectory.accelerationMps2 = repmat(a, numel(t), 1);
end
