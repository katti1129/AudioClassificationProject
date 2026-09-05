function results = createFigures(results, config)
%CREATEFIGURES Create and save geometry, waveform, spectral, and diagnostic PNGs.
%   RESULTS = CREATEFIGURES(RESULTS, CONFIG) renders figures invisibly and
%   saves them under RESULTS.output.figureDirectory. Geometry uses metres,
%   waveforms use calibrated pressure [Pa], and spectra use frequency [Hz].

arguments
    results (1,1) struct
    config (1,1) struct
end

if ~config.output.writeFigures
    return;
end

directory = results.output.figureDirectory;
id = char(results.simulationId);

files.geometry = fullfile(directory, sprintf('%s_geometry.png', id));
files.waveforms = fullfile(directory, sprintf('%s_waveforms.png', id));
files.spectrograms = fullfile(directory, sprintf('%s_spectrograms.png', id));
files.diagnostics = fullfile(directory, sprintf('%s_diagnostics.png', id));

figures = gobjects(4,1);
figures(1) = geometryFigure(results);
exportgraphics(figures(1), files.geometry, 'Resolution', 200);
figures(2) = waveformFigure(results);
exportgraphics(figures(2), files.waveforms, 'Resolution', 200);
figures(3) = spectrogramFigure(results);
exportgraphics(figures(3), files.spectrograms, 'Resolution', 200);
figures(4) = diagnosticFigure(results, config);
exportgraphics(figures(4), files.diagnostics, 'Resolution', 200);

if config.output.closeFiguresAfterSave
    close(figures(ishandle(figures)));
end
results.output.figureFiles = files;

if config.output.writeMat
    save(results.output.matFile, 'results', '-v7.3');
end
end

function figureHandle = geometryFigure(results)
figureHandle = figure('Visible','off','Color','w','Name','Simulation geometry');
axesHandle = axes(figureHandle); hold(axesHandle,'on'); grid(axesHandle,'on');
axis(axesHandle,'equal'); view(axesHandle,3);

s = results.trajectories.source.positionM;
r = results.trajectories.receiver.positionM;
plot3(axesHandle, s(:,1),s(:,2),s(:,3),'r-','LineWidth',1.6,'DisplayName','Source trajectory');
plot3(axesHandle, r(:,1),r(:,2),r(:,3),'b-','LineWidth',1.6,'DisplayName','Receiver trajectory');

if isfield(results.paths,'direct')
    [~, representative] = min(results.paths.direct.distanceM);
else
    representative = max(1, round(size(s,1)/2));
end
representative = min([representative,size(s,1),size(r,1)]);
if isfield(results.paths,'direct') && isfield(results.paths.direct,'sourcePositionM')
    sourcePathPoint=results.paths.direct.sourcePositionM(representative,:);
    receiverPathPoint=results.paths.direct.receiverPositionM(representative,:);
else
    sourcePathPoint=s(representative,:);
    receiverPathPoint=r(representative,:);
end
plot3(axesHandle,sourcePathPoint(1),sourcePathPoint(2),sourcePathPoint(3), ...
    'ro','MarkerFaceColor','r','DisplayName','Source');
plot3(axesHandle,receiverPathPoint(1),receiverPathPoint(2),receiverPathPoint(3), ...
    'bo','MarkerFaceColor','b','DisplayName','Receiver');
plot3(axesHandle,[sourcePathPoint(1),receiverPathPoint(1)], ...
    [sourcePathPoint(2),receiverPathPoint(2)], ...
    [sourcePathPoint(3),receiverPathPoint(3)],'k--','DisplayName','LOS');

candidate = false(numel(results.obstacles),1);
if isfield(results,'fresnel')
    if isfield(results.fresnel,'candidateMask'), candidate = results.fresnel.candidateMask(:); end
end
blocked = false(numel(results.obstacles),1);
if isfield(results,'obstruction')
    names = {'blockedByObstacle','everBlockedByObstacle','obstacleBlockedMask'};
    for k=1:numel(names)
        if isfield(results.obstruction,names{k})
            blocked = results.obstruction.(names{k})(:); break;
        end
    end
