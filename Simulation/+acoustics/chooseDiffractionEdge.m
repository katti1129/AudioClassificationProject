function geometry = chooseDiffractionEdge(sourcePositionM, receiverPositionM, obstacle)
%CHOOSEDIFFRACTIONEDGE Find a shortest finite-box edge-bypass path.
%   GEOMETRY = CHOOSEDIFFRACTIONEDGE(SOURCEPOSITIONM, RECEIVERPOSITIONM,
%   OBSTACLE) searches the top and four vertical faces of a ground-standing
%   axis-aligned box. A candidate path has three legs:
%       Source -> first edge point -> same-face surface leg
%              -> second edge point -> Receiver.
%   Entry and exit points are constrained to exposed face edges, while the
%   first and last legs may touch the box only at their endpoints. This
%   finite-thickness construction replaces the invalid one-point path that
%   would pass through a thick box in a typical blocked geometry.
%
%   Positions and returned distances use [m]. The path is subsequently
%   assigned one path-equivalent, frequency-dependent knife-edge loss; it
%   is not claimed to be an exact two-edge UTD solution.

arguments
    sourcePositionM (1,3) double
    receiverPositionM (1,3) double
    obstacle (1,1) struct
end

mn=obstacle.minCornerM;
mx=obstacle.maxCornerM;
v=[mn(1) mn(2) mn(3); mx(1) mn(2) mn(3); ...
   mx(1) mx(2) mn(3); mn(1) mx(2) mn(3); ...
   mn(1) mn(2) mx(3); mx(1) mn(2) mx(3); ...
   mx(1) mx(2) mx(3); mn(1) mx(2) mx(3)];

% Bottom-face edges are excluded because a ground-standing obstacle cannot
% be bypassed through the ground. Each cell describes one exposed face.
faceNames={"top","x_min","x_max","y_min","y_max"};
faceEdges={ ...
    [5 6; 6 7; 7 8; 8 5], ...
    [4 8; 8 5; 5 1], ...
    [3 7; 7 6; 6 2], ...
    [2 6; 6 5; 5 1], ...
    [3 7; 7 8; 8 4]};

bestLength=Inf;
bestFirst=[NaN NaN NaN];
bestSecond=[NaN NaN NaN];
bestFace=NaN;
bestEntryEdge=NaN;
bestExitEdge=NaN;

for faceIndex=1:numel(faceEdges)
    edges=faceEdges{faceIndex};
    entryVisible=false(size(edges,1),1);
    exitVisible=false(size(edges,1),1);
    for edgeIndex=1:size(edges,1)
        edgeStart=v(edges(edgeIndex,1),:);
        edgeEnd=v(edges(edgeIndex,2),:);
        entryVisible(edgeIndex)=edgePotentiallyVisible(sourcePositionM, ...
            edgeStart,edgeEnd,mn,mx,true);
        exitVisible(edgeIndex)=edgePotentiallyVisible(receiverPositionM, ...
            edgeStart,edgeEnd,mn,mx,true);
    end
    for entryIndex=1:size(edges,1)
        if ~entryVisible(entryIndex), continue; end
        entryStart=v(edges(entryIndex,1),:);
        entryEnd=v(edges(entryIndex,2),:);
        for exitIndex=1:size(edges,1)
            if ~exitVisible(exitIndex), continue; end
            exitStart=v(edges(exitIndex,1),:);
            exitEnd=v(edges(exitIndex,2),:);
            [uEntry,uExit,pathLength]=optimizeEdgePair(sourcePositionM, ...
                receiverPositionM,entryStart,entryEnd,exitStart,exitEnd);
            firstPoint=entryStart+uEntry*(entryEnd-entryStart);
            secondPoint=exitStart+uExit*(exitEnd-exitStart);

            if ~touchesOnlyAtEndpoint(sourcePositionM,firstPoint,mn,mx,true) ...
                    || ~touchesOnlyAtEndpoint(secondPoint,receiverPositionM, ...
                    mn,mx,false)
                continue;
            end
            if pathLength<bestLength
                bestLength=pathLength;
                bestFirst=firstPoint;
                bestSecond=secondPoint;
                bestFace=faceIndex;
                bestEntryEdge=entryIndex;
                bestExitEdge=exitIndex;
            end
        end
    end
