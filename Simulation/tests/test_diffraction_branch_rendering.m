function checks = test_diffraction_branch_rendering()
%TEST_DIFFRACTION_BRANCH_RENDERING Independent read-time/pressure regressions.
% Output: Case/Check/Status/Measured/Expected/Tolerance/Unit/Detail table.
% All times [s], positions [m], pressure [Pa]. No production files are saved.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'tests'));
c=default_config();fs=16000;c.audio.processingSampleRateHz=fs;
t=(0:1/fs:.5-1/fs)';x=sin(2*pi*800*t);
s=struct('initialPositionM',[0 0 1.5],'initialVelocityMps',[0 0 0],'accelerationMps2',[0 0 0]);
r=s;r.initialPositionM=[20 0 1.5];
at=[0;.2;.21;t(end)];points={[10 2 1.5];[10 2 1.5];[10 12 1.5];[10 12 1.5]};
lengths=cellfun(@(p)norm(s.initialPositionM-p)+norm(r.initialPositionM-p),points);
d=struct('analysisTimeSec',at,'active',true(4,1),'pathKey',["A";"A";"B";"B"], ...
    'emissionTimeSec',at-lengths/c.physics.soundSpeedMps, ...
    'directDistanceM',20*ones(4,1),'excessPathM',lengths-20,'pathPointsM',{points});
[y,~,a]=acoustics.renderDiffractionBranches(x,t,t,s,r,struct([]),d,c,@(v,~,~)v);
checks=researchtest.check('branch_unit','independent_read_rates',a.timeWarpOutlierPairs,0,0,'pairs','Static rays must each have rate 1, despite a delay jump');
checks=[checks;researchtest.check('branch_unit','two_tracks',a.branchCount,2,0,'tracks','Two identities, not one interpolated delay')];
% Independent expected waveform: interpolate source on EACH physical delay,
% then linear pressure crossfade over the supplied 10 ms geometry interval.
alpha=max(0,min(1,(t-.2)/.01));
ya=interp1(t,x,t-lengths(1)/343,'linear',0)/20;
yb=interp1(t,x,t-lengths(3)/343,'linear',0)/20;
expected=(1-alpha).*ya+alpha.*yb;
checks=[checks;researchtest.check('branch_unit','independent_pressure_mix',max(abs(y-expected)),0,1e-10,'Pa','Independent two-delay pressure reference, identity loss filter')];
legacy=interp1(t,x,interp1(at,d.emissionTimeSec,t),'linear',0)/20;
ix=t>.2&t<.21;
checks=[checks;researchtest.check('branch_unit','legacy_artifact_exercised',double(max(abs(legacy(ix)-expected(ix)))>1e-3),1,0,'boolean','Negative control must differ; the defect is exercised')];
checks=[checks;researchtest.check('branch_unit','no_uncovered_samples',a.uncoveredActiveSamples,0,0,'samples','No missing valid branch')];
% Deliberately label the discontinuity as one ray. The audit MUST FAIL it;
% no slope clipping, threshold relaxation, or blind omission is permitted.
d.pathKey(:)="WRONG_SINGLE_ID";
[~,~,bad]=acoustics.renderDiffractionBranches(x,t,t,s,r,struct([]),d,c,@(v,~,~)v);
checks=[checks;researchtest.check('branch_unit','negative_control_detected',double(bad.timeWarpOutlierPairs>0),1,0,'boolean','Misidentified same-ray delay jump is still detected')];
% Reproduce a stale final solver iterate: raw tau does not match its points.
d.pathKey=["A";"A";"B";"B"];d.emissionTimeSec(2)=d.emissionTimeSec(2)+.001;
[fixed,~,audit]=acoustics.renderDiffractionBranches(x,t,t,s,r,struct([]),d,c,@(v,~,~)v);
checks=[checks;researchtest.check('branch_unit','stale_anchor_corrected',max(abs(fixed-expected)),0,1e-10,'Pa','Final points re-solved; stale 1 ms emission time must not reach the reader')];
checks=[checks;researchtest.check('branch_unit','stale_anchor_recorded',max(abs(audit.anchorTimeCorrectionSec)),.001,1e-10,'s','Correction retained in diagnostics')];
% One invalid raw anchor between valid rays is recovered only if a neighbor
% is geometrically valid at that receive time. No invalid ray is transmitted.
d.pathPointsM={points{1};points{3};points{1};points{1}};d.pathKey=["A";"B";"A";"A"];
for j=1:4,L=2*norm(d.pathPointsM{j}-[0 0 1.5]);d.emissionTimeSec(j)=at(j)-L/343;end
blocker=researchtest.box(1,[5 6],2,2,4);
[fixed,~,audit]=acoustics.renderDiffractionBranches(x,t,t,s,r,blocker,d,c,@(v,~,~)v);
checks=[checks;researchtest.check('branch_unit','invalid_anchor_recovered',nnz(audit.recoveredAnchorFromFrame),1,0,'frames','Only adjacent valid contact path may replace invalid selection')];
checks=[checks;researchtest.check('branch_unit','recovered_waveform',max(abs(fixed-ya)),0,1e-10,'Pa','Recovered ray is the unobstructed A path, independently calculated')];
% Geometric continuation with acceleration and both endpoints moving.
s.initialVelocityMps=[12 0 0];s.accelerationMps2=[2 0 0];
r.initialVelocityMps=[-3 0 0];r.accelerationMps2=[-.5 0 0];
[tau,~,~,valid,res]=acoustics.solveFixedDiffractionPath(s,r,t,[10 2 1.5],struct([]),c);
checks=[checks;researchtest.check('branch_unit','retarded_residual',max(abs(res)),0,c.solver.timeToleranceSec,'s','Recomputed geometric residual, not update difference')];
checks=[checks;researchtest.check('branch_unit','moving_ray_valid',nnz(~valid),0,0,'samples','Both endpoints accelerate; all causal and converged')];
st=acoustics.computeTrajectory(s,tau);rt=acoustics.computeTrajectory(r,t);
u=[10 2 1.5]-st.positionM;u=u./vecnorm(u,2,2);
v=rt.positionM-[10 2 1.5];v=v./vecnorm(v,2,2);
factor=(1-sum(v.*rt.velocityMps,2)/343)./(1-sum(u.*st.velocityMps,2)/343);
checks=[checks;researchtest.check('branch_unit','moving_ray_doppler',max(abs(diff(tau)./diff(t)-(factor(1:end-1)+factor(2:end))/2)),0,1e-6,'ratio','Finite difference vs independent endpoint Doppler formula')];
% An obstructed continuation must not contribute a phantom transmission.
box=researchtest.box(1,[5 1],2,2,4);
[~,~,~,valid]=acoustics.solveFixedDiffractionPath(s,r,t,[10 2 1.5],box,c);
checks=[checks;researchtest.check('branch_unit','penetrating_ray_rejected',nnz(valid),0,0,'samples','AABB crossing is rejected before mixing')];
end
