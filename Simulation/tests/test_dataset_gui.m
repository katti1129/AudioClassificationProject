function tests = test_dataset_gui()
%TEST_DATASET_GUI Exercise real GUI callbacks without interactive dialogs.
tests=functiontests(localfunctions);
end
function test_editSaveLoadRun(tc)
c=default_config(); c.simulation.durationSec=.15;
c.obstacle.enabled=false; c.reflection.enabled=false;
c.audio.internalOversampleFactor=1;
app=dataset_generator(c,'off');
cleanup=onCleanup(@()delete(app.Figure));
app.Controls.Count.Value=2; app.generateRows();
app.Controls.Common.CPA_m.Value=20;
app.Controls.Common.ReceiverVelocityKmh.Value=4;
app.applyAll();
app.Controls.StartSeed.Value=101; app.assignSeeds();
rows=app.getRows();
verifyEqual(tc,height(rows),2);
verifyEqual(tc,rows.CPA_m,[20;20]);
verifyEqual(tc,rows.Seed,[101;102]);
% Selected-row common settings use the same CellSelectionCallback as the UI.
callback=app.Controls.Table.CellSelectionCallback;
callback(app.Controls.Table,struct('Indices',[2 3]));
app.Controls.Common.CPA_m.Value=50; app.applySelected();
rows=app.getRows(); verifyEqual(tc,rows.CPA_m,[20;50]);
parent=tempname; mkdir(parent);
file=fullfile(parent,'settings.mat'); app.saveConfig(file);
app.Controls.Count.Value=1; app.generateRows(); app.loadConfig(file);
verifyEqual(tc,app.getRows(),rows);
app.Controls.Parent.Value=parent; app.Controls.DatasetName.Value='GUI_TEST';
app.Controls.SaveFigures.Value=false; app.Controls.SaveMat.Value=false;
[m,a]=app.run();
verifyEqual(tc,a.Status,["SUCCESS";"SUCCESS"]);
verifyEqual(tc,height(m),2);
verifyEqual(tc,app.Controls.Progress.Value,100);
verifyEqual(tc,app.Controls.Run.Enable,matlab.lang.OnOffSwitchState.on);
verifyEqual(tc,app.Controls.Counter.Text,'2 / 2');
end