end

geometry.valid=isfinite(bestLength);
geometry.pointM=bestFirst;             % Backward-compatible first point.
geometry.secondPointM=bestSecond;
geometry.diffractionPointsM=[bestFirst;bestSecond];
geometry.faceIndex=bestFace;
geometry.entryEdgeIndex=bestEntryEdge;
geometry.exitEdgeIndex=bestExitEdge;

if geometry.valid
    geometry.faceName=faceNames{bestFace};
    geometry.edgeType="finite_AABB_two_edge_surface_path";
    geometry.sourceDistanceM=norm(sourcePositionM-bestFirst);
    geometry.surfaceDistanceM=norm(bestFirst-bestSecond);
    geometry.receiverDistanceM=norm(receiverPositionM-bestSecond);
    geometry.pathLengthM=geometry.sourceDistanceM+geometry.surfaceDistanceM ...
        +geometry.receiverDistanceM;
else
    geometry.faceName="";
    geometry.edgeType="";
    geometry.sourceDistanceM=NaN;
    geometry.surfaceDistanceM=NaN;
    geometry.receiverDistanceM=NaN;
    geometry.pathLengthM=NaN;
end
end

function [bestU,bestV,bestLength]=optimizeEdgePair(source,receiver,a1,b1,a2,b2)
%OPTIMIZEEDGEPAIR Minimize a convex three-leg length over two line segments.
bestU=0.5;
bestV=0.5;
options=optimset('TolX',1e-8,'Display','off');
for iteration=1:6
    previous=[bestU,bestV];
    bestU=minimizeBounded(@(candidate) pathLength(candidate,bestV),options);
    bestV=minimizeBounded(@(candidate) pathLength(bestU,candidate),options);
    if max(abs([bestU,bestV]-previous))<1e-7
        break;
    end
end
bestLength=pathLength(bestU,bestV);

    function value=pathLength(uValue,vValue)
        q1=a1+uValue*(b1-a1);
        q2=a2+vValue*(b2-a2);
        value=norm(source-q1)+norm(q1-q2)+norm(receiver-q2);
    end
end

function visible=edgePotentiallyVisible(observer,edgeStart,edgeEnd,minimum,maximum,boxAtEnd)
%EDGEPOTENTIALLYVISIBLE Cheap broad phase before continuous minimization.
parameters=[0,0.5,1];
visible=false;
for parameter=parameters
    point=edgeStart+parameter*(edgeEnd-edgeStart);
    if boxAtEnd
        clear=touchesOnlyAtEndpoint(observer,point,minimum,maximum,true);
    else
        clear=touchesOnlyAtEndpoint(point,observer,minimum,maximum,false);
    end
    if clear
        visible=true;
        return;
    end
end
end

function location=minimizeBounded(objective,options)
%MINIMIZEBOUNDED Include both endpoints in a scalar bounded minimization.
[interior,interiorValue]=fminbnd(objective,0,1,options);
candidates=[0,interior,1];
values=[objective(0),interiorValue,objective(1)];
[~,index]=min(values);
location=candidates(index);
end

function clear=touchesOnlyAtEndpoint(startPoint,endPoint,minimum,maximum,boxAtEnd)
%TOUCHESONLYATENDPOINT Permit boundary contact but reject box penetration.
[hit,tEnter,tExit]=acoustics.segmentAABB(startPoint,endPoint,minimum,maximum);
if ~hit
    clear=true;
    return;
end
parameterTolerance=1e-7;
if boxAtEnd
    clear=tEnter>=1-parameterTolerance;
else
    clear=tExit<=parameterTolerance;
end
end
