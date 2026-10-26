function result = run_btms_tests(cfg)
%RUN_BTMS_TESTS Quantitative stationary-wedge/finite-edge verification.
% Input cfg: btms_config. Output result: checks, boundaryScan, convergence,
% example responses. PASS covers only the stated numerical/model scope.
% Reuses Simulation/tests/+researchtest table helpers, without editing them.
checks=table(); scan=table(); convergence=table();
g=cfg.geometry; g.receiver(2)=2.7;
base=btms.edgeResponse(g,cfg);
ref=btms.referenceInfiniteBTM(g,cfg);
add('reference','BTM time-form relative L1',norm(base.h-ref,1)/norm(ref,1),0,1e-8,'relative', ...
    'Independent time-variable quadrature, same analytical model; not measured ground truth.');
add('reference','No inverse-tanh clamps',base.roundoffClamps,0,0,'count','Roundoff guard must not activate in this case.');
rec=g; rec.source=g.receiver; rec.receiver=g.source;
reverse=btms.edgeResponse(rec,cfg);
add('reciprocity','Exchange source/receiver',norm(base.h-reverse.h,1)/norm(base.h,1),0,1e-10,'relative','Rigid reciprocal medium.');
before=base.t+0.5/cfg.fs<base.onset;
add('causality','Pre-arrival IR',max(abs(base.h(before))),0,1e-13,'1/m','No sample-bin contribution before minimum edge-path arrival.');
first=find(abs(base.h)>1e-14,1);
add('causality','First arrival bin',abs(base.t(first)-base.onset),0,0.5/cfg.fs+1e-12,'s','Area-sampled impulse has at most half-bin onset uncertainty.');
L0=hypot(g.source(1)+g.receiver(1),g.source(3)-g.receiver(3));
add('geometry','Fermat onset length',base.onset*cfg.c,L0,1e-12,'m','Analytical stationary point along infinite edge.');
% Finite segment tests concern the edge contribution, not the wall field.
fg=g; fg.edgeLimits=cfg.finiteEdgeLimits;
finite=btms.edgeResponse(fg,cfg);
left=fg; right=fg; split=0.9;
assert(split>fg.edgeLimits(1)&&split<fg.edgeLimits(2),'Test split must lie in finite segment.');
left.edgeLimits(2)=split; right.edgeLimits(1)=split;
a=btms.edgeResponse(left,cfg); b=btms.edgeResponse(right,cfg);
add('finite_edge','Segment additivity',norm(finite.h-a.h-b.h,1)/norm(finite.h,1),0,1e-8,'relative','Splitting edge does not duplicate or lose contribution.');
after=finite.t-0.5/cfg.fs>finite.lastArrival;
add('finite_edge','No response beyond endpoint support',max(abs(finite.h(after))),0,1e-13,'1/m','Finite edge has finite path-delay support.');
far=g; far.edgeLimits=[2 4]; farResponse=btms.edgeResponse(far,cfg);
expected=(hypot(g.source(1),2-g.source(3))+hypot(g.receiver(1),2-g.receiver(3)))/cfg.c;
add('finite_edge','Apex outside segment onset',farResponse.onset,expected,1e-12,'s','Closest endpoint, not infinite-edge Fermat point.');
wide=g; wide.edgeLimits=[-100 100]; w=btms.edgeResponse(wide,cfg);
add('finite_edge','Long segment vs time-windowed infinite edge',norm(base.h-w.h,1)/norm(base.h,1),0,1e-10,'relative','Segment contains every edge point arriving in retained time window.');
rejected=false;
try
    btms.geometricalResponse(fg,cfg);
catch err
    rejected=strcmp(err.identifier,'btms:finiteGA');
