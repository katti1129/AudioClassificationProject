function [paths, reflectedPa] = synthesizeReflections(sourcePa, sourceTimeSec, ...
    sourceConfig, receiverConfig, observationTimeSec, planes, ...
    soundSpeedMps, solverConfig, referenceDistanceM, minimumDistanceM, ...
    obstacles, geometryTimeStepSec)
%SYNTHESIZEREFLECTIONS Synthesize configured first-order image-source paths.
%   [PATHS,Y] = SYNTHESIZEREFLECTIONS(...) returns one diagnostic structure
%   per static plane and their summed pressure Y [Pa]. Each component uses
%   its own retarded emission time [s], total path length [m], spherical
%   spreading, validity mask, and signed pressure reflection coefficient.

arguments
    sourcePa (:,1) double
    sourceTimeSec (:,1) double
    sourceConfig (1,1) struct
    receiverConfig (1,1) struct
    observationTimeSec (:,1) double
    planes
    soundSpeedMps (1,1) double {mustBePositive}
    solverConfig (1,1) struct
    referenceDistanceM (1,1) double {mustBePositive}
    minimumDistanceM (1,1) double {mustBePositive}
    obstacles = struct([])
    geometryTimeStepSec (1,1) double {mustBePositive} = 0.01
end

reflectedPa=zeros(size(observationTimeSec));
paths=struct([]);
for k=1:numel(planes)
    path=acoustics.solveReflectionPath(sourceConfig,receiverConfig, ...
        observationTimeSec,planes(k),soundSpeedMps,solverConfig);
    visibility=true(size(observationTimeSec));
    if ~isempty(obstacles)
        analysisTimeSec=geometryTimes(observationTimeSec,geometryTimeStepSec);
        sourceAnalysis=interp1(observationTimeSec,path.sourcePositionM, ...
            analysisTimeSec,'linear','extrap');
        pointAnalysis=interp1(observationTimeSec,path.reflectionPointM, ...
            analysisTimeSec,'linear','extrap');
        receiverAnalysis=interp1(observationTimeSec,path.receiverPositionM, ...
            analysisTimeSec,'linear','extrap');
        [visibleAnalysis,blockedMatrix]=acoustics.computeBrokenPathVisibility( ...
            sourceAnalysis,pointAnalysis,receiverAnalysis,obstacles);
        visibility=logical(interp1(analysisTimeSec,double(visibleAnalysis), ...
            observationTimeSec,'previous',0));
        path.obstacleVisibilityAnalysisTimeSec=analysisTimeSec;
        path.obstacleVisibleAnalysis=visibleAnalysis;
        path.blockedByObstacleAnalysis=blockedMatrix;
    end
    emittedPa=interp1(sourceTimeSec,sourcePa,path.emissionTimeSec,'linear',0);
    spreading=referenceDistanceM./max(path.distanceM,minimumDistanceM);
    componentPa=emittedPa.*spreading ...
        .*planes(k).pressureReflectionCoefficient.*double(path.valid) ...
        .*double(visibility);
    path.valid=path.valid & visibility;
    path.signalPa=componentPa;
    if isempty(paths),paths=path;else,paths(k)=path;end
    reflectedPa=reflectedPa+componentPa;
end
end

function times=geometryTimes(observationTimeSec,stepSec)
%GEOMETRYTIMES Build a visibility grid including the last audio sample.
times=(observationTimeSec(1):stepSec:observationTimeSec(end)).';
if isempty(times) || times(end)<observationTimeSec(end)
    times(end+1,1)=observationTimeSec(end);
end
if isscalar(times)
    times(end+1,1)=observationTimeSec(end)+eps(max(1,abs(observationTimeSec(end))));
end
end
