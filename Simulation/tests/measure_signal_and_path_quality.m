function [checks, detail] = measure_signal_and_path_quality(r,o,label)
%MEASURE_SIGNAL_AND_PATH_QUALITY Read-only waveform/path diagnostics.
% Inputs: saved RESULTS, options, case label. Output: check rows and detail.
% Geometry [m], time [s], signals [Pa]. Binary gate amplitudes below are
% diagnostic estimates reconstructed at OUTPUT rate, not the actual final
% WAV sample jump or an auditory click score. They expose hard-mask risks.
% Missing fields are NOT_EVALUATED, not silent PASS. No geometry is re-solved.
t=r.timeSec(:);fs=r.sampleRateHz;sig=r.signals;
y=[sig.directPa sig.reflectedPa sig.diffractedPa sig.finalPa];
checks=researchtest.check(label,'finite_samples',nnz(~isfinite(y)),0,0,'samples','All four stored pressure components');
checks=[checks;researchtest.check(label,'component_sum', ...
    max(abs(sig.finalPa-sig.directPa-sig.reflectedPa-sig.diffractedPa)),0,1e-9,'Pa','Stored component consistency')];
detail=struct();detail.events=table('Size',[0 6], ...
    'VariableTypes',{'string','double','double','double','double','string'}, ...
    'VariableNames',{'Path','TimeSec','MaskBefore','MaskAfter','EstimatedGatePa','Kind'});
detail.warp=table();detail.obstacleSetChanges=0;detail.maxDelaySec=0;
detail.componentRMSPa=sqrt(mean(y.^2,1));
detail.maxAdjacentSampleDifferencePa=max(abs(diff(y)),[],1);
detail.maxConcurrentObstacleReflections=0;
detail.maxExtraReflectionDelaySec=NaN;
detail.losTransitions=0;detail.groundTransitions=0;detail.faceTransitions=0;
detail.directGatePa=zeros(size(t));
try
    p=r.paths.direct;
    mask=~logical(interp1(r.obstruction.timeSec,double(r.obstruction.blocked),t,'previous','extrap'));
    base=interp1(r.audio.sourceTimeSec,r.audio.inputPa,p.emissionTimeSec,'linear',0) ...
        .*r.config.audio.referenceDistanceM./max(p.distanceM,r.config.physics.minimumDistanceM);
    detail.directGatePa=base.*[0;diff(double(mask))];
    detail.events=[detail.events;gateEvents('direct',t,mask,base,'LOS')];
    detail.losTransitions=nnz(diff(mask));
    detail.maxDelaySec=max(t-p.emissionTimeSec);
    checks=[checks;gateCheck(label,'direct_gate_risk',detail.directGatePa,o)];
catch ex
    checks=[checks;missing(label,'direct_gate_risk',ex.message)];
end
concurrent=zeros(size(t));extra=[];reflectionGate=zeros(size(t));
try
    groups={r.paths.reflections,r.paths.obstacleReflections};
    for group=1:2
        paths=groups{group};
        for k=1:numel(paths)
            p=paths(k);pt=p.observationTimeSec;
            tau=interp1(pt,p.emissionTimeSec,t,'linear','extrap');
            dist=interp1(pt,p.distanceM,t,'linear','extrap');
            valid=logical(interp1(pt,double(p.valid),t,'previous','extrap'));
            base=interp1(r.audio.sourceTimeSec,r.audio.inputPa,tau,'linear',0) ...
                .*r.config.audio.referenceDistanceM./max(dist,r.config.physics.minimumDistanceM) ...
                .*p.pressureReflectionCoefficient;
            g=base.*[0;diff(double(valid))];g(~isfinite(g))=0;
            reflectionGate=reflectionGate+g;
            detail.events=[detail.events;gateEvents(string(p.id),t,valid,base,'reflection')];
            if group==1,detail.groundTransitions=detail.groundTransitions+nnz(diff(valid));
            else,detail.faceTransitions=detail.faceTransitions+nnz(diff(valid));end
            live=valid & tau>=0 & tau<r.audio.inputDurationSec;
            if any(valid),detail.maxDelaySec=max(detail.maxDelaySec,max(t(valid)-tau(valid)));end
            if group==2
                concurrent=concurrent+live;
                extra=[extra;r.paths.direct.emissionTimeSec(live)-tau(live)]; %#ok<AGROW>
            end
        end
    end
    detail.maxConcurrentObstacleReflections=max(concurrent);
    if ~isempty(extra),detail.maxExtraReflectionDelaySec=max(extra);end
    checks=[checks;gateCheck(label,'reflection_gate_risk',reflectionGate,o)];