end
add('scope_guard','Reject finite-edge as complete finite-wall field',double(rejected),1,0,'boolean','Prevents silently combining truncated edge with infinite-wall GA.');
% Quadrature convergence both away from and near the shadow boundary.
for near=[false true]
    qg=g;
    if near, qg.receiver(2)=qg.source(2)+pi+1e-4; end
    cc=cfg; cc.quadratureOrder=2*cfg.quadratureOrder; truth=btms.edgeResponse(qg,cc);
    for order=unique([16 32 cfg.quadratureOrder])
        cc.quadratureOrder=order; v=btms.edgeResponse(qg,cc);
        e=max(abs(v.H-truth.H))*L0;
        convergence=[convergence; table("quadrature",double(near),double(order),e, ...
            'VariableNames',{'Study','NearBoundary','Parameter','NormalizedError'})]; %#ok<AGROW>
        if order==cfg.quadratureOrder
            add('quadrature',string(order)+' vs '+string(2*order)+' nodes; near='+string(near),e,0,1e-5,'relative to 1/L0','Complex transfer, maximum over configured frequencies. Lower-order runs remain in convergence.csv.');
        end
    end
end
% Also test numerical resolution near the limiting offsets, not just 1e-4.
for offset=[1e-3 1e-5 1e-6]
    qg=g; qg.receiver(2)=qg.source(2)+pi+offset;
    a=btms.edgeResponse(qg,cfg); cc=cfg; cc.quadratureOrder=2*cfg.quadratureOrder;
    b=btms.edgeResponse(qg,cc);
    add('quadrature','Configured vs doubled order; offset='+string(offset),max(abs(a.H-b.H))*L0,0,1e-5,'relative to 1/L0','Additional near-boundary resolution check.');
end
% Boundary limiting tests; both wedge faces and both direct shadow sides.
% GA-alone is a negative control: it MUST retain the unit ray discontinuity.
for alpha=[3*pi/2 2*pi]
    for mirror=[false true]
        bg=cfg.geometry; bg.alpha=alpha;
        bg.source(2)=pi/6;
        if mirror, bg.source(2)=alpha-pi/6; end
        for kind=["shadow" "reflection"]
            if kind=="shadow"
                if mirror, boundary=bg.source(2)-pi; else, boundary=bg.source(2)+pi; end
            else
                if mirror, boundary=2*alpha-pi-bg.source(2); else, boundary=pi-bg.source(2); end
            end
            label=sprintf('%gdeg_%s_face%d',alpha*180/pi,kind,mirror);
            bg.receiver(2)=boundary;
            center=btms.totalResponse(bg,cfg);
            scale=hypot(bg.source(1)+bg.receiver(1),bg.source(3)-bg.receiver(3));
            jumps=zeros(size(cfg.boundaryOffsets));
            for n=1:numel(cfg.boundaryOffsets)
                epsilon=cfg.boundaryOffsets(n);
                bg.receiver(2)=boundary-epsilon; minus=btms.totalResponse(bg,cfg);
                bg.receiver(2)=boundary+epsilon; plus=btms.totalResponse(bg,cfg);
                jumps(n)=max(abs(plus.H-minus.H))*scale;
                gaJump=max(abs(plus.ga.HDirect+plus.ga.HReflected-minus.ga.HDirect-minus.ga.HReflected))*scale;
                for k=1:numel(cfg.frequencies)
                    scan=[scan; scanRow(label,alpha,boundary,-epsilon,cfg.frequencies(k),minus,k); ...
                        scanRow(label,alpha,boundary,epsilon,cfg.frequencies(k),plus,k)]; %#ok<AGROW>
                end
            end
            for k=1:numel(cfg.frequencies)
                scan=[scan; scanRow(label,alpha,boundary,0,cfg.frequencies(k),center,k)]; %#ok<AGROW>
            end
            add(label,'Total complex boundary jump',jumps(end),0,1e-3,'relative to 1/L0','Both sides at +/-1e-6 rad; maximum over frequencies.');
            add(label,'Boundary exact value vs two-sided mean',max(abs(center.H-(plus.H+minus.H)/2))*scale,0,1e-4,'relative to 1/L0','Half-weight GA and symmetric diffraction limit.');
            add(label,'Boundary jump decreases',double(jumps(end)<0.02*jumps(1)),1,0,'boolean','Offsets reduced from 1e-2 to 1e-6 rad; not a crossfade.');
            add(label,'GA-only negative control',gaJump,1,1e-3,'relative to 1/L0','Without diffraction, the discontinuity must remain detectable.');
            add(label,'IR-bin continuity',norm(plus.total-minus.total,1)*scale,0,1e-3,'relative to 1/L0','Tests signed area-sampled response, not only transfer magnitude.');
        end
    end
