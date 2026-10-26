function out = edgeResponse(g,cfg)
%EDGERESPONSE First-order BTMS rigid-wedge finite/infinite edge contribution.
% Inputs: g.alpha [rad], source/receiver [r m,theta rad,z m], edgeLimits [m];
% cfg.c [m/s], fs [Hz], irDuration [s], quadratureOrder, frequencies [Hz].
% Outputs: h integrated IR bins [1/m], H complex transfer [1/m], t [s],
% frequencies [Hz], onset [s], lastArrival [s], retainedUntil [s].
% Convention: free-field h(t)=delta(t-R/c)/R. Convolve h WITHOUT /fs.
% Calamia & Svensson (2007), DOI 10.1155/2007/63560, equations (2)-(5).
% No magnitude-only loss, smoothing, crossfade, or empirical coefficient.
% H integrates exp(-i*omega*L/c) at quadrature nodes; it is not FFT(h).
% Finite edge response alone is NOT the solution for a complete finite wall.
btms.validate(g,cfg);
s = g.source; r = g.receiver;
rs = s(1); rr = r(1); nu = pi/g.alpha;
L0 = hypot(rs+rr,s(3)-r(3));
zA = (rr*s(3)+rs*r(3))/(rs+rr);
zMin = min(max(zA,g.edgeLimits(1)),g.edgeLimits(2));
pathLength = @(z) hypot(rs,z-s(3))+hypot(rr,z-r(3));
out.onset = pathLength(zMin)/cfg.c;
out.lastArrival = max(pathLength(g.edgeLimits))/cfg.c;
out.t = (0:ceil(cfg.irDuration*cfg.fs)).'/cfg.fs;
out.h = zeros(size(out.t));
out.H = complex(zeros(1,numel(cfg.frequencies)));
out.frequencies = cfg.frequencies(:).';
out.retainedUntil = out.t(end)+0.5/cfg.fs;
out.roundoffClamps = 0;
% u=asinh((z-zS)/rS)+asinh((z-zR)/rR), monotonic along the edge.
% eta=abs(u), dz/(m*l)=du/L, L^2=L0^2+4*rS*rR*sinh(u/2)^2.
uEdge = asinh((g.edgeLimits-s(3))/rs)+asinh((g.edgeLimits-r(3))/rr);
tLo = max(0,out.t-0.5/cfg.fs); tHi = out.t+0.5/cfg.fs;
toU = @(t) 2*asinh(sqrt(max((cfg.c*t).^2-L0^2,0))/(2*sqrt(rs*rr)));
uLo = toU(tLo); uHi = toU(tHi);
phi = [pi+s(2)+r(2),pi+s(2)-r(2),pi-s(2)+r(2),pi-s(2)-r(2)];
[x,w] = btms.gaussRule(cfg.quadratureOrder);
for side = [-1 1]
    if side==1, lo=uLo; hi=uHi; else, lo=-uHi; hi=-uLo; end
    lo=max(lo,uEdge(1)); hi=min(hi,uEdge(2));
    idx=find(hi>lo & tHi>L0/cfg.c);
    if isempty(idx), continue; end
    for j=1:4
        a=mod(nu*phi(j)+pi,2*pi)-pi;
        % At a=0 use symmetric angular limit of this term; GA uses 1/2.
        % This machine-roundoff convention is NOT an angular crossfade.
        if abs(a)<32*eps || abs(abs(a)-pi)<32*eps, continue; end
        kappa=abs(tan(a/2)); sigma=sign(tan(a/2));
        % v=atan(tanh(nu*u/2)/kappa) removes the boundary-peaked kernel.
        % beta*du=(2*sigma/nu)*dv, so prefactor becomes -sigma/(2*pi).
        vl=atan(tanh(nu*lo(idx)/2)/kappa);
        vh=atan(tanh(nu*hi(idx)/2)/kappa);
        half=(vh-vl)/2; v=(vh+vl)/2+half.*x;
        q=kappa*tan(v);
        out.roundoffClamps=out.roundoffClamps+nnz(abs(q)>=1);
        q=max(-1+eps,min(1-eps,q)); % Guard inverse-tanh roundoff only.
        u=(2/nu)*atanh(q);
        L=sqrt(L0^2+4*rs*rr*sinh(u/2).^2);
        A=(-sigma/(2*pi))*half.*w./L;
        out.h(idx)=out.h(idx)+sum(A,2);
        for k=1:numel(out.frequencies)
            out.H(k)=out.H(k)+sum(A.*exp(-2i*pi*out.frequencies(k)*L/cfg.c),'all');
        end
    end
end
end
