function geometry = chooseMultipleObstacleDiffractionPath( ...
    sourcePositionM,receiverPositionM,obstacles,blockingIndices)
%CHOOSEMULTIPLEOBSTACLEDIFFRACTIONPATH Build a clear serial-barrier path.
%   GEOMETRY = CHOOSEMULTIPLEOBSTACLEDIFFRACTIONPATH(S,R,OBSTACLES,INDICES)
%   constructs a path in the vertical plane through the direct horizontal
%   bearing. For each directly intersected AABB, its LOS entry/exit
%   parameters are lifted to the box top. A recursive taut-string (upper
%   convex majorant) selects the minimum polyline that does not pass below
%   any of those finite-width top constraints. Coordinates and distances
%   use [m].
%
%   This supplies a physical delay path when serial boxes defeat every
%   single-box bypass. Its downstream magnitude is deliberately labelled a
%   path-equivalent single-knife-edge approximation; this routine itself is
%   not Deygout, Bullington, or UTD.

arguments
    sourcePositionM (1,3) double
    receiverPositionM (1,3) double
    obstacles
    blockingIndices (:,1) double
end

directVector=receiverPositionM-sourcePositionM;
directDistanceM=norm(directVector);
geometry=emptyGeometry();
if directDistanceM<=eps || isempty(blockingIndices)
    geometry.failureReason="degenerate_or_empty";
    return;
end

uValues=[0;1];
points=[sourcePositionM;receiverPositionM];
owners=[NaN;NaN];
for listIndex=1:numel(blockingIndices)
    obstacleIndex=blockingIndices(listIndex);
    obstacle=obstacles(obstacleIndex);
    [hit,tEnter,tExit]=acoustics.segmentAABB(sourcePositionM,receiverPositionM, ...
        obstacle.minCornerM,obstacle.maxCornerM,0);
    if ~hit, continue; end
    parameters=max(0,min(1,[tEnter;tExit]));
    for parameterIndex=1:2
        u=parameters(parameterIndex);
        point=sourcePositionM+u*directVector;
        point(3)=obstacle.maxCornerM(3);
        uValues(end+1,1)=u; %#ok<AGROW>
        points(end+1,:)=point; %#ok<AGROW>
        owners(end+1,1)=obstacleIndex; %#ok<AGROW>
    end
end

[uValues,order]=sort(uValues);
points=points(order,:);
owners=owners(order);
[uValues,points,owners]=mergeEqualParameters(uValues,points,owners);
if numel(uValues)<=2
    geometry.failureReason="no_top_constraints";
    return;
end

selected=tautStringIndices(uValues,points(:,3));
selected=selected(selected~=1 & selected~=numel(uValues));
if isempty(selected)
    geometry.failureReason="no_taut_points";
    return;
end
diffractionPointsM=points(selected,:);
polyline=[sourcePositionM;diffractionPointsM;receiverPositionM];
if polylinePassesInterior(polyline,obstacles)
    geometry.failureReason="polyline_intersects_AABB_interior";
    return;
end

legLengths=sqrt(sum(diff(polyline,1,1).^2,2));
usedOwners=unique(owners(selected));
usedOwners=usedOwners(isfinite(usedOwners));
directLineZ=sourcePositionM(3)+uValues(selected) ...
    *(receiverPositionM(3)-sourcePositionM(3));
[~,principalLocal]=max(points(selected,3)-directLineZ);
principalObstacleIndex=owners(selected(principalLocal));
if ~isfinite(principalObstacleIndex) && ~isempty(usedOwners)
    principalObstacleIndex=usedOwners(1);
end

geometry.valid=true;
geometry.pointM=diffractionPointsM(1,:);
geometry.secondPointM=diffractionPointsM(end,:);
geometry.diffractionPointsM=diffractionPointsM;
geometry.sourceDistanceM=legLengths(1);
geometry.surfaceDistanceM=sum(legLengths(2:end-1));
geometry.receiverDistanceM=legLengths(end);
geometry.pathLengthM=sum(legLengths);
geometry.faceName="vertical_top_multi_AABB";
geometry.edgeType="serial_AABB_vertical_taut_path";
geometry.obstacleIndex=principalObstacleIndex;
geometry.obstacleIndices=usedOwners(:).';
geometry.multiplePathApproximation=true;
geometry.failureReason="";
end

function [uOut,pointsOut,ownersOut]=mergeEqualParameters(u,points,owners)
%MERGEEQUALPARAMETERS Retain the tallest top constraint at each position.
tolerance=1e-10;
uOut=zeros(size(u));
pointsOut=zeros(size(points));
ownersOut=nan(size(owners));
count=0;
index=1;
while index<=numel(u)
    group=index;
    while group(end)<numel(u) && abs(u(group(end)+1)-u(index))<=tolerance
        group(end+1)=group(end)+1; %#ok<AGROW>
    end
    [~,highest]=max(points(group,3));
    chosen=group(highest);
    count=count+1;
    uOut(count)=u(chosen);
    pointsOut(count,:)=points(chosen,:);
    ownersOut(count)=owners(chosen);
    index=group(end)+1;
end
uOut=uOut(1:count);
pointsOut=pointsOut(1:count,:);
ownersOut=ownersOut(1:count);
end

function selected=tautStringIndices(u,z)
%TAUTSTRINGINDICES Recursively form the shortest upper majorant polyline.
selected=[1;numel(u)];
stack=[1,numel(u)];
toleranceM=1e-9;
while ~isempty(stack)
    first=stack(end,1);
    last=stack(end,2);
    stack(end,:)=[];
    candidates=(first+1:last-1).';
    if isempty(candidates), continue; end
    fraction=(u(candidates)-u(first))/(u(last)-u(first));
    lineZ=z(first)+fraction*(z(last)-z(first));
    [maximumClearance,localIndex]=max(z(candidates)-lineZ);
    if maximumClearance>toleranceM
        principal=candidates(localIndex);
        selected(end+1,1)=principal; %#ok<AGROW>
        stack(end+1,:)=[first,principal]; %#ok<AGROW>
        stack(end+1,:)=[principal,last]; %#ok<AGROW>
    end
end
selected=sort(unique(selected));
end

function passes=polylinePassesInterior(polyline,obstacles)
%POLYLINEPASSESINTERIOR Reject strict AABB penetration but allow tangency.
passes=false;
toleranceM=1e-8;
for legIndex=1:size(polyline,1)-1
    for obstacleIndex=1:numel(obstacles)
        minimum=obstacles(obstacleIndex).minCornerM+toleranceM;
        maximum=obstacles(obstacleIndex).maxCornerM-toleranceM;
        if any(maximum<=minimum), continue; end
        if acoustics.segmentAABB(polyline(legIndex,:),polyline(legIndex+1,:), ...
                minimum,maximum,0)
            passes=true;
            return;
        end
    end
end
end

function geometry=emptyGeometry()
%EMPTYGEOMETRY Return the common invalid-path schema.
geometry.valid=false;
geometry.pointM=[NaN NaN NaN];
geometry.secondPointM=[NaN NaN NaN];
geometry.diffractionPointsM=nan(0,3);
geometry.sourceDistanceM=NaN;
geometry.surfaceDistanceM=NaN;
geometry.receiverDistanceM=NaN;
geometry.pathLengthM=NaN;
geometry.faceName="";
geometry.edgeType="";
geometry.obstacleIndex=NaN;
geometry.obstacleIndices=zeros(1,0);
geometry.multiplePathApproximation=false;
geometry.failureReason="uninitialized";
end
