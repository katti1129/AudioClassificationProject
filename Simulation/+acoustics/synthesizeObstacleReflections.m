function [paths, reflectedPa] = synthesizeObstacleReflections( ...
    sourcePa, sourceTimeSec, sourceConfig, receiverConfig, ...
    observationTimeSec, obstacles, soundSpeedMps, solverConfig, ...
    referenceDistanceM, minimumDistanceM, geometryTimeStepSec)
%SYNTHESIZEOBSTACLEREFLECTIONS Synthesize first-order finite AABB reflections.
%   [PATHS,Y] = SYNTHESIZEOBSTACLEREFLECTIONS(SOURCEPA,SOURCETIME,
%   SOURCECONFIG,RECEIVERCONFIG,OBSERVATIONTIME,OBSTACLES,C,SOLVER,
%   REFERENCEDISTANCE,MINIMUMDISTANCE,GEOMETRYSTEP) treats each box top and
%   four vertical sides as one-sided finite specular planes. Moving Source
%   and Receiver retarded times are solved at geometry times [s], then
%   emission time, total path length [m], and validity are interpolated to
%   the audio grid. Y is calibrated pressure [Pa].
%
%   Each face uses its obstacle's signed pressure reflection coefficient.
%   Both path legs are tested against all boxes; only endpoint contact with
%   the reflecting box is exempted. Bottom faces are omitted because boxes
%   rest on the ground.

arguments
    sourcePa (:,1) double
    sourceTimeSec (:,1) double
    sourceConfig (1,1) struct
    receiverConfig (1,1) struct
    observationTimeSec (:,1) double
    obstacles
    soundSpeedMps (1,1) double {mustBePositive}
    solverConfig (1,1) struct
    referenceDistanceM (1,1) double {mustBePositive}
    minimumDistanceM (1,1) double {mustBePositive}
    geometryTimeStepSec (1,1) double {mustBePositive}
end

reflectedPa=zeros(size(observationTimeSec));
paths=struct([]);
if isempty(obstacles)
    return;
end

analysisTimeSec=geometryTimes(observationTimeSec,geometryTimeStepSec);
pathCount=0;
for obstacleIndex=1:numel(obstacles)
    planes=boxPlanes(obstacles(obstacleIndex),obstacleIndex);
    for faceIndex=1:numel(planes)
        path=acoustics.solveReflectionPath(sourceConfig,receiverConfig, ...
            analysisTimeSec,planes(faceIndex),soundSpeedMps,solverConfig);
        validBeforeOcclusion=path.valid;
        [visible,blockedMatrix]=acoustics.computeBrokenPathVisibility( ...
            path.sourcePositionM,path.reflectionPointM,path.receiverPositionM, ...
            obstacles,obstacleIndex);
        path.valid=path.valid & visible;
        path.validBeforeOcclusion=validBeforeOcclusion;
        path.blockedByObstacle=blockedMatrix;
        path.obstacleIndex=obstacleIndex;
        path.obstacleId=string(obstacles(obstacleIndex).id);
        path.faceName=planes(faceIndex).faceName;

        validAudio=logical(interp1(analysisTimeSec,double(path.valid), ...
            observationTimeSec,'previous',0));
        emissionAudio=interp1(analysisTimeSec,path.emissionTimeSec, ...
            observationTimeSec,'linear','extrap');
        distanceAudio=interp1(analysisTimeSec,path.distanceM, ...
            observationTimeSec,'linear','extrap');
        emittedPa=interp1(sourceTimeSec,sourcePa,emissionAudio,'linear',0);
        spreading=referenceDistanceM./max(distanceAudio,minimumDistanceM);
        reflectedPa=reflectedPa+emittedPa.*spreading ...
            .*planes(faceIndex).pressureReflectionCoefficient.*double(validAudio);

        pathCount=pathCount+1;
        if pathCount==1
            paths=path;
        else
            paths(pathCount)=path;
        end
    end
end
end

function planes=boxPlanes(obstacle,obstacleIndex)
%BOXPLANES Convert exposed AABB faces to bounded one-sided planes.
mn=reshape(obstacle.minCornerM,1,3);
mx=reshape(obstacle.maxCornerM,1,3);
coefficient=obstacle.pressureReflectionCoefficient;
names=["top","x_min","x_max","y_min","y_max"];
points=[(mn+mx)/2; mn(1),(mn(2)+mx(2))/2,(mn(3)+mx(3))/2; ...
    mx(1),(mn(2)+mx(2))/2,(mn(3)+mx(3))/2; ...
    (mn(1)+mx(1))/2,mn(2),(mn(3)+mx(3))/2; ...
    (mn(1)+mx(1))/2,mx(2),(mn(3)+mx(3))/2];
points(1,3)=mx(3);
normals=[0 0 1; -1 0 0; 1 0 0; 0 -1 0; 0 1 0];
toleranceM=1e-9;
template=struct('id',"",'pointM',[0 0 0],'normal',[0 0 1], ...
    'pressureReflectionCoefficient',coefficient,'boundsMinM',mn, ...
    'boundsMaxM',mx,'oneSided',true,'faceName',"");
planes=repmat(template,5,1);
for faceIndex=1:5
    planes(faceIndex).id="OBS_"+compose('%03d',obstacleIndex)+"_"+names(faceIndex);
    planes(faceIndex).pointM=points(faceIndex,:);
    planes(faceIndex).normal=normals(faceIndex,:);
    planes(faceIndex).boundsMinM=mn-toleranceM;
    planes(faceIndex).boundsMaxM=mx+toleranceM;
    planes(faceIndex).faceName=names(faceIndex);
end
end

function times=geometryTimes(observationTimeSec,stepSec)
%GEOMETRYTIMES Build a geometry grid that includes the last audio sample.
times=(observationTimeSec(1):stepSec:observationTimeSec(end)).';
if isempty(times) || times(end)<observationTimeSec(end)
    times(end+1,1)=observationTimeSec(end);
end
if isscalar(times)
    times(end+1,1)=observationTimeSec(end)+eps(max(1,abs(observationTimeSec(end))));
end
end
