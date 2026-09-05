function [intersects, tEnter, tExit] = segmentAABB( ...
    startPointM, endPointM, minCornerM, maxCornerM, toleranceM)
%SEGMENTAABB Test a 3D line segment against an axis-aligned bounding box.
%   [HIT,T0,T1] = SEGMENTAABB(P0,P1,MINIMUM,MAXIMUM,TOLERANCE) uses the
%   exact slab intersection algorithm. P0/P1 and AABB corners use [m]. T0
%   and T1 are unitless segment parameters in [0,1]. Touching the boundary
%   counts as an intersection. TOLERANCEM defaults to 1e-10 m.

arguments
    startPointM (1,3) double
    endPointM (1,3) double
    minCornerM (1,3) double
    maxCornerM (1,3) double
    toleranceM (1,1) double {mustBeNonnegative} = 1e-10
end

minimum=minCornerM-toleranceM;
maximum=maxCornerM+toleranceM;
direction=endPointM-startPointM;
tEnter=0; tExit=1; intersects=true;

for axisIndex=1:3
    if abs(direction(axisIndex))<=eps(max(1,abs(startPointM(axisIndex))))
        if startPointM(axisIndex)<minimum(axisIndex) ...
                || startPointM(axisIndex)>maximum(axisIndex)
            intersects=false; tEnter=NaN; tExit=NaN; return;
        end
    else
        tA=(minimum(axisIndex)-startPointM(axisIndex))/direction(axisIndex);
        tB=(maximum(axisIndex)-startPointM(axisIndex))/direction(axisIndex);
        slabEnter=min(tA,tB); slabExit=max(tA,tB);
        tEnter=max(tEnter,slabEnter); tExit=min(tExit,slabExit);
        if tEnter>tExit
            intersects=false; tEnter=NaN; tExit=NaN; return;
        end
    end
end
end
