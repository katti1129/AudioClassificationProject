function results = run_single(config, paths, options)
%RUN_SINGLE Run unchanged acoustics, then save one AI WAV and diagnostics.
%   RESULTS = RUN_SINGLE(CONFIG,PATHS,OPTIONS) uses existing scale validation,
%   Excel and figure writers. Only a fully exported trial publishes its WAV.
%   Per-component physical pressure is retained in the optional results MAT.
assert(~isfile(paths.wavFile),'pipeline:OutputExists','WAV already exists: %s',paths.wavFile);
if ~isfolder(paths.resultDir), mkdir(paths.resultDir); end
if ~isfolder(paths.audioDir), mkdir(paths.audioDir); end
if ~isfolder(paths.excelDir), mkdir(paths.excelDir); end
if ~isfolder(paths.figureDir), mkdir(paths.figureDir); end
assert(strcmpi(config.output.wavClippingPolicy,'error'), ...
    'pipeline:FixedScale','Batch WAVs require the fixed full-scale policy.');
config.simulation.id=paths.name;
config.output.rootDir=fileparts(paths.resultDir);
config.output.writeComponentWav=false;
config.output.writeExcel=true;
config.output.writeFigures=options.writeFigures;
config.output.writeMat=options.writeMat;
config.output.overwrite=true; % Collision handling already selected/archived this exact path.
save(paths.configFile,'config','-v7');
config=acoustics.validateConfig(config);
computeConfig=config;
computeConfig.output.writeExcel=false;
computeConfig.output.writeFigures=false;
computeConfig.output.writeMat=false;
% writeOutputs still performs the existing pressure-scale/clipping checks.
results=acoustics.runSimulation(computeConfig);
results.config=config;
results.output.directory=paths.resultDir;
results.output.audioDirectory=paths.audioDir;
results.output.audioFiles=struct('final',paths.wavFile);
results.output.excelFile=paths.excelFile;
results.output.figureDirectory=paths.figureDir;
results.output.matFile=paths.matFile;
results.pipeline.experimentName=paths.name;
results.pipeline.finalWavOnly=true;
delta=results.trajectories.receiver.positionM-results.trajectories.source.positionM;
[results.pipeline.observedHorizontalCPAM,idx]=min(vecnorm(delta(:,1:2),2,2));
results.pipeline.observedCPATimeSec=results.timeSec(idx);
results.pipeline.observed3DMinimumM=min(vecnorm(delta,2,2));
results.pipeline.generatedAt=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
% Preserve current writer's physical scale; there is no peak normalization.
digitalSignal=results.signals.finalPa/results.output.paPerFullScale;
assert(all(isfinite(digitalSignal))&&all(abs(digitalSignal)<=1+10*eps), ...
    'pipeline:WavScale','Final WAV pressure scale is invalid.');
pending=fullfile(paths.resultDir,'pending_final.wav');
audiowrite(pending,digitalSignal,results.sampleRateHz, ...
    'BitsPerSample',config.output.wavBitsPerSample, ...
    'Title',char(paths.name), ...
    'Comment',sprintf('PaPerFullScale=%.17g',results.output.paPerFullScale));
results=acoustics.writeMetadataExcel(results,config);
if config.output.writeFigures
    % The unchanged figure writer repeats the long experiment ID in each
    % filename. Render in a short temporary path, then use role names inside
    % the uniquely named experiment folder (Windows path-length limits).
    figureStage=tempname;
    mkdir(figureStage);
    figureCleanup=onCleanup(@()removeStage(figureStage));
    results.output.figureDirectory=figureStage;
    figureConfig=config; figureConfig.output.writeMat=false;
    results=acoustics.createFigures(results,figureConfig);
    roles=fieldnames(results.output.figureFiles);
    for figureIndex=1:numel(roles)
        role=roles{figureIndex};
        finalFigure=fullfile(paths.figureDir,[role,'.png']);
        movefile(results.output.figureFiles.(role),finalFigure);
        results.output.figureFiles.(role)=finalFigure;
    end
    results.output.figureDirectory=paths.figureDir;
    clear figureCleanup;
end
% createFigures saves MAT only when figures are enabled; cover both cases.
if config.output.writeMat, save(paths.matFile,'results','-v7.3'); end
fid=fopen(paths.logFile,'w','n','UTF-8');
assert(fid>=0,'pipeline:LogWrite','Cannot write run_info.txt.');
closer=onCleanup(@()fclose(fid));
fprintf(fid,'Experiment: %s\nStatus: SUCCESS\nCreated: %s\n', ...
    paths.name,results.pipeline.generatedAt);
fprintf(fid,'Input WAV: %s\nFinal WAV: %s\nSeed: %.0f\n', ...
    config.audio.inputFile,paths.wavFile,config.obstacle.seed);
fprintf(fid,'PaPerFullScale: %.17g\nObserved horizontal CPA [m]: %.17g\n', ...
    results.output.paPerFullScale,results.pipeline.observedHorizontalCPAM);
fprintf(fid,'MATLAB: %s\nModel: %s\n',version,config.metadata.modelVersion);
clear closer;
assert(~isfile(paths.wavFile),'pipeline:OutputRace','Another process created the final WAV.');
movefile(pending,paths.wavFile); % Publication is the final step.
end

function removeStage(folder)
%REMOVESTAGE Remove only this call's freshly allocated temporary figure folder.
if isfolder(folder), rmdir(folder,'s'); end
end
