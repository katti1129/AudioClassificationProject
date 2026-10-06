function tests = test_output_paths()
%TEST_OUTPUT_PATHS Verify flat audio, safe collision policies and config persistence.
tests=functiontests(localfunctions);
end
function test_separation(tc)
root=tempname; mkdir(root);
p=pipeline.create_output_paths(root,'ambulance_TEST');
verifyEqual(tc,p.wavFile,fullfile(root,'audio','ambulance_TEST.wav'));
verifyEqual(tc,p.excelDir,fullfile(root,'simulation_results','ambulance_TEST','excel'));
verifyError(tc,@()pipeline.create_output_paths(root,'../outside'),'pipeline:UnsafeName');
end
function test_collisionPolicies(tc)
root=tempname; mkdir(root);
p=pipeline.create_output_paths(root,'test');
mkdir(p.audioDir); mkdir(p.resultDir);
audiowrite(p.wavFile,zeros(100,1),16000);
[q,skip]=pipeline.resolve_collision(root,'test','Skip');
verifyTrue(tc,skip); verifyEqual(tc,q.name,"test");
[q,skip]=pipeline.resolve_collision(root,'test','Rename');
verifyFalse(tc,skip); verifyEqual(tc,q.name,"test_REP02");
mkdir(q.resultDir);
[q,~,archive]=pipeline.resolve_collision(root,'test','Overwrite');
verifyEqual(tc,q.name,"test");
verifyTrue(tc,isfile(fullfile(archive,'test.wav')));
verifyTrue(tc,isfolder(fullfile(archive,'test')));
verifyFalse(tc,isfile(p.wavFile));
end
function test_roundTrip(tc)
root=tempname; mkdir(root);
c=default_config(); rows=pipeline.default_conditions(3,c);
rows.CPA_m=[10;20;50]; rows.Seed=[4;4;6];
o=pipeline.default_options(); o.datasetName='RoundTrip';
o.progressFcn=@(~)disp('not serialized');
file=fullfile(root,'dataset_config.mat');
pipeline.save_dataset_config(file,rows,c,o);
[loaded,base,opts]=pipeline.load_dataset_config(file);
verifyEqual(tc,loaded,rows); verifyEqual(tc,base,c);
verifyEmpty(tc,opts.progressFcn);
verifyEqual(tc,opts.datasetName,'RoundTrip');
end
