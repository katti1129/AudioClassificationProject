function result = computeObstruction(sourcePositionsM, receiverPositionsM, ...
    obstacles, analysisTimeSec)
%COMPUTEOBSTRUCTION Determine time-varying 3D line-of-sight obstruction.
%   RESULT = COMPUTEOBSTRUCTION(SOURCEPOSITIONSM, RECEIVERPOSITIONSM,
%   OBSTACLES, ANALYSISTIMESEC) applies exact segment-AABB tests at each
%   geometry time. Positions use [m], time uses [s]. RESULT preserves the
%   full time-by-obstacle matrix so every accepted/rejected blocker remains
%   auditable.

arguments
    sourcePositionsM (:,3) double
    receiverPositionsM (:,3) double
    obstacles
    analysisTimeSec (:,1) double
end

nTimes=size(sourcePositionsM,1);
nObstacles=numel(obstacles);
if size(receiverPositionsM,1)~=nTimes || numel(analysisTimeSec)~=nTimes
    error('acoustics:ObstructionSize','Position arrays and time must have equal rows.');
end
intersectionMatrix=false(nTimes,nObstacles);
firstBlockingIndex=nan(nTimes,1);
for timeIndex=1:nTimes
    for obstacleIndex=1:nObstacles
        hit=acoustics.segmentAABB(sourcePositionsM(timeIndex,:), ...
            receiverPositionsM(timeIndex,:),obstacles(obstacleIndex).minCornerM, ...
            obstacles(obstacleIndex).maxCornerM);
        intersectionMatrix(timeIndex,obstacleIndex)=hit;
        if hit && isnan(firstBlockingIndex(timeIndex))
            firstBlockingIndex(timeIndex)=obstacleIndex;
        end
    end
end
result.timeSec=analysisTimeSec(:);
result.blocked=any(intersectionMatrix,2);
result.isBlocked=result.blocked;
result.intersectionMatrix=intersectionMatrix;
result.firstBlockingIndex=firstBlockingIndex;
result.blockedByObstacle=any(intersectionMatrix,1).';
result.everBlockedByObstacle=result.blockedByObstacle;
end
