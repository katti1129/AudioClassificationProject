function [tau, distanceM, deltaM, valid, residualSec] = solveFixedDiffractionPath( ...
    source,receiver,t,points,obstacles,config)
%SOLVEFIXEDDIFFRACTIONPATH Retarded time through a frozen broken ray.
% Inputs: trajectories; receive times t [s]; fixed contact points [m]; AABBs.
% Outputs: emission time [s], free-space reference distance/excess length [m],
% valid ray mask, true retarded-time residual [s]. Used only to continue an
% endpoint branch over a geometry-update transition/filter support interval.
% This is a local frozen-contact approximation, not a new diffraction theory.
% Strict penetration of ANY box is rejected; boundary tangency is permitted.
t=t(:);c=config.physics.soundSpeedMps;
r=acoustics.computeTrajectory(receiver,t);
s=acoustics.computeTrajectory(source,t);
surface=sum(vecnorm(diff(points,1,1),2,2));
last=vecnorm(r.positionM-points(end,:),2,2);
tau=t-(vecnorm(s.positionM-points(1,:),2,2)+surface+last)/c;
for k=1:config.solver.maxIterations
    s=acoustics.computeTrajectory(source,tau);
    next=t-(vecnorm(s.positionM-points(1,:),2,2)+surface+last)/c;
    if max(abs(next-tau))<=config.solver.timeToleranceSec,tau=next;break;end
    tau=next;
end
s=acoustics.computeTrajectory(source,tau);
lengthM=vecnorm(s.positionM-points(1,:),2,2)+surface+last;
residualSec=tau+lengthM/c-t;
distanceM=vecnorm(r.positionM-s.positionM,2,2);
deltaM=max(lengthM-distanceM,0);
valid=isfinite(tau)&tau<=t&abs(residualSec)<=config.solver.timeToleranceSec;
for k=1:numel(obstacles)
    % Match the existing serial-path strict-interior convention [m].
    mn=obstacles(k).minCornerM+1e-8;mx=obstacles(k).maxCornerM-1e-8;
    if any(mx<=mn),continue;end
    valid=valid & ~interiorHit(s.positionM,points(1,:),mn,mx) ...
        & ~interiorHit(points(end,:),r.positionM,mn,mx);
    for j=1:size(points,1)-1
        if interiorHit(points(j,:),points(j+1,:),mn,mx),valid(:)=false;break;end
    end
end
end

function hit=interiorHit(a,b,mn,mx)
%INTERIORHIT Vectorized slab test for many segments against one strict AABB.
v=b-a;n=size(v,1);lo=zeros(n,1);hi=ones(n,1);miss=false(n,1);
for axis=1:3
    aa=a(:,axis);vv=v(:,axis);parallel=abs(vv)<eps;
    miss=miss | (parallel & (aa<mn(axis)|aa>mx(axis)));
    safe=vv;safe(parallel)=1;
    u=(mn(axis)-aa)./safe;w=(mx(axis)-aa)./safe;
    lower=min(u,w);upper=max(u,w);lower(parallel)=-Inf;upper(parallel)=Inf;
    lo=max(lo,lower);hi=min(hi,upper);
end
hit=~miss & lo<=hi;
end
