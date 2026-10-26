function [y, tauAudio, info] = renderDiffractionBranches( ...
    x,sourceTime,t,source,receiver,obstacles,d,config,lossFilter)
%RENDERDIFFRACTIONBRANCHES Render distinct ray tracks without delay blending.
% Inputs: source pressure x [Pa], source/receive times [s], trajectories,
% boxes, frame geometry d, config, existing frequency-loss filter callback.
% Outputs: summed pressure y [Pa], single-track emission times [s] (NaN in
% mixtures), and per-track read times/weights/validity plus numerical audit.
%
% Same-topology frames retain linear delay interpolation. At a topology
% change, each endpoint ray is continued with frozen contact points and its
% own retarded-time solution. Pressure weights are linear in the geometry
% interval (partition of unity), NOT interpolation of two delay values.
% Each track is frequency-filtered separately before pressure mixing.
% Frozen contacts and crossfade are rendering approximations, not UTD or a
% physical shadow-boundary solution. AABB penetration is rejected during
% continuation; weights are normalized over valid rays only. No speed clamp.
% Original visibility is retained: this does NOT fix direct/reflection gates.
t=t(:);n=numel(t);at=d.analysisTimeSec(:);active=d.active(:);
mask=logical(interp1(at,double(active),t,'previous',0));
% The legacy selector can change topology during fixed-point iteration.
% Its last stored length may then have been evaluated at the PREVIOUS tau.
% Resolve the final chosen polyline independently before interpolating it.
% Preserve the caller's raw arrays; record every correction explicitly.
anchorCorrection=zeros(size(at));anchorInvalid=false(size(at));anchorResidual=zeros(size(at));
for j=find(active).'
    [newTau,newDistance,newDelta,ok,res]=acoustics.solveFixedDiffractionPath( ...
        source,receiver,at(j),d.pathPointsM{j},obstacles,config);
    anchorCorrection(j)=newTau-d.emissionTimeSec(j);anchorInvalid(j)=~ok;anchorResidual(j)=res;
    d.emissionTimeSec(j)=newTau;d.directDistanceM(j)=newDistance;d.excessPathM(j)=newDelta;
end
active=active&~anchorInvalid;
% A last-iteration topology oscillation can leave the raw chosen ray inside
% another box at its corrected emission time. Try ONLY the adjacent valid
% frame rays (one geometry interval), with a fresh causal/visibility solve.
% This is local path tracking, not transmission through an invalid obstacle.
% Unrecoverable anchors remain inactive and are exposed as coverage FAILs.
originalInvalid=anchorInvalid;recoveredFrom=zeros(size(at));
originalGood=active;originalPoints=d.pathPointsM;originalKeys=d.pathKey;
for j=find(originalInvalid).'
    candidates=[j-1,j+1];candidates=candidates(candidates>=1 & candidates<=numel(at));
    for h=candidates
        if ~originalGood(h),continue;end
        [newTau,newDistance,newDelta,ok,res]=acoustics.solveFixedDiffractionPath( ...
            source,receiver,at(j),originalPoints{h},obstacles,config);
        if ~ok,continue;end
        anchorCorrection(j)=anchorCorrection(j)+newTau-d.emissionTimeSec(j);
        d.emissionTimeSec(j)=newTau;d.directDistanceM(j)=newDistance;d.excessPathM(j)=newDelta;
        d.pathPointsM{j}=originalPoints{h};d.pathKey(j)=originalKeys(h);
        active(j)=true;anchorInvalid(j)=false;anchorResidual(j)=res;recoveredFrom(j)=h;
        break;
    end
end
key=d.pathKey(:);edge=[true;key(2:end)~=key(1:end-1)|~active(1:end-1)];
starts=find(active & edge);ends=zeros(size(starts));
for k=1:numel(starts)
    j=starts(k);while j<numel(at)&&active(j+1)&&key(j+1)==key(j),j=j+1;end
    ends(k)=j;
