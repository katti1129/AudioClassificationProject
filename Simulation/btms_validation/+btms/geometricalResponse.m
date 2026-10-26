function out = geometricalResponse(g,cfg)
%GEOMETRICALRESPONSE Direct/specular GA of an infinite rigid wedge.
% Inputs: geometry/config (see edgeResponse).
% Outputs: separate IR bins and complex transfers [1/m], lengths [m], weights.
% ONLY infinite wedge GA; a finite edge segment does not define a finite wall.
% At a shadow/reflection boundary the corresponding ray has half weight.
btms.validate(g,cfg);
assert(all(isinf(g.edgeLimits)),'btms:finiteGA', ...
    'Infinite-wedge GA cannot be presented as a complete finite-wall field.');
s=g.source; r=g.receiver; alpha=g.alpha;
angle=[s(2)-r(2),s(2)+r(2),2*alpha-s(2)-r(2)];
out.length=sqrt(s(1)^2+r(1)^2-2*s(1)*r(1)*cos(angle)+(s(3)-r(3))^2);
margin=[pi-abs(s(2)-r(2)),pi-s(2)-r(2),s(2)+r(2)-(2*alpha-pi)];
tol=32*eps*max(1,alpha);
out.weight=double(margin>tol)+0.5*double(abs(margin)<=tol);
out.t=(0:ceil(cfg.irDuration*cfg.fs)).'/cfg.fs;
out.hDirect=zeros(size(out.t)); out.hReflected=zeros(size(out.t));
out.HDirect=complex(zeros(1,numel(cfg.frequencies))); out.HReflected=out.HDirect;
out.retained=false(1,3);
for j=1:3
    if out.weight(j)==0, continue; end
    assert(out.length(j)>0,'btms:coincident','Coincident source/receiver unsupported.');
    ix=round(out.length(j)/cfg.c*cfg.fs)+1;
    if ix>numel(out.t), continue; end
    out.retained(j)=true;
    gain=out.weight(j)/out.length(j);
    H=gain*exp(-2i*pi*cfg.frequencies(:).'*out.length(j)/cfg.c);
    if j==1
        out.hDirect(ix)=out.hDirect(ix)+gain; out.HDirect=out.HDirect+H;
    else
        out.hReflected(ix)=out.hReflected(ix)+gain; out.HReflected=out.HReflected+H;
    end
end
end
