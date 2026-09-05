function [visible, blockedByObstacle] = computeBrokenPathVisibility( ...
    sourcePositionsM, interactionPointsM, receiverPositionsM, obstacles, ...
    exemptObstacleIndex)
%COMPUTEBROKENPATHVISIBILITY Test two reflection legs against 3D AABBs.
%   [VISIBLE,BLOCKEDBYOBSTACLE] = COMPUTEBROKENPATHVISIBILITY(S,Q,R,
%   OBSTACLES,EXEMPTINDEX) tests S->Q and Q->R at every row using exact
%   segment-AABB slab intersections. Coordinates use [m]. VISIBLE is one
%   logical value per row; BLOCKEDBYOBSTACLE is time-by-obstacle.
%
%   EXEMPTINDEX is used when Q lies on the reflecting obstacle itself. For
%   that box, contact only at the end of S->Q and start of Q->R is allowed;
%   penetration before/after the interaction point is still rejected.

arguments
    sourcePositionsM (:,3) double
    interactionPointsM (:,3) double
    receiverPositionsM (:,3) double
    obstacles
    exemptObstacleIndex (1,1) double = NaN
end

nTimes=size(sourcePositionsM,1);
nObstacles=numel(obstacles);
if size(interactionPointsM,1)~=nTimes || size(receiverPositionsM,1)~=nTimes
    error('acoustics:BrokenPathSize', ...
        'Source, interaction, and Receiver arrays must have equal rows.');
end

blockedByObstacle=false(nTimes,nObstacles);
finiteGeometry=all(isfinite(sourcePositionsM),2) ...
    & all(isfinite(interactionPointsM),2) ...
    & all(isfinite(receiverPositionsM),2);

for timeIndex=find(finiteGeometry).'
    source=sourcePositionsM(timeIndex,:);
    point=interactionPointsM(timeIndex,:);
    receiver=receiverPositionsM(timeIndex,:);
    for obstacleIndex=1:nObstacles
        obstacle=obstacles(obstacleIndex);
        [firstHit,firstEnter,~]=acoustics.segmentAABB(source,point, ...
            obstacle.minCornerM,obstacle.maxCornerM);
        [secondHit,~,secondExit]=acoustics.segmentAABB(point,receiver, ...
            obstacle.minCornerM,obstacle.maxCornerM);
        if obstacleIndex==exemptObstacleIndex
            parameterTolerance=1e-7;
            firstBlocked=firstHit && firstEnter<1-parameterTolerance;
            secondBlocked=secondHit && secondExit>parameterTolerance;
        else
            firstBlocked=firstHit;
            secondBlocked=secondHit;
        end
        blockedByObstacle(timeIndex,obstacleIndex)=firstBlocked || secondBlocked;
    end
end

visible=finiteGeometry & ~any(blockedByObstacle,2);
end
