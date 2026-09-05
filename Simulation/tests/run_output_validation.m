function report = run_output_validation()
%RUN_OUTPUT_VALIDATION Generate and read back every required output type.
%   REPORT = RUN_OUTPUT_VALIDATION() runs a short 16 kHz simulation using
%   the real ambulance WAV and one blocking/reflecting AABB. It verifies
%   component summation, WAV scaling and sample metadata, XLSX sheets and
%   required obstacle columns, MAT content, and nonempty PNG files. Output
%   remains under data/output/validation/VALIDATION_OUTPUT_SMOKE.

rootDirectory=fileparts(fileparts(mfilename('fullpath')));
addpath(rootDirectory);
config=default_config();
config.simulation.id="VALIDATION_OUTPUT_SMOKE";
config.simulation.durationSec=0.5;
config.simulation.geometryTimeStepSec=0.025;
config.audio.sampleRateHz=16000;
config.audio.internalOversampleFactor=1;
config.source.initialPositionM=[-10 0 1.5];
config.source.initialVelocityMps=[0 0 0];
config.receiver.initialPositionM=[10 0 1.5];
config.receiver.initialVelocityMps=[0 0 0];
config.obstacle.enabled=true;
config.obstacle.manualObstacles=manualBox();
config.diffraction.windowLengthSamples=256;
config.diffraction.overlapSamples=192;
config.diffraction.fftLength=256;
config.output.rootDir=fullfile(rootDirectory,'data','output','validation');
config.output.overwrite=true;

results=acoustics.runSimulation(config);
checks=strings(24,1); passed=false(24,1); details=strings(24,1);
checkCount=0;
record('component_sum',max(abs(results.signals.finalPa-( ...
    results.signals.directPa+results.signals.reflectedPa ...
    +results.signals.diffractedPa)))<1e-10,'final = direct + reflected + diffracted');

audioNames={'direct','reflected','diffracted','final'};
for audioIndex=1:numel(audioNames)
    name=audioNames{audioIndex};
    filename=results.output.audioFiles.(name);
    info=audioinfo(filename);
    record("wav_exists_"+name,isfile(filename),'WAV exists');
    record("wav_rate_"+name,info.SampleRate==16000,'16 kHz');
    record("wav_length_"+name,info.TotalSamples==8000,'0.5 s');
end

[digitalFinal,readFs]=audioread(results.output.audioFiles.final);
restoredPa=double(digitalFinal)*results.output.paPerFullScale;
tolerance=max(2e-6*results.output.paPerFullScale, ...
    5e-6*max(abs(results.signals.finalPa)));
record('wav_pressure_readback',readFs==results.sampleRateHz ...
    && max(abs(restoredPa-results.signals.finalPa))<=tolerance, ...
    sprintf('max error %.6g Pa',max(abs(restoredPa-results.signals.finalPa))));
record('wav_no_clipping',max(abs(digitalFinal))<=config.output.clippingHeadroom+1e-6, ...
    sprintf('digital peak %.6g',max(abs(digitalFinal))));
nominalScale=config.physics.referencePressurePa ...
    *10^(config.output.fullScaleSPLdB/20);
record('fixed_wav_scale',~results.output.adaptiveScaleUsed ...
    && abs(results.output.paPerFullScale-nominalScale)<1e-12*nominalScale, ...
    sprintf('%.9g Pa/full-scale',results.output.paPerFullScale));

requiredSheets=["Conditions","Obstacles","Paths","Reflections"];
actualSheets=string(sheetnames(results.output.excelFile));
record('xlsx_sheets',all(ismember(requiredSheets,actualSheets)), ...
    strjoin(cellstr(actualSheets),', '));
obstacleTable=readtable(results.output.excelFile,'Sheet','Obstacles', ...
    'VariableNamingRule','preserve');
requiredColumns=["SimulationID","ObstacleID","RandomSeed","X_M","Y_M", ...
    "Z_M","Width_M","Depth_M","Height_M","ReflectionCoefficient", ...
    "LOSBlocked","InsideFresnel","FresnelSelected","DiffractionUsed", ...
    "DiffractionPointX_M","SourceToObstacle_M","ObstacleToReceiver_M", ...
    "DiffractionPath_M","DiffractionLoss_dB"];
record('xlsx_obstacle_columns',all(ismember(requiredColumns, ...
    string(obstacleTable.Properties.VariableNames))),'required columns');

matVariables=whos('-file',results.output.matFile);
record('mat_results',any(strcmp({matVariables.name},'results')),'results variable');
figureNames=fieldnames(results.output.figureFiles);
figuresValid=true;
for figureIndex=1:numel(figureNames)
    fileInfo=dir(results.output.figureFiles.(figureNames{figureIndex}));
    figuresValid=figuresValid && ~isempty(fileInfo) && fileInfo.bytes>0;
end
record('png_files',figuresValid,sprintf('%d figures',numel(figureNames)));

checks=checks(1:checkCount);
passed=passed(1:checkCount);
details=details(1:checkCount);
report=table(checks,passed,details,'VariableNames',{'Check','Passed','Details'});
disp(report);
if any(~passed)
    error('acoustics:OutputValidationFailed','Output validation failed: %s', ...
        strjoin(cellstr(checks(~passed)),', '));
end
fprintf('All %d output validation checks passed.\n',height(report));

    function record(name,condition,detail)
        checkCount=checkCount+1;
        checks(checkCount)=string(name);
        passed(checkCount)=logical(condition);
        details(checkCount)=string(detail);
    end
end

function obstacle=manualBox()
%MANUALBOX Return the deterministic validation obstacle in SI units.
center=[0 0 2]; width=1; depth=2; height=4;
half=[width/2,depth/2,height/2];
obstacle=struct('id',"OBS_001",'centerM',center, ...
    'widthM',width,'depthM',depth,'heightM',height, ...
    'minCornerM',center-half,'maxCornerM',center+half, ...
    'material',"test_concrete",'pressureReflectionCoefficient',0.7);
end
