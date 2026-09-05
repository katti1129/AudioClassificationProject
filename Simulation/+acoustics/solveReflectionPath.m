function path = solveReflectionPath(sourceConfig, receiverConfig, observationTimeSec, ...
    plane, soundSpeedMps, solverConfig)
%SOLVEREFLECTIONPATH Solve a first-order specular plane-reflection path.
%   PATH = SOLVEREFLECTIONPATH(SOURCECONFIG, RECEIVERCONFIG, T, PLANE, C,
%   SOLVER) mirrors the moving Source across a static plane and solves the
%   image-source retarded-time equation. It returns the physical reflection
%   point [m], broken path length [m], delay [s], validity, and Doppler
%   factor. PLANE.pressureReflectionCoefficient is a pressure-amplitude
%   coefficient, not an energy coefficient.
%
%   This is the first-order image-source method of Allen & Berkley (1979).
%   The default model uses a real, frequency-independent coefficient.

arguments
    sourceConfig (1,1) struct
    receiverConfig (1,1) struct
    observationTimeSec (:,1) double
    plane (1,1) struct
    soundSpeedMps (1,1) double {mustBePositive}
    solverConfig (1,1) struct
end

t = observationTimeSec(:);
n = reshape(double(plane.normal),1,3);
n = n/norm(n);
planePoint = reshape(double(plane.pointM),1,3);
imageConfig = mirroredEntity(sourceConfig, planePoint, n);
imagePath = acoustics.solveDirectPath(imageConfig, receiverConfig, t, ...
    soundSpeedMps, solverConfig);

tau = imagePath.emissionTimeSec;
receiver = acoustics.computeTrajectory(receiverConfig,t);
source = acoustics.computeTrajectory(sourceConfig,tau);
imagePosition = imagePath.sourcePositionM;
difference = receiver.positionM-imagePosition;

denominator=sum(difference.*n,2);
numerator=sum((planePoint-imagePosition).*n,2);
lineParameter=nan(size(t));
nonparallel=abs(denominator)>100*eps;
lineParameter(nonparallel)=numerator(nonparallel)./denominator(nonparallel);
reflectionPointM=imagePosition+lineParameter.*difference;

sourceSide=sum((source.positionM-planePoint).*n,2);
receiverSide=sum((receiver.positionM-planePoint).*n,2);
samePhysicalSide=sourceSide.*receiverSide>=0;
if isfield(plane,'oneSided') && plane.oneSided
    sideToleranceM=1e-9;
    samePhysicalSide=sourceSide>=-sideToleranceM ...
        & receiverSide>=-sideToleranceM;
end
valid=imagePath.valid & isfinite(lineParameter) ...
    & lineParameter>=0 & lineParameter<=1 & samePhysicalSide;
if isfield(plane,'boundsMinM') && isfield(plane,'boundsMaxM')
    lower=reshape(plane.boundsMinM,1,3); upper=reshape(plane.boundsMaxM,1,3);
    valid=valid & all(reflectionPointM>=lower & reflectionPointM<=upper,2);
end

d1=sqrt(sum((source.positionM-reflectionPointM).^2,2));
d2=sqrt(sum((receiver.positionM-reflectionPointM).^2,2));
brokenLength=d1+d2;
distanceM=imagePath.distanceM;
distanceM(valid)=brokenLength(valid); % Equal to the image distance for valid paths.

path.id=string(plane.id);
path.model="first_order_specular_image_source";
path.observationTimeSec=t;
path.emissionTimeSec=tau;
path.delaySec=t-tau;
path.distanceM=distanceM;
path.pathLengthM=distanceM;
path.sourceToReflectionM=d1;
path.reflectionToReceiverM=d2;
path.reflectionPointM=reflectionPointM;
path.sourcePositionM=source.positionM;
path.receiverPositionM=receiver.positionM;
path.imageSourcePositionM=imagePosition;
path.dopplerFactor=imagePath.dopplerFactor;
path.residualSec=imagePath.residualSec;
path.causal=imagePath.causal;
path.valid=valid;
path.converged=imagePath.converged;
path.iterations=imagePath.iterations;
path.pressureReflectionCoefficient=plane.pressureReflectionCoefficient;
end

function image = mirroredEntity(entity,planePoint,normal)
image=entity;
image.initialPositionM=mirrorPosition(entity.initialPositionM,planePoint,normal);
image.initialVelocityMps=mirrorVector(entity.initialVelocityMps,normal);
image.accelerationMps2=mirrorVector(entity.accelerationMps2,normal);
end

function value=mirrorPosition(value,planePoint,normal)
value=reshape(double(value),1,3);
value=value-2*dot(value-planePoint,normal)*normal;
end

function value=mirrorVector(value,normal)
value=reshape(double(value),1,3);
value=value-2*dot(value,normal)*normal;
end
