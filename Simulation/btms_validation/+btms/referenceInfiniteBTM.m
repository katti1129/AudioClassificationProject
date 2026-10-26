function h = referenceInfiniteBTM(g,cfg)
%REFERENCEINFINITEBTM Independent time-form BTM quadrature, infinite edge.
% Inputs g,cfg; output integrated IR h [1/m], same bins as edgeResponse.
% Svensson et al. (1999), JASA 106, 2331-2344, DOI 10.1121/1.428071.
% h(t)=-c*nu*sum(beta)/(2*pi*rS*rR*sinh(eta)), t>t0.
% q=sqrt(t-t0) removes onset square-root singularity. Reference is for angles
% AWAY from boundaries; it does not reuse the line-integral u/v transform.
btms.validate(g,cfg);
assert(all(isinf(g.edgeLimits)),'btms:reference','Reference requires infinite edge.');
s=g.source; r=g.receiver; nu=pi/g.alpha;
phi=[pi+s(2)+r(2),pi+s(2)-r(2),pi-s(2)+r(2),pi-s(2)-r(2)];
a=mod(nu*phi+pi,2*pi)-pi;
assert(all(abs(a)>1e-3),'btms:referenceBoundary','Use reference away from boundaries.');
ab=s(1)*r(1); t0=hypot(s(1)+r(1),s(3)-r(3))/cfg.c;
t=(0:ceil(cfg.irDuration*cfg.fs)).'/cfg.fs;
ql=sqrt(max(t-0.5/cfg.fs-t0,0)); qh=sqrt(max(t+0.5/cfg.fs-t0,0));
[x,w]=btms.gaussRule(max(64,2*cfg.quadratureOrder));
q=(qh+ql)/2+(qh-ql)/2.*x;
v=cfg.c*q.*sqrt(2*t0+q.^2)/(2*sqrt(ab)); eta=2*asinh(v);
beta=zeros(size(q));
for j=1:4
    beta=beta+sin(a(j))./(2*sinh(nu*eta/2).^2+2*sin(a(j)/2)^2);
end
integrand=-nu*beta./(pi*sqrt(ab)*sqrt(2*t0+q.^2).*sqrt(1+v.^2));
h=sum((qh-ql)/2.*w.*integrand,2);
end
