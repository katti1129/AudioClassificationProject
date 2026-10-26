function out = totalResponse(g,cfg)
%TOTALRESPONSE Signed sum of GA and BTMS for an infinite rigid wedge.
% Inputs g,cfg: see edgeResponse. Output individual/total IR and H [1/m].
% No gate of diffraction by direct visibility: diffraction exists both sides.
out.edge=btms.edgeResponse(g,cfg);
out.ga=btms.geometricalResponse(g,cfg);
out.t=out.edge.t;
out.direct=out.ga.hDirect; out.reflected=out.ga.hReflected;
out.diffracted=out.edge.h;
out.total=out.direct+out.reflected+out.diffracted;
out.H=out.ga.HDirect+out.ga.HReflected+out.edge.H;
end
