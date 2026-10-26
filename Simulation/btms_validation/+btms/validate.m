function validate(g,cfg)
%VALIDATE Reject unsupported geometries and invalid numerical settings.
% Inputs: g edge-aligned cylindrical geometry; cfg numerical settings.
% Output: none; throws on invalid input. Rigid exterior wedges only.
validateattributes(g.alpha,{'numeric'},{'real','finite','scalar','>',pi,'<=',2*pi});
for name = ["source" "receiver"]
    p = g.(name);
    validateattributes(p,{'numeric'},{'real','finite','vector','numel',3});
    assert(p(1)>0 && p(2)>0 && p(2)<g.alpha,'btms:geometry', ...
        'Points must be off the edge and strictly inside the exterior wedge.');
end
validateattributes(g.edgeLimits,{'numeric'},{'real','vector','numel',2,'nonnan'});
assert(g.edgeLimits(1)<g.edgeLimits(2),'btms:geometry','Edge limits must increase.');
validateattributes(cfg.c,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(cfg.fs,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(cfg.irDuration,{'numeric'},{'real','finite','positive','scalar'});
validateattributes(cfg.quadratureOrder,{'numeric'},{'integer','scalar','>=',4});
validateattributes(cfg.frequencies,{'numeric'},{'real','finite','vector','nonnegative'});
assert(all(cfg.frequencies<cfg.fs/2),'btms:frequency','Frequencies must be below Nyquist.');
end
