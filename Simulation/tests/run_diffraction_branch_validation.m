function report = run_diffraction_branch_validation(outputParent,seeds)
%RUN_DIFFRACTION_BRANCH_VALIDATION Regression + separate before/after outputs.
% Inputs: optional output parent folder and seed vector (default 1:10).
% Outputs: report; checks.csv, before_after.csv, branch_metrics.csv, MAT/WAV.
% Existing Dataset_001 is READ ONLY. New files use a unique run directory.
% Raw selected-path jumps remain recorded, distinct from rendered ray rates.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root,fullfile(root,'tests'));
if nargin<1,outputParent=fullfile(root,'data','output','diffraction_branch_validation');end
if nargin<2,seeds=1:10;end
if ~isfolder(outputParent),mkdir(outputParent);end
runDir=tempname(outputParent);mkdir(runDir);fprintf('BRANCH_VALIDATION_OUTPUT=%s\n',runDir);
checks=test_diffraction_branch_rendering();comparison=table();metrics=table();
writetable(checks,fullfile(runDir,'checks.csv'));
old=run_validation_tests();writetable(old,fullfile(runDir,'legacy_unit.csv'));
for j=1:height(old),checks=[checks;researchtest.check('legacy_unit',old.Test(j),double(old.Passed(j)),1,0,'boolean',old.Details(j))];end %#ok<AGROW>
old=run_scenario_tests();writetable(old,fullfile(runDir,'legacy_scenarios.csv'));
for j=1:height(old),checks=[checks;researchtest.check('legacy_scenario',old.Scenario(j),double(old.Passed(j)),1,0,'boolean',old.Details(j))];end %#ok<AGROW>
o=research_validation_config();o.runDir=runDir;o.saveFigures=false;
checks=[checks;test_rendered_signal_physics(o)];
writetable(checks,fullfile(runDir,'checks.csv'));
manifest=readtable(fullfile(root,'datasets','Dataset_001','dataset_manifest.csv'),'TextType','string');
for seed=seeds(:).'
    label="SEED"+seed;fprintf('Regenerating %s in new output directory\n',label);
    try
        row=find(manifest.Seed==seed,1);files=dir(fullfile(manifest.ResultFolder(row),'**','*physical_results.mat'));
        assert(numel(files)==1);loaded=load(fullfile(files(1).folder,files(1).name),'results');before=loaded.results;
        c=before.config;c.simulation.id="BRANCH_"+label;c=outputConfig(c,runDir);
        after=acoustics.runSimulation(c);
        checks=[checks;verifyCase(after,before,label)]; %#ok<AGROW>
        [line,bm]=caseMetrics(after,before,label);comparison=[comparison;line];metrics=[metrics;bm]; %#ok<AGROW>
        save(fullfile(runDir,label+"_comparison.mat"),'line','bm');
    catch ex
        checks=[checks;researchtest.row(label,'execution','FAIL',NaN,NaN,NaN,'',getReport(ex,'extended','hyperlinks','off'))]; %#ok<AGROW>
    end
    writeProgress();
end
% Use the previously recorded failing real-WAV scene, not a new easier scene.
% Its unchanged exact configuration is loaded from the prior physical MAT.
baseline=fullfile(fileparts(mfilename('fullpath')),'branch_validation_baseline.mat');
% A caller may provide the baseline path in the environment to avoid a
% machine-specific path embedded in this reusable test.
custom=getenv('ACOUSTICS_BRANCH_BASELINE');if ~isempty(custom),baseline=custom;end
if isfile(baseline)
    try
        loaded=load(baseline,'results');before=loaded.results;
        c=before.config;c.simulation.id="BRANCH_DIFFRACTION_SWITCH";c=outputConfig(c,runDir);
        after=acoustics.runSimulation(c);label="diffraction_switch";
        checks=[checks;verifyCase(after,before,label)];
        [line,bm]=caseMetrics(after,before,label);comparison=[comparison;line];metrics=[metrics;bm];
    catch ex
        checks=[checks;researchtest.row('diffraction_switch','execution','FAIL',NaN,NaN,NaN,'',getReport(ex,'extended','hyperlinks','off'))];
    end
