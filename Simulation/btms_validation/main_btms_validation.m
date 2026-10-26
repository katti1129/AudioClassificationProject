function result = main_btms_validation(cfg)
%MAIN_BTMS_VALIDATION Run isolated stationary BTMS tests and save CSV/MAT/PNG.
% Input optional cfg from btms_config; output result with checks and paths.
% Does not edit or call the production dataset generator or synthesizer.
root=fileparts(mfilename('fullpath'));
oldPath=path; cleanup=onCleanup(@()path(oldPath));
addpath(root,fullfile(root,'tests'),fullfile(fileparts(root),'tests'));
if nargin<1, cfg=btms_config(); end
btms.validate(cfg.geometry,cfg);
runID=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
outDir=fullfile(cfg.outputDir,['BTMS_' runID]);
assert(~isfolder(outDir),'btms:outputExists','Refusing to overwrite an existing run.');
mkdir(outDir);
fprintf('BTMS stationary validation: %s\n',outDir);
result=run_btms_tests(cfg);
result.runID=runID; result.outputDir=outDir;
writetable(result.checks,fullfile(outDir,'checks.csv'),'Encoding','UTF-8');
writetable(result.boundaryScan,fullfile(outDir,'boundary_scan.csv'),'Encoding','UTF-8');
writetable(result.convergence,fullfile(outDir,'convergence.csv'),'Encoding','UTF-8');
save(fullfile(outDir,'results.mat'),'result','-v7.3');
btms.saveFigures(result,outDir);
% Export readback is a separate small audit; physical FAIL is never suppressed.
names=["checks.csv" "boundary_scan.csv" "convergence.csv"];
expected=[height(result.checks) height(result.boundaryScan) height(result.convergence)];
exportChecks=table();
for j=1:numel(names)
    tab=readtable(fullfile(outDir,names(j)),'VariableNamingRule','preserve');
    exportChecks=[exportChecks; researchtest.check('export',names(j)+" row readback",height(tab),expected(j),0,'rows','Written CSV reopened in MATLAB.')]; %#ok<AGROW>
end
for name=["geometry.png" "boundary_continuity.png" "impulse_response.png" "convergence.png"]
    info=imfinfo(fullfile(outDir,name));
    exportChecks=[exportChecks; researchtest.check('export',name+" readable",double(info.Width>0&&info.Height>0),1,0,'boolean','PNG reopened after saving.')]; %#ok<AGROW>
end
loaded=load(fullfile(outDir,'results.mat'),'result');
exportChecks=[exportChecks; researchtest.check('export','MAT checks readback',height(loaded.result.checks),height(result.checks),0,'rows','Results and configuration retained in MAT.')];
writetable(exportChecks,fullfile(outDir,'export_checks.csv'),'Encoding','UTF-8');
result.exportChecks=exportChecks;
save(fullfile(outDir,'results.mat'),'result','-v7.3');
fprintf('Physical/numerical checks: PASS=%d FAIL=%d INFO=%d NOT_EVALUATED=%d\n', ...
    nnz(result.checks.Status=="PASS"),nnz(result.checks.Status=="FAIL"), ...
    nnz(result.checks.Status=="INFO"),nnz(result.checks.Status=="NOT_EVALUATED"));
fprintf('Export checks: PASS=%d FAIL=%d\n',nnz(exportChecks.Status=="PASS"),nnz(exportChecks.Status=="FAIL"));
if any(result.checks.Status=="FAIL") || any(exportChecks.Status=="FAIL")
    warning('btms:validationFailed','Validation has FAIL rows. Inspect checks.csv; do not use as a validated production model.');
end
end