catch ex
    checks=[checks;missing(label,'reflection_gate_risk',ex.message)];
end
try
    d=r.diffraction;dt=d.analysisTimeSec(:);active=d.active(:);
    if ~r.config.diffraction.enabled || ~any(active)
        checks=[checks;missing(label,'diffraction_time_warp','Diffraction disabled or no active path')];
    else
        pair=active(1:end-1)&active(2:end);
        rate=diff(d.emissionTimeSec)./diff(dt);
        vs=max(vecnorm(r.trajectories.source.velocityMps,2,2));
        vr=max(vecnorm(r.trajectories.receiver.velocityMps,2,2));
        c=r.config.physics.soundSpeedMps;
        lower=(1-vr/c)/(1+vs/c);upper=(1+vr/c)/(1-vs/c);
        bad=pair & (~isfinite(rate) | rate<lower-o.warpTolerance | rate>upper+o.warpTolerance);
        changed=any(diff(double(d.usedObstacleMask),1,1)~=0,2)&pair;
        detail.obstacleSetChanges=nnz(changed);
        detail.warp=table(dt(1:end-1),dt(2:end),rate,pair,changed,bad, ...
            'VariableNames',{'StartSec','EndSec','TimeWarp','BothActive','ObstacleSetChanged','OutsideMotionBounds'});
        if ~any(pair)
            checks=[checks;missing(label,'diffraction_time_warp','No consecutive active frames')];
        else
            checks=[checks;researchtest.check(label,'diffraction_time_warp',nnz(bad),0,0,'frames', ...
                sprintf('Smooth-path motion bounds %.6f to %.6f, margin %.6f; branch blending requires separate treatment',lower,upper,o.warpTolerance))];
        end
        if isfield(d,'converged')
            checks=[checks;researchtest.check(label,'diffraction_solver',nnz(~d.converged),0,0,'frames','Retarded-time convergence flags')];
        end
        detail.maxDelaySec=max(detail.maxDelaySec,max(dt(active)-d.emissionTimeSec(active)));
        mask=logical(interp1(dt,double(active),t,'previous','extrap'));
        % Record measured adjacent-sample change at gate boundaries, not a
        % reconstructed pre-WOLA signal or proof of an audible discontinuity.
        ix=find(diff(mask)~=0)+1;
        for k=ix(:)'
            detail.events=[detail.events;{ "diffraction",t(k),double(mask(k-1)),double(mask(k)), ...
                sig.diffractedPa(k)-sig.diffractedPa(k-1),"output_delta_at_mask_boundary"}]; %#ok<AGROW>
        end
        if isempty(ix),value=0;else,value=max(abs(sig.diffractedPa(ix)-sig.diffractedPa(ix-1)));end
        checks=[checks;gateCheck(label,'diffraction_boundary_review',value,o)];
    end
catch ex
    checks=[checks;missing(label,'diffraction_time_warp',ex.message)];
end
detail.reflectionGatePa=reflectionGate;
detail.timeSec=t;detail.sampleRateHz=fs;
end

function e = gateEvents(name,t,mask,base,kind)
%GATEEVENTS Report binary mask transitions with estimated amplitude [Pa].
ix=find(diff(mask)~=0)+1;n=numel(ix);
e=table(repmat(string(name),n,1),t(ix),double(mask(ix-1)),double(mask(ix)), ...
    base(ix).*(double(mask(ix))-double(mask(ix-1))),repmat(string(kind),n,1), ...
    'VariableNames',{'Path','TimeSec','MaskBefore','MaskAfter','EstimatedGatePa','Kind'});
end
function c = gateCheck(label,name,g,o)
%GATECHECK Warn on nonzero boundary term; not an acoustic audibility test.
v=max(abs(g));if isempty(v),v=0;end
status="PASS";if ~isfinite(v)||v>o.gateNumericalFloorPa,status="WARN";end
c=researchtest.row(label,name,status,v,0,o.gateNumericalFloorPa,'Pa', ...
    'Diagnostic boundary metric only; a nonzero sample difference alone does not prove a click');
end
function c = missing(label,name,message)
%MISSING Explicitly represent unavailable/inapplicable analysis.
c=researchtest.row(label,name,'NOT_EVALUATED',NaN,NaN,NaN,'',message);
end