end
for k = 1:numel(results.obstacles)
    color = [0.72 0.72 0.72]; alpha = 0.18;
    if candidate(k), color=[0.95 0.55 0.10]; alpha=0.30; end
    if blocked(k), color=[0.80 0.10 0.10]; alpha=0.40; end
    drawBox(axesHandle, results.obstacles(k), color, alpha);
end

if isfield(results.paths,'reflections') && ~isempty(results.paths.reflections)
    for k=1:numel(results.paths.reflections)
        path=results.paths.reflections(k);
        if ~isfield(path,'reflectionPointM'), continue; end
        idx=min(representative,size(path.reflectionPointM,1)); q=path.reflectionPointM(idx,:);
        if all(isfinite(q))
            reflectedSource=path.sourcePositionM(idx,:);
            reflectedReceiver=path.receiverPositionM(idx,:);
            plot3(axesHandle,[reflectedSource(1),q(1),reflectedReceiver(1)], ...
                [reflectedSource(2),q(2),reflectedReceiver(2)], ...
                [reflectedSource(3),q(3),reflectedReceiver(3)], ...
                'c-.','LineWidth',1.2,'DisplayName','Reflection path');
        end
    end
end

if isfield(results.paths,'obstacleReflections') ...
        && ~isempty(results.paths.obstacleReflections)
    plotted=0;
    for k=1:numel(results.paths.obstacleReflections)
        path=results.paths.obstacleReflections(k);
        idx=find(path.valid,1,'first');
        if isempty(idx), continue; end
        q=path.reflectionPointM(idx,:);
        reflectedSource=path.sourcePositionM(idx,:);
        reflectedReceiver=path.receiverPositionM(idx,:);
        visibility='off';
        if plotted==0, visibility='on'; end
        plot3(axesHandle,[reflectedSource(1),q(1),reflectedReceiver(1)], ...
            [reflectedSource(2),q(2),reflectedReceiver(2)], ...
            [reflectedSource(3),q(3),reflectedReceiver(3)], ...
            '-.','Color',[0.1 0.5 0.8],'LineWidth',1.0, ...
            'DisplayName','Obstacle reflection path', ...
            'HandleVisibility',visibility);
        plotted=plotted+1;
        if plotted>=5, break; end
    end
end

if isfield(results,'diffraction') && any(results.diffraction.active)
    idx=find(results.diffraction.active,1,'first'); q=results.diffraction.pointM(idx,:);
    t=results.diffraction.analysisTimeSec(idx);
    tau=results.diffraction.emissionTimeSec(idx);
    ss=acoustics.computeTrajectory(results.config.source,tau);
    rr=acoustics.computeTrajectory(results.config.receiver,t);
    if isfield(results.diffraction,'pathPointsM') ...
            && ~isempty(results.diffraction.pathPointsM{idx})
        diffractionPoints=results.diffraction.pathPointsM{idx};
    elseif isfield(results.diffraction,'secondPointM')
        diffractionPoints=[q;results.diffraction.secondPointM(idx,:)];
    else
        diffractionPoints=q;
    end
    polyline=[ss.positionM(1,:);diffractionPoints;rr.positionM(1,:)];
    plot3(axesHandle,polyline(:,1),polyline(:,2),polyline(:,3), ...
        'm-','LineWidth',1.6,'DisplayName','Diffraction path');
    plot3(axesHandle,diffractionPoints(:,1),diffractionPoints(:,2), ...
        diffractionPoints(:,3),'mx','MarkerSize',9,'LineWidth',1.5, ...
        'DisplayName','Diffraction point');
end
xlabel(axesHandle,'x [m]'); ylabel(axesHandle,'y [m]'); zlabel(axesHandle,'z [m]');
title(axesHandle,sprintf('Geometry: %s',results.simulationId),'Interpreter','none');
legend(axesHandle,'Location','bestoutside');
end

