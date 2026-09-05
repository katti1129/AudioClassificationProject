function obstacles = generateObstacles(obstacleConfig, sourcePositionsM, receiverPositionsM)
%GENERATEOBSTACLES Create reproducible static axis-aligned 3D box obstacles.
%   OBSTACLES = GENERATEOBSTACLES(CONFIG, SOURCEPOSITIONSM,
%   RECEIVERPOSITIONSM) uses CONFIG.seed with MATLAB's twister generator.
%   Each box rests on z=0 and stores ID, center [m], width/depth/height [m],
%   material, pressure reflection coefficient, and AABB corners [m]. Boxes
%   are rejected if an expanded AABB overlaps any sampled Source/Receiver
%   trajectory point. Optional box-box overlap rejection is also supported.

arguments
    obstacleConfig (1,1) struct
    sourcePositionsM (:,3) double
    receiverPositionsM (:,3) double
end

previousRandomState = rng;
restoreRandomState = onCleanup(@() rng(previousRandomState));
rng(obstacleConfig.seed, 'twister');

n = obstacleConfig.count;
template = struct('id',"",'centerM',[0 0 0],'widthM',0,'depthM',0, ...
    'heightM',0,'minCornerM',[0 0 0],'maxCornerM',[0 0 0], ...
    'material',"",'pressureReflectionCoefficient',0);
obstacles = repmat(template, n, 1);
placed = 0;
attempts = 0;

while placed < n && attempts < obstacleConfig.maximumPlacementAttempts
    attempts = attempts + 1;
    widthM = uniformRange(obstacleConfig.widthRangeM);
    depthM = uniformRange(obstacleConfig.depthRangeM);
    heightM = uniformRange(obstacleConfig.heightRangeM);
    lower = obstacleConfig.boundsMinM;
    upper = obstacleConfig.boundsMaxM;
    if upper(1)-lower(1) < widthM || upper(2)-lower(2) < depthM
        error('acoustics:ObstacleLargerThanBounds', ...
            'Obstacle dimension range does not fit inside placement bounds.');
    end
    centerX = lower(1)+widthM/2 + rand*(upper(1)-lower(1)-widthM);
    centerY = lower(2)+depthM/2 + rand*(upper(2)-lower(2)-depthM);
    centerM = [centerX,centerY,heightM/2];
    minCornerM = centerM-[widthM/2,depthM/2,heightM/2];
    maxCornerM = centerM+[widthM/2,depthM/2,heightM/2];

    clearance = obstacleConfig.trajectoryClearanceM;
    expandedMinimum = minCornerM-clearance;
    expandedMaximum = maxCornerM+clearance;
    if any(pointsInsideBox(sourcePositionsM,expandedMinimum,expandedMaximum)) ...
            || any(pointsInsideBox(receiverPositionsM,expandedMinimum,expandedMaximum))
        continue;
    end

    if obstacleConfig.avoidObstacleOverlap && placed > 0
        overlaps = false;
        for j=1:placed
            overlaps = overlaps || boxesOverlap(minCornerM,maxCornerM, ...
                obstacles(j).minCornerM,obstacles(j).maxCornerM);
        end
        if overlaps, continue; end
    end

    materialIndex = randi(numel(obstacleConfig.materials));
    material = obstacleConfig.materials(materialIndex);
    placed = placed+1;
    obstacles(placed).id = "OBS_"+compose('%03d',placed);
    obstacles(placed).centerM = centerM;
    obstacles(placed).widthM = widthM;
    obstacles(placed).depthM = depthM;
    obstacles(placed).heightM = heightM;
    obstacles(placed).minCornerM = minCornerM;
    obstacles(placed).maxCornerM = maxCornerM;
    obstacles(placed).material = string(material.name);
    obstacles(placed).pressureReflectionCoefficient = ...
        material.pressureReflectionCoefficient;
end

if placed < n
    error('acoustics:ObstaclePlacementFailed', ...
        ['Placed only %d of %d obstacles after %d attempts. Increase bounds, ' ...
         'reduce clearance/count, or allow obstacle overlap.'], ...
        placed,n,attempts);
end
end

function value = uniformRange(range)
value=range(1)+rand*(range(2)-range(1));
end

function inside = pointsInsideBox(points,minimum,maximum)
inside=all(points>=minimum & points<=maximum,2);
end

function overlap = boxesOverlap(minimumA,maximumA,minimumB,maximumB)
overlap=all(maximumA>=minimumB & maximumB>=minimumA);
end
