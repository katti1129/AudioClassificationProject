function export_research_validation(report)
%EXPORT_RESEARCH_VALIDATION Save summary CSV/MAT and a human-readable report.
% Input: report struct with checks/options/runDir. Output: unique run files.
% Status counts are not an assertion that physical validation is complete.
dest=report.runDir;t=report.checks;
writetable(t,fullfile(dest,'summary.csv'));save(fullfile(dest,'report.mat'),'report','-v7.3');
fid=fopen(fullfile(dest,'report.md'),'w','n','UTF-8');assert(fid>=0);clean=onCleanup(@()fclose(fid));
fprintf(fid,'# Research validation report\n\n');
fprintf(fid,'Output: `%s`\n\n',dest);
fprintf(fid,'PASS: %d; FAIL: %d; WARN: %d; NOT_EVALUATED: %d\n\n', ...
    nnz(t.Status=="PASS"),nnz(t.Status=="FAIL"),nnz(t.Status=="WARN"),nnz(t.Status=="NOT_EVALUATED"));
fprintf(fid,['Simulator and Dataset_001 were not modified by this suite. Saved dataset rows were diagnosed, not regenerated.\n\n' ...
    'Synthetic tests measure generated signals against analytic targets. Real WAV scenes use the entire input without looping. ' ...
    'FAIL includes violated numerical requirements or missing intended scene events. WARN denotes boundary risks, not proven audible clicks. ' ...
    'NOT_EVALUATED is never a pass. Knife-edge tests validate the implemented approximation, not exact box diffraction or UTD. ' ...
    'No experimental ground truth was supplied: real-world accuracy is NOT_EVALUATED.\n\n' ...
    'All figures and audio are per-case under ambulance/. Original and output pressure scales are preserved. ' ...
    'Gate estimates are at the output sample rate and are not equivalent to the exact processing-rate gate diagnostic used previously.\n\n']);
fprintf(fid,'|Case|Check|Status|Measured|Expected|Tolerance|Unit|\n|---|---|---|---:|---:|---:|---|\n');
for k=1:height(t)
    fprintf(fid,'|%s|%s|%s|%.8g|%.8g|%.8g|%s|\n',t.Case(k),t.Check(k),t.Status(k),t.Measured(k),t.Expected(k),t.Tolerance(k),t.Unit(k));
end
fprintf(fid,'\n## Details for non-passing checks\n\n');
for k=find(t.Status~="PASS")'
    fprintf(fid,'### %s / %s — %s\n\n%s\n\n',t.Case(k),t.Check(k),t.Status(k),t.Detail(k));
end
end
