function [selectedObstacles, diagnostics] = fresnelSelect(obstacles, ...
    sourcePositionsM, receiverPositionsM, frequenciesHz, soundSpeedMps, ...
    zoneNumber)
%FRESNELSELECT Conservatively select boxes near the moving first Fresnel zone.
%   [SELECTED,DIAGNOSTICS] = FRESNELSELECT(OBSTACLES,SOURCEPOSITIONSM,
%   RECEIVERPOSITIONSM,FREQUENCIESHZ,C) uses the lowest supplied frequency
%   [Hz], hence the largest first Fresnel zone. The exact point-ellipsoid
%   condition is d1+d2 <= D+n*lambda/2 for zone number n. For an AABB, its
%   center is expanded by the box bounding-sphere radius:
%   centerPath-2*rho <= D+n*lambda/2.
%   This is a conservative broad-phase test intended not to discard a box
%   that might intersect the ellipsoid; it is not removal from the physical
%   scene. Positions/distances use [m], C uses [m/s].
%
%   Reference: ITU-R P.526-16, first Fresnel ellipsoid definition.

arguments
    obstacles
    sourcePositionsM (:,3) double
    receiverPositionsM (:,3) double
    frequenciesHz (:,1) double {mustBePositive}
    soundSpeedMps (1,1) double {mustBePositive}
    zoneNumber (1,1) double {mustBePositive,mustBeInteger} = 1
end

if size(sourcePositionsM,1)~=size(receiverPositionsM,1)
    error('acoustics:FresnelSize','Source and Receiver position rows must match.');
end
nObstacles=numel(obstacles); nTimes=size(sourcePositionsM,1);
frequencyHz=min(frequenciesHz);
wavelengthM=soundSpeedMps/frequencyHz;
intersectsByTime=false(nTimes,nObstacles);
betweenByTime=false(nTimes,nObstacles);
marginByTime=inf(nTimes,nObstacles);
localRadiusByTime=zeros(nTimes,nObstacles);

for timeIndex=1:nTimes
    source=sourcePositionsM(timeIndex,:); receiver=receiverPositionsM(timeIndex,:);
    axisVector=receiver-source; directDistance=norm(axisVector);
    if directDistance<=eps, continue; end
    axisUnit=axisVector/directDistance;
    threshold=directDistance+zoneNumber*wavelengthM/2;
    for obstacleIndex=1:nObstacles
        obstacle=obstacles(obstacleIndex);
        center=obstacle.centerM;
        radius=0.5*norm([obstacle.widthM,obstacle.depthM,obstacle.heightM]);
        projected=dot(center-source,axisUnit);
        between=projected+radius>=0 && projected-radius<=directDistance;
        centerPath=norm(center-source)+norm(receiver-center);
        margin=centerPath-2*radius-threshold;
        intersects=between && margin<=0;
        clamped=max(0,min(directDistance,projected));
        localRadius=sqrt(max(0,zoneNumber*wavelengthM*clamped*(directDistance-clamped) ...
            /directDistance));
        betweenByTime(timeIndex,obstacleIndex)=between;
        intersectsByTime(timeIndex,obstacleIndex)=intersects;
        marginByTime(timeIndex,obstacleIndex)=margin;
        localRadiusByTime(timeIndex,obstacleIndex)=localRadius;
    end
end

candidateMask=any(intersectsByTime,1).';
diagnostics.model="first_Fresnel_ellipsoid_AABB_bounding_sphere_conservative";
diagnostics.frequencyHz=frequencyHz;
diagnostics.wavelengthM=wavelengthM;
diagnostics.zoneNumber=zoneNumber;
diagnostics.candidateMask=candidateMask;
diagnostics.selectedMask=candidateMask;
diagnostics.intersectsMask=candidateMask;
diagnostics.betweenEndpointsMask=any(betweenByTime,1).';
diagnostics.minimumClearanceM=min(marginByTime,[],1).';
diagnostics.maximumLocalRadiusM=max(localRadiusByTime,[],1).';
diagnostics.intersectsByTime=intersectsByTime;
diagnostics.betweenByTime=betweenByTime;
selectedObstacles=obstacles(candidateMask);
end
