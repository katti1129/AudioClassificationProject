function path = solveDirectPath(sourceConfig, receiverConfig, observationTimeSec, ...
    soundSpeedMps, solverConfig)
%SOLVEDIRECTPATH Solve moving-Source/moving-Receiver retarded propagation.
%   PATH = SOLVEDIRECTPATH(SOURCECONFIG, RECEIVERCONFIG, T, C, SOLVER)
%   solves, for every reception time t [s],
%       t = tau + |x_r(t)-x_s(tau)|/c.
%   Newton iteration evaluates Source position at emission time tau and
%   Receiver position at reception time t. PATH contains distance [m],
%   delay [s], emission time [s], propagation direction, convergence, and
%   the instantaneous Doppler frequency factor d(tau)/dt.
%
%   Doppler factor:
%       (1 - n dot v_receiver/c) / (1 - n dot v_source/c)
%   where n points from Source at tau to Receiver at t.
%   Reference: NASA RP-1258, moving observer/source retarded-time relation.

arguments
    sourceConfig (1,1) struct
    receiverConfig (1,1) struct
    observationTimeSec (:,1) double
    soundSpeedMps (1,1) double {mustBePositive}
    solverConfig (1,1) struct
end

t = observationTimeSec(:);
receiver = acoustics.computeTrajectory(receiverConfig, t);
sourceAtReception = acoustics.computeTrajectory(sourceConfig, t);
initialDistance = sqrt(sum((receiver.positionM-sourceAtReception.positionM).^2,2));
tau = t - initialDistance/soundSpeedMps;
converged = false(size(t));
iterations = zeros(size(t));

for iteration = 1:solverConfig.maxIterations
    source = acoustics.computeTrajectory(sourceConfig, tau);
    difference = receiver.positionM - source.positionM;
    distanceM = sqrt(sum(difference.^2,2));
    direction = difference ./ max(distanceM, eps);
    sourceRadialMps = sum(direction .* source.velocityMps, 2);
    derivative = 1 - sourceRadialMps/soundSpeedMps;
    residualSec = tau + distanceM/soundSpeedMps - t;
    active = ~converged;
    newlyConverged = active & abs(residualSec) <= solverConfig.timeToleranceSec;
    iterations(newlyConverged) = iteration;
    converged = converged | newlyConverged;
    if all(converged), break; end
    active = ~converged;

    % Fixed-point iteration is the causal fallback when a Newton step is
    % singular or crosses the reception time.
    fixedPointTau = t - distanceM/soundSpeedMps;
    nextTau = tau;
    nextTau(active) = fixedPointTau(active);
    newtonTau = tau - residualSec ./ derivative;
    useNewton = active & derivative > sqrt(eps) & isfinite(newtonTau) ...
        & newtonTau <= t + solverConfig.timeToleranceSec;
    nextTau(useNewton) = newtonTau(useNewton);
    tau = nextTau;
end

source = acoustics.computeTrajectory(sourceConfig, tau);
difference = receiver.positionM - source.positionM;
distanceM = sqrt(sum(difference.^2,2));
direction = difference ./ max(distanceM, eps);
sourceRadialMps = sum(direction .* source.velocityMps, 2);
receiverRadialMps = sum(direction .* receiver.velocityMps, 2);
denominator = 1 - sourceRadialMps/soundSpeedMps;
numerator = 1 - receiverRadialMps/soundSpeedMps;
dopplerFactor = numerator ./ denominator;
residualSec = tau + distanceM/soundSpeedMps - t;
finalConvergence = abs(residualSec) <= solverConfig.timeToleranceSec;
iterations(~converged & finalConvergence) = solverConfig.maxIterations;
converged = converged | finalConvergence;
iterations(iterations == 0) = solverConfig.maxIterations;
causal = t-tau >= -solverConfig.timeToleranceSec;
valid = converged & causal & denominator > 0 & numerator > 0 ...
    & isfinite(distanceM) & isfinite(dopplerFactor);

path.model = "retarded_time_moving_source_and_receiver";
path.observationTimeSec = t;
path.emissionTimeSec = tau;
path.delaySec = t - tau;
path.distanceM = distanceM;
path.pathLengthM = distanceM;
path.directionSourceToReceiver = direction;
path.sourcePositionM = source.positionM;
path.receiverPositionM = receiver.positionM;
path.sourceVelocityMps = source.velocityMps;
path.receiverVelocityMps = receiver.velocityMps;
path.dopplerFactor = dopplerFactor;
path.residualSec = residualSec;
path.converged = converged;
path.iterations = iterations;
path.causal = causal;
path.valid = valid;

if any(~converged)
    warning('acoustics:DirectRetardedTimeNotConverged', ...
        '%d direct-path samples did not meet the requested tolerance.', nnz(~converged));
end
end