else
    checks=[checks;researchtest.row('diffraction_switch','baseline_available','NOT_EVALUATED',NaN,NaN,NaN,'','Set ACOUSTICS_BRANCH_BASELINE to prior physical-results MAT')];
end
writeProgress();
report=struct('checks',checks,'comparison',comparison,'branchMetrics',metrics,'runDir',runDir);
save(fullfile(runDir,'report.mat'),'report','-v7.3');
fprintf('PASS=%d FAIL=%d NOT_EVALUATED=%d\n',nnz(checks.Status=="PASS"),nnz(checks.Status=="FAIL"),nnz(checks.Status=="NOT_EVALUATED"));
disp(comparison);
    function writeProgress()
        writetable(checks,fullfile(runDir,'checks.csv'));
        if width(comparison)>0,writetable(comparison,fullfile(runDir,'before_after.csv'));end
        if width(metrics)>0,writetable(metrics,fullfile(runDir,'branch_metrics.csv'));end
    end
end

function c=outputConfig(c,runDir)
%OUTPUTCONFIG Change only output handling, leaving acoustic inputs unchanged.
c.output.rootDir=fullfile(runDir,'regenerated');c.output.overwrite=false;
c.output.writeMat=true;c.output.writeComponentWav=true;
c.output.writeExcel=false;c.output.writeFigures=false;
end

function rows=verifyCase(after,before,label)
%VERIFYCASE Validate actual renderer and preserve unaffected components.
d=after.diffraction;a=d.rendering;
rows=researchtest.check(label,'rendered_time_warp_outliers',a.timeWarpOutlierPairs,0,0,'pairs','Actual independently rendered tracks; raw selection jumps separately retained');
count=0;weights=zeros(size(d.activeAudio));invalidWeight=0;
for k=1:numel(a.branches)
    b=a.branches(k);live=b.weight>0;pair=live(1:end-1)&live(2:end);
    rate=diff(b.emissionTimeSec)./diff(b.timeSec);
    count=count+nnz(pair&(~isfinite(rate)|rate<b.motionLower-.002|rate>b.motionUpper+.002));
    weights(b.sampleIndices)=weights(b.sampleIndices)+b.weight;
    invalidWeight=invalidWeight+nnz(live&~b.valid);
end
rows=[rows;researchtest.check(label,'independent_rate_audit',count,0,0,'pairs','Recomputed from saved per-track read times, not the summary counter')];
rows=[rows;researchtest.check(label,'weight_partition',max(abs(weights-double(d.activeAudio))),0,1e-12,'ratio','Weights sum to one on active samples and zero elsewhere')];
rows=[rows;researchtest.check(label,'invalid_ray_contribution',invalidWeight,0,0,'samples','No nonzero weight on geometrically invalid continuation')];
rows=[rows;researchtest.check(label,'anchor_validity',a.anchorInvalidFrames,0,0,'frames','Final selected polylines checked at independently solved emission time')];
rows=[rows;researchtest.check(label,'anchor_retarded_residual',a.maxAnchorResidualSec,0,after.config.solver.timeToleranceSec,'s','True residual at final selected points')];
rows=[rows;researchtest.check(label,'uncovered_active_samples',a.uncoveredActiveSamples,0,0,'samples','No unintended silence from missing continued rays')];
rows=[rows;researchtest.check(label,'direct_unchanged',max(abs(after.signals.directPa-before.signals.directPa)),0,1e-10,'Pa','Same configuration, only diffraction changed')];
rows=[rows;researchtest.check(label,'reflection_unchanged',max(abs(after.signals.reflectedPa-before.signals.reflectedPa)),0,1e-10,'Pa','Same configuration, only diffraction changed')];
rows=[rows;researchtest.check(label,'selected_geometry_unchanged',double(isequaln(d.pathLengthM,before.diffraction.pathLengthM)&&isequaln(d.emissionTimeSec,before.diffraction.emissionTimeSec)),1,0,'boolean','No geometry or raw delay edits to manufacture a pass')];
rows=[rows;researchtest.check(label,'finite_output',nnz(~isfinite(after.signals.finalPa)),0,0,'samples','Finite mixed pressure')];
rows=[rows;researchtest.check(label,'component_sum',max(abs(after.signals.finalPa-after.signals.directPa-after.signals.reflectedPa-after.signals.diffractedPa)),0,1e-9,'Pa','Direct + reflected + diffracted')];
[y,fs]=audioread(after.output.audioFiles.final);
rows=[rows;researchtest.check(label,'wav_sample_rate',fs,after.sampleRateHz,0,'Hz','New output file')];
rows=[rows;researchtest.check(label,'wav_pressure_readback',max(abs(y*after.output.paPerFullScale-after.signals.finalPa)),0,2e-6*after.output.paPerFullScale,'Pa','Original shared scale, no peak normalization')];
rows=[rows;researchtest.check(label,'wav_clipping',nnz(abs(y)>=1),0,0,'samples','New output file')];
if ~after.config.diffraction.enabled
    rows.Status(rows.Check=="rendered_time_warp_outliers"|rows.Check=="independent_rate_audit")="NOT_EVALUATED";
    rows.Detail(rows.Check=="rendered_time_warp_outliers"|rows.Check=="independent_rate_audit")="Diffraction disabled, not counted as a physical pass";
    rows=[rows;researchtest.check(label,'disabled_output_unchanged',max(abs(after.signals.finalPa-before.signals.finalPa)),0,1e-10,'Pa','Diffraction OFF: complete output unchanged')];