end
y=zeros(n,1);weightSum=zeros(n,1);tauAudio=nan(n,1);rayCount=zeros(n,1);
branches=struct([]);badTotal=0;testedTotal=0;minRate=Inf;maxRate=-Inf;
context=config.diffraction.windowLengthSamples/config.audio.processingSampleRateHz;
for k=1:numel(starts)
    a=starts(k);b=ends(k);left=at(a);right=at(b);
    if a>1 && active(a-1),left=at(a-1);end
    if b<numel(at),right=at(b+1);end
    ix=find(t>=max(t(1),left-context)&t<=min(t(end),right+context));
    q=t(ix);tau=nan(size(q));dist=tau;delta=tau;valid=false(size(q));res=zeros(size(q));
    middle=q>=at(a)&q<=at(b);
    if b>a
        tau(middle)=interp1(at(a:b),d.emissionTimeSec(a:b),q(middle),'linear');
        dist(middle)=interp1(at(a:b),d.directDistanceM(a:b),q(middle),'linear');
        delta(middle)=interp1(at(a:b),d.excessPathM(a:b),q(middle),'linear');
        valid(middle)=true;
    else
        tau(middle)=d.emissionTimeSec(a);dist(middle)=d.directDistanceM(a);
        delta(middle)=d.excessPathM(a);valid(middle)=true;
    end
    for side=1:2
        if side==1,part=q<at(a);anchor=a;else,part=q>at(b);anchor=b;end
        if any(part)
            [tau(part),dist(part),delta(part),valid(part),res(part)]= ...
                acoustics.solveFixedDiffractionPath(source,receiver,q(part), ...
                d.pathPointsM{anchor},obstacles,config);
        end
    end
    w=double(q>=at(a)&q<=at(b));
    if a>1 && active(a-1)
        part=q>=left&q<at(a);w(part)=(q(part)-left)/(at(a)-left);
    end
    if b<numel(at)
        part=q>at(b)&q<right;
        if active(b+1),w(part)=(right-q(part))/(right-at(b));else,w(part)=1;end
    end
    w=w.*double(valid).*double(mask(ix));
    input=zeros(n,1);da=zeros(n,1);va=false(n,1);
    input(ix)=interp1(sourceTime,x,tau,'linear',0).* ...
        (config.audio.referenceDistanceM./max(dist,config.physics.minimumDistanceM)).*valid;
    input(~isfinite(input))=0;da(ix)=delta;va(ix)=valid;
    filtered=lossFilter(input,da,va);
    y(ix)=y(ix)+w.*filtered(ix);weightSum(ix)=weightSum(ix)+w;
    live=w>0;li=ix(live);tauAudio(li)=tau(live);rayCount(li)=rayCount(li)+1;
    % Audit the actual read trajectory, not a difference across two tracks.
    pair=live(1:end-1)&live(2:end);
    rate=diff(tau)./diff(q);
    st=acoustics.computeTrajectory(source,tau);rt=acoustics.computeTrajectory(receiver,q);
    vs=max(vecnorm(st.velocityMps,2,2));vr=max(vecnorm(rt.velocityMps,2,2));c=config.physics.soundSpeedMps;
    lower=(1-vr/c)/(1+vs/c);upper=(1+vr/c)/(1-vs/c);
    bad=pair&(~isfinite(rate)|rate<lower-.002|rate>upper+.002);
    badTotal=badTotal+nnz(bad);testedTotal=testedTotal+nnz(pair);
    if any(pair),minRate=min(minRate,min(rate(pair)));maxRate=max(maxRate,max(rate(pair)));end
    bi=struct('key',key(a),'firstFrame',a,'lastFrame',b,'sampleIndices',ix, ...
        'timeSec',q,'emissionTimeSec',tau,'weight',w,'valid',valid, ...
        'motionLower',lower,'motionUpper',upper,'outlierPairs',nnz(bad), ...
        'testedPairs',nnz(pair),'maxContinuationResidualSec',max(abs(res)));
    branches=[branches;bi]; %#ok<AGROW>
end
covered=weightSum>0;y(covered)=y(covered)./weightSum(covered);
y(~mask)=0;tauAudio(rayCount~=1)=NaN;
for k=1:numel(branches)
    ix=branches(k).sampleIndices;den=weightSum(ix);live=den>0;
    branches(k).weight(live)=branches(k).weight(live)./den(live);
end
info.method="topology_tracks_independent_delays_linear_pressure_mix";
info.branches=branches;info.branchCount=numel(branches);
info.transitionFrames=find(active(1:end-1)&active(2:end)&key(1:end-1)~=key(2:end));
info.rawWeightSum=weightSum;info.activeRayCount=rayCount;
info.mixtureSamples=nnz(rayCount>1);info.uncoveredActiveSamples=nnz(mask&~covered);
info.testedPairs=testedTotal;info.timeWarpOutlierPairs=badTotal;
if isinf(minRate),minRate=NaN;maxRate=NaN;end
info.minTimeWarp=minRate;info.maxTimeWarp=maxRate;
info.warpAuditMargin=.002; % Unchanged diagnostic tolerance, not a clamp.
info.activeAudio=mask;
info.anchorTimeCorrectionSec=anchorCorrection;
info.anchorInvalidFrames=nnz(anchorInvalid);
info.maxAnchorResidualSec=max(abs(anchorResidual));
info.originalInvalidAnchorFrames=find(originalInvalid);
info.recoveredAnchorFromFrame=recoveredFrom;
info.anchorEmissionTimeSec=d.emissionTimeSec;
info.anchorPathKey=d.pathKey;
info.anchorPathPointsM=d.pathPointsM;
end