function figureHandle = waveformFigure(results)
figureHandle=figure('Visible','off','Color','w','Name','Waveforms','Position',[100 100 1100 900]);
names={'Input at reference distance','Direct','Reflected','Diffracted','Final'};
fields={'inputPa','directPa','reflectedPa','diffractedPa','finalPa'};
for k=1:5
    ax=subplot(5,1,k,'Parent',figureHandle);
    if k==1
        values=results.audio.inputPa; time=results.audio.sourceTimeSec;
    else
        values=results.signals.(fields{k}); time=results.timeSec;
    end
    plot(ax,time,values,'k'); grid(ax,'on'); ylabel(ax,'Pa'); title(ax,names{k});
    if k==5, xlabel(ax,'Time [s]'); end
end
end

function figureHandle = spectrogramFigure(results)
figureHandle=figure('Visible','off','Color','w','Name','Spectrograms','Position',[100 100 1100 750]);
values={results.audio.inputPa,results.signals.finalPa};
titles={'Input spectrogram','Final receiver spectrogram'};
for k=1:2
    ax=subplot(2,1,k,'Parent',figureHandle);
    nfft=min(1024,max(128,2^floor(log2(numel(values{k})))));
    window=0.5-0.5*cos(2*pi*(0:nfft-1)'/nfft);
    overlap=round(0.875*nfft);
    [s,f,t]=spectrogram(values{k},window,overlap,nfft,results.sampleRateHz);
    level=20*log10(max(abs(s),realmin));
    level=level-max(level,[],'all');
    imagesc(ax,t,f,level); axis(ax,'xy'); ylim(ax,[0 results.sampleRateHz/2]);
    xlabel(ax,'Time [s]'); ylabel(ax,'Frequency [Hz]'); title(ax,titles{k});
    clim(ax,[-80 0]);
    colorbarHandle=colorbar(ax);
    colorbarHandle.Label.String='Magnitude [dB re panel maximum]';
    colormap(ax,'turbo');
end
end

function figureHandle = diagnosticFigure(results,config)
figureHandle=figure('Visible','off','Color','w','Name','Diagnostics','Position',[100 100 1100 850]);
t=results.timeSec; path=results.paths.direct;
ax=subplot(3,1,1,'Parent',figureHandle); plot(ax,t,path.distanceM,'b'); grid(ax,'on');
ylabel(ax,'Distance [m]'); title(ax,'Direct path length');
ax=subplot(3,1,2,'Parent',figureHandle); plot(ax,t,path.dopplerFactor,'r'); grid(ax,'on');
yline(ax,1,'k--'); ylabel(ax,'f_r/f_s'); title(ax,'Instantaneous Doppler factor');
window=max(1,round(0.125*results.sampleRateHz));
rmsPa=sqrt(movmean(results.signals.finalPa.^2,window));
spl=20*log10(max(rmsPa,eps)/config.physics.referencePressurePa);
ax=subplot(3,1,3,'Parent',figureHandle); plot(ax,t,spl,'g'); grid(ax,'on');
xlabel(ax,'Time [s]'); ylabel(ax,'dB SPL'); title(ax,'125 ms running RMS level');
end

function drawBox(ax,obstacle,color,alpha)
if isfield(obstacle,'minCornerM')
    mn=obstacle.minCornerM; mx=obstacle.maxCornerM;
else
    center=obstacle.centerM;
    half=[obstacle.widthM/2,obstacle.depthM/2,obstacle.heightM/2];
    mn=center-half; mx=center+half;
end
vertices=[mn(1) mn(2) mn(3); mx(1) mn(2) mn(3); mx(1) mx(2) mn(3); mn(1) mx(2) mn(3); ...
          mn(1) mn(2) mx(3); mx(1) mn(2) mx(3); mx(1) mx(2) mx(3); mn(1) mx(2) mx(3)];
faces=[1 2 3 4;5 6 7 8;1 2 6 5;2 3 7 6;3 4 8 7;4 1 5 8];
patch(ax,'Vertices',vertices,'Faces',faces,'FaceColor',color,'FaceAlpha',alpha, ...
    'EdgeColor',color,'HandleVisibility','off');
end