elseif a.testedPairs==0
    rows=[rows;researchtest.row(label,'rendered_coverage','NOT_EVALUATED',0,NaN,NaN,'pairs','No consecutive audible branch samples')];
end
end

function [line,metrics]=caseMetrics(after,before,label)
%CASEMETRICS Report raw frame jumps and actual sample read-rate independently.
a=after.diffraction.rendering;d=before.diffraction;t=d.analysisTimeSec;
q=diff(d.emissionTimeSec)./diff(t);pair=d.active(1:end-1)&d.active(2:end);
c=before.config.physics.soundSpeedMps;
vs=max(vecnorm(before.trajectories.source.velocityMps,2,2));vr=max(vecnorm(before.trajectories.receiver.velocityMps,2,2));
lo=(1-vr/c)/(1+vs/c);hi=(1+vr/c)/(1-vs/c);
bad=nnz(pair&(~isfinite(q)|q<lo-.002|q>hi+.002));
line=table(string(label),before.config.diffraction.enabled,bad,a.timeWarpOutlierPairs, ...
    a.testedPairs,a.branchCount,numel(a.transitionFrames),a.mixtureSamples,a.uncoveredActiveSamples, ...
    a.minTimeWarp,a.maxTimeWarp,rms(before.signals.diffractedPa),rms(after.signals.diffractedPa), ...
    max(abs(diff(before.signals.diffractedPa))),max(abs(diff(after.signals.diffractedPa))), ...
    string(after.output.audioFiles.final), ...
    'VariableNames',{'Case','DiffractionEnabled','BeforeRawOutlierFrames','AfterRenderedOutlierPairs', ...
    'RenderedTestedPairs','BranchCount','TopologyChanges','MixtureSamples','UncoveredActiveSamples', ...
    'MinRenderedTimeWarp','MaxRenderedTimeWarp','BeforeDiffractedRMSPa','AfterDiffractedRMSPa', ...
    'BeforeMaxSampleDeltaPa','AfterMaxSampleDeltaPa','OutputWAV'});
metrics=table();
for k=1:numel(a.branches)
    b=a.branches(k);
    metrics=[metrics;table(string(label),k,b.key,b.firstFrame,b.lastFrame,b.testedPairs,b.outlierPairs, ...
        b.motionLower,b.motionUpper,b.maxContinuationResidualSec, ...
        'VariableNames',{'Case','Branch','Key','FirstFrame','LastFrame','TestedPairs','OutlierPairs', ...
        'MotionLower','MotionUpper','MaxContinuationResidualSec'})]; %#ok<AGROW>
end
end
