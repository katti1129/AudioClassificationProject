function checks = analyze_saved_dataset(o)
%ANALYZE_SAVED_DATASET Read existing SEED1:10, never rerun or write the dataset.
% Input: options with datasetDir/runDir. Output: diagnostic check table.
% Per-case gate events, time-warp details and manifest snapshots are saved
% only below the new validation output directory.
checks=table();manifest=fullfile(o.datasetDir,'dataset_manifest.csv');
if ~isfile(manifest)
    checks=researchtest.row('saved_dataset','availability','NOT_EVALUATED',NaN,NaN,NaN,'','Manifest missing: '+string(manifest));return;
end
m=readtable(manifest,'TextType','string');m=m(ismember(m.Seed,1:10),:);m=sortrows(m,'Seed');
dest=fullfile(o.runDir,'saved_dataset');mkdir(dest);writetable(m,fullfile(dest,'manifest_snapshot.csv'));
for seed=1:10
    if ~any(m.Seed==seed)
        checks=[checks;researchtest.row("SEED"+seed,'availability','NOT_EVALUATED',NaN,NaN,NaN,'','Seed missing from manifest')]; %#ok<AGROW>
    end
end
for k=1:height(m)
    label="SEED"+m.Seed(k)+"_ROW"+k;fprintf('Diagnosing %s\n',label);
    try
        if m.Status(k)~="SUCCESS",error('validation:SavedStatus','Saved row was not successful');end
        files=dir(fullfile(m.ResultFolder(k),'**','*physical_results.mat'));
        if numel(files)~=1,error('validation:SavedMAT','Expected exactly one physical_results MAT');end
        loaded=load(fullfile(files(1).folder,files(1).name),'results');r=loaded.results;
        [rows,detail]=measure_signal_and_path_quality(r,o,label);
        [audio,fs]=audioread(m.WAVPath(k));
        rows=[rows;researchtest.check(label,'wav_sample_rate',fs,r.sampleRateHz,0,'Hz','Saved WAV versus MAT'); ...
            researchtest.check(label,'wav_clipped_samples',nnz(abs(audio)>=1),0,0,'samples','Digital full scale'); ...
            researchtest.check(label,'wav_length',size(audio,1),numel(r.timeSec),0,'samples','Saved WAV versus MAT')];
        if isvector(audio)&&numel(audio)==numel(r.timeSec)
            scale=r.output.paPerFullScale;
            rows=[rows;researchtest.check(label,'wav_pressure_readback', ...
                max(abs(double(audio(:))*scale-r.signals.finalPa)),0,2e-6*scale,'Pa','Allows single-precision WAV rounding; does not normalize')];
        end
        folder=fullfile(dest,char(label));mkdir(folder);
        writetable(detail.events,fullfile(folder,'gate_events.csv'));
        if width(detail.warp)>0,writetable(detail.warp,fullfile(folder,'diffraction_time_warp.csv'));end
        save(fullfile(folder,'diagnostics.mat'),'detail');
        checks=[checks;rows]; %#ok<AGROW>
    catch ex
        checks=[checks;researchtest.row(label,'saved_data_analysis','NOT_EVALUATED',NaN,NaN,NaN,'',getReport(ex,'basic','hyperlinks','off'))]; %#ok<AGROW>
    end
end
end
