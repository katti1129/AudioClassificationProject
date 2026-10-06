function tests = test_dataset_pipeline()
%TEST_DATASET_PIPELINE Real WAV batch, failure continuation and artifact checks.
tests=functiontests(localfunctions);
end
function setupOnce(tc)
project=fileparts(fileparts(mfilename('fullpath')));
parent=fullfile(project,'datasets');
if ~isfolder(parent), mkdir(parent); end
[~,uniquePart]=fileparts(tempname(parent));
o=pipeline.default_options();
o.datasetName=['Validation_',uniquePart(end-7:end)];
o.writeFigures=true; o.writeMat=true;
c=default_config();
c.simulation.durationSec=.25;
c.audio.internalOversampleFactor=1;
c.simulation.geometryTimeStepSec=.05;
c.source.initialPositionM=[-1 0 1.5];
c.receiver.initialPositionM=[1 10 1.2];
rows=pipeline.default_conditions(3,c);
rows.Obstacle(:)=false; rows.Reflection(:)=false;
rows.InputWAV(2)=string(fullfile(project,'data','input','DOES_NOT_EXIST.wav'));
rows.Reflection(3)=true; rows.Obstacle(3)=true; rows.ObstacleCount(3)=2;
rows.Profile(3)="constant_acceleration"; rows.SourceAccelerationMps2(3)=1;
rows.ReceiverVelocityKmh(3)=4;
[manifest,attempts]=pipeline.run_batch(rows,c,o);
tc.TestData=struct('config',c,'rows',rows,'options',o, ...
    'manifest',manifest,'attempts',attempts,'root',fullfile(o.datasetParent,o.datasetName));
fprintf('PIPELINE_VALIDATION_DATASET=%s\n',tc.TestData.root);
end
function test_continueAfterFailure(tc)
m=tc.TestData.manifest; a=tc.TestData.attempts;
verifyEqual(tc,a.Status,["SUCCESS";"FAILED";"SUCCESS"]);
verifyEqual(tc,height(m),3);
verifyNotEmpty(tc,a.ErrorMessage(2));
verifyFalse(tc,isfile(a.WAVPath(2)));
verifyEqual(tc,numel(dir(fullfile(tc.TestData.root,'audio','*.wav'))),2);
verifyEqual(tc,numel(dir(fullfile(tc.TestData.root,'simulation_results','**','*.wav'))),0);
verifyTrue(tc,isfile(fullfile(tc.TestData.root,'dataset_manifest.xlsx')));
t=readtable(fullfile(tc.TestData.root,'dataset_manifest.xlsx'),'Sheet','Manifest','TextType','string');
verifyEqual(tc,t.Status,m.Status);
end
function test_artifactsAndScale(tc)
m=tc.TestData.manifest; p=pipeline.create_output_paths(tc.TestData.root,m.ID(1));
[audio,fs]=audioread(p.wavFile);
verifyEqual(tc,fs,16000); verifyEqual(tc,numel(audio),4000);
s=load(p.matFile,'results'); result=s.results;
verifyLessThan(tc,max(abs(audio*result.output.paPerFullScale-result.signals.finalPa)),1e-5);
verifyEqual(tc,result.output.audioFiles.final,p.wavFile);
verifyFalse(tc,result.output.adaptiveScaleUsed);
verifyTrue(tc,isfile(p.configFile));
verifyEqual(tc,numel(dir(fullfile(p.figureDir,'*.png'))),4);
verifyEqual(tc,string(sheetnames(p.excelFile)),["Conditions";"Obstacles";"Paths";"Reflections"]);
conditions=readtable(p.excelFile,'Sheet','Conditions','TextType','string');
verifyEqual(tc,conditions.Value(conditions.Condition=="OutputWAV_Final"),string(p.wavFile));
verifyEqual(tc,result.signals.finalPa, ...
    result.signals.directPa+result.signals.reflectedPa+result.signals.diffractedPa,'AbsTol',1e-10);
end
function test_unchangedAcousticResult(tc)
c=pipeline.row_to_config(tc.TestData.rows(1,:),tc.TestData.config);
c.output.rootDir=tempname; c.simulation.id="BASELINE";
c.output.writeComponentWav=false; c.output.writeMat=false;
c.output.writeFigures=false; c.output.writeExcel=false;
baseline=acoustics.runSimulation(c);
p=pipeline.create_output_paths(tc.TestData.root,tc.TestData.manifest.ID(1));
saved=load(p.matFile,'results');
verifyEqual(tc,saved.results.signals,baseline.signals);
verifyEqual(tc,saved.results.obstacles,baseline.obstacles);
verifyEqual(tc,saved.results.output.paPerFullScale,baseline.output.paPerFullScale);
end
function test_skipRenameOverwrite(tc)
row=tc.TestData.rows(1,:); c=tc.TestData.config; o=tc.TestData.options;
o.writeFigures=false; o.writeMat=false;
o.collisionPolicy='Skip';
[m,a]=pipeline.run_batch(row,c,o);
verifyEqual(tc,a.Status(end),"SKIPPED");
verifyEqual(tc,m.Status(m.ID==tc.TestData.manifest.ID(1)),"SUCCESS");
o.collisionPolicy='Rename';
[~,a]=pipeline.run_batch(row,c,o);
verifyEqual(tc,a.Status(end),"SUCCESS");
verifyTrue(tc,endsWith(a.ID(end),"_REP02"));
verifyTrue(tc,isfile(a.WAVPath(end)));
o.collisionPolicy='Overwrite';
[m,a]=pipeline.run_batch(row,c,o);
verifyEqual(tc,a.Status(end),"SUCCESS");
verifyTrue(tc,isfolder(a.ArchiveFolder(end)));
verifyTrue(tc,isfile(fullfile(a.ArchiveFolder(end),a.ID(end)+".wav")));
verifyEqual(tc,nnz(m.ID==a.ID(end)),1);
end
function test_cancelledRowsAndLock(tc)
c=tc.TestData.config; rows=tc.TestData.rows([1 3],:);
o=tc.TestData.options; o.datasetName=[o.datasetName,'_cancel']; o.cancelFcn=@()true;
[~,attempts]=pipeline.run_batch(rows,c,o);
verifyEqual(tc,attempts.Status,["CANCELLED";"CANCELLED"]);
root=fullfile(o.datasetParent,o.datasetName);
verifyFalse(tc,isfolder(fullfile(root,'.batch_lock')));
verifyEmpty(tc,dir(fullfile(root,'audio','*.wav')));
mkdir(fullfile(root,'.batch_lock'));
verifyError(tc,@()pipeline.run_batch(rows,c,o),'pipeline:DatasetLocked');
rmdir(fullfile(root,'.batch_lock'));
end
