function report = run_research_validation(options)
%RUN_RESEARCH_VALIDATION Diagnose saved results and run independent checks.
% Input: optional research_validation_config struct. Output: report struct.
% Does not modify simulator code or regenerate/overwrite Dataset_001.
% Results go into a unique directory. FAIL/WARN remain visible in summary;
% they do not stop other suites. Execution exceptions are recorded as FAIL.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,fullfile(root,'tests'));
if nargin==0,options=research_validation_config();end
if ~isfolder(options.outputParent),mkdir(options.outputParent);end
runDir=tempname(options.outputParent); mkdir(runDir);
options.runDir=runDir;
save(fullfile(runDir,'validation_settings.mat'),'options');
% Capture hashes so a report can be associated with a precise implementation.
files=[dir(fullfile(root,'+acoustics','*.m'));dir(fullfile(root,'tests','*.m')); ...
    dir(fullfile(root,'tests','+researchtest','*.m'));dir(fullfile(root,'default_config.m')); ...
    dir(options.inputWav)];
inventory=table();
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    fid=fopen(path,'rb'); closer=onCleanup(@()fclose(fid)); bytes=fread(fid,Inf,'*uint8');clear closer;
    md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
    hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
    inventory=[inventory;table(string(path),string(hash),'VariableNames',{'Path','SHA256'})]; %#ok<AGROW>
end
writetable(inventory,fullfile(runDir,'code_inventory.csv'));
report=struct('options',options,'checks',table(),'runDir',runDir);
suites={@analyze_saved_dataset,@test_rendered_signal_physics,@test_ambulance_transitions};
enabled=[options.runSavedDataset options.runPhysics options.runAmbulance];
for k=1:numel(suites)
    if ~enabled(k),continue;end
    name=func2str(suites{k});fprintf('\nStarting %s\n',name);
    try
        rows=suites{k}(options);
    catch ex
        rows=researchtest.row(name,'execution',"FAIL",NaN,NaN,NaN,"", ...
            getReport(ex,'extended','hyperlinks','off'));
    end
    report.checks=[report.checks;rows];
    writetable(report.checks,fullfile(runDir,'summary.csv'));
end
export_research_validation(report);
disp(report.checks(:,{'Case','Check','Status'}));
fprintf('Validation output: %s\n',runDir);
end