end
% Explicit half-ray and physically correct inverse-distance amplitude tests.
gg=cfg.geometry; gg.receiver(2)=gg.source(2)+pi;
ga=btms.geometricalResponse(gg,cfg);
add('GA','Half direct ray on boundary',ga.weight(1),0.5,0,'weight','No ad-hoc boundary mute.');
gg.receiver(2)=pi-gg.source(2); ga=btms.geometricalResponse(gg,cfg);
add('GA','Half reflection on boundary',ga.weight(2),0.5,0,'weight','Rigid reflection coefficient is +1, not an adjustable absorption model.');
gg.receiver(2)=1.5; ga=btms.geometricalResponse(gg,cfg);
add('GA','Direct amplitude 1/R',sum(ga.hDirect),1/ga.length(1),1e-12,'1/m','Free-field normalization, no per-signal normalization.');
% Sampling error is evaluated, not confused with physical discontinuity.
err=zeros(1,2);
for j=1:2
    cc=cfg; cc.fs=cfg.fs*2^(j-1); v=btms.edgeResponse(g,cc);
    discrete=(v.h.'*exp(-2i*pi*v.t*cfg.frequencies)).';
    err(j)=max(abs(discrete(:).'-v.H))*L0;
    convergence=[convergence; table("IR_sampling",0,cc.fs,err(j), ...
        'VariableNames',{'Study','NearBoundary','Parameter','NormalizedError'})]; %#ok<AGROW>
end
add('sampling','IR discretization improves at doubled fs',double(err(2)<err(1)),1,0,'boolean','FFT-style transfer vs exact-delay quadrature; quantization is not hidden.');
% Time tail diagnostics: finite window is not an infinite-time exact IR.
cc=cfg; cc.irDuration=2*cfg.irDuration; longer=btms.edgeResponse(g,cc);
tail=norm(longer.h(numel(base.h)+1:end),1)*L0;
checks=[checks; researchtest.row('window','Omitted tail over next window','INFO',tail,NaN,NaN,'relative L1', ...
    'Windowed infinite-edge response; later tail beyond this next window is not bounded here.')];
checks=[checks; researchtest.row('scope','Complete finite wall incl. all edges','NOT_EVALUATED',NaN,NaN,NaN,'', ...
    'Finite single-edge contribution is implemented; closed finite-wall field and higher-order interactions are not.'); ...
    researchtest.row('scope','Moving source/receiver and Doppler','NOT_EVALUATED',NaN,NaN,NaN,'','Position scans are independent stationary fields, not a time-varying renderer.'); ...
    researchtest.row('scope','Ambulance WAV and Dataset_002 artifacts','NOT_EVALUATED',NaN,NaN,NaN,'','Existing simulator is untouched. This suite cannot certify that its clicks or overlapping audio are fixed.'); ...
    researchtest.row('scope','Independent measured/FEM/BEM reference','NOT_EVALUATED',NaN,NaN,NaN,'','Time-form BTM comparison tests implementation, not experimental validity.')];
result.checks=checks; result.boundaryScan=scan; result.convergence=convergence;
result.example=base; result.finiteExample=finite; result.reference=ref;
result.exampleGeometry=g; result.config=cfg;

    function add(caseName,name,value,expected,tolerance,unit,detail)
        checks=[checks; researchtest.check(caseName,name,value,expected,tolerance,unit,detail)];
    end
end

function t=scanRow(label,alpha,boundary,offset,f,response,k)
%SCANROW One signed complex-frequency sample for reproducible CSV plotting.
d=response.ga.HDirect(k); r=response.ga.HReflected(k); e=response.edge.H(k); h=response.H(k);
t=table(string(label),alpha,boundary,offset,f,real(d),imag(d),real(r),imag(r),real(e),imag(e),real(h),imag(h), ...
    'VariableNames',{'Case','WedgeAngle_rad','BoundaryAngle_rad','Offset_rad','Frequency_Hz', ...
    'DirectReal_per_m','DirectImag_per_m','ReflectedReal_per_m','ReflectedImag_per_m', ...
    'DiffractedReal_per_m','DiffractedImag_per_m','TotalReal_per_m','TotalImag_per_m'});
end
