function [result,outputDir] = run_background_simulation(config,progress)
%RUN_BACKGROUND_SIMULATION Existing Doppler renderer plus selected background.
% Inputs: optional config; optional progress(stage,fraction) callback returning
% true to continue or false to cancel BEFORE saving. Polls phase boundaries,
% not individual audio samples. Saving is not interruptible.
% Outputs: result with Pa components/metadata/mask, and unique output folder.
% No changes to original renderer. No per-file normalization or auto limiting.
if nargin<1, config = background_simulation_config(); end
if nargin<2, progress = []; end
checkpoint(progress,'simulation',0);
clean = simulate_moving_receiver_rms(config);
checkpoint(progress,'mixing',.55);
result = mix_background_audio(clean,config.background);
signals = [result.direct_signal,result.reflected_signal,result.siren_signal, ...
    result.background_signal,result.final_signal];
digital = signals/config.wavFullScalePa;
if any(~isfinite(digital),'all') || max(abs(digital),[],'all')>=1
    error('background:Clipping','Fixed-scale output would clip. No files saved; set one common larger wavFullScalePa for all comparison conditions.');
end
checkpoint(progress,'saving',.7);
if ~isfolder(config.outputRoot), mkdir(config.outputRoot); end
[~,id] = fileparts(tempname(config.outputRoot));
outputDir = fullfile(config.outputRoot,['BG_' id]);
mkdir(outputDir);
result.outputDir = outputDir;
result.simulationId = string(['BG_' id]);
names = ["direct","reflected","siren","background","final"];
for k=1:numel(names)
    filename = fullfile(outputDir,names(k)+".wav");
    audiowrite(filename,digital(:,k),result.fs,'BitsPerSample',24);
    [saved,savedFs] = audioread(filename);
    assert(savedFs==result.fs && isequal(size(saved),size(digital(:,k))));
    assert(max(abs(saved-digital(:,k)))<=2^-23,'WAV roundtrip exceeds one 24-bit step.');
end
save(fullfile(outputDir,'result.mat'),'result','-v7.3');
writetable(result.backgroundInfo,fullfile(outputDir,'background_settings.csv'));
summary = table(names',sqrt(mean(signals.^2,1))',max(abs(signals),[],1)', ...
    max(abs(digital),[],1)','VariableNames',{'Component','WholeOutputRmsPa','PeakPa','PeakWav'});
writetable(summary,fullfile(outputDir,'signal_summary.csv'));
calibration = table(result.simulationId,result.fs,config.wavFullScalePa, ...
    config.sourceSplDb,config.referenceDistanceM,string(config.inputFile), ...
    'VariableNames',{'SimulationId','FsHz','WavFullScalePa','SirenReferenceSplDb','ReferenceDistanceM','SirenFile'});
writetable(calibration,fullfile(outputDir,'calibration.csv'));
windows = windowMetrics(result);
writetable(windows,fullfile(outputDir,'window_metrics.csv'));
if config.makeFigures, drawFigures(result,windows,config.figureVisible,outputDir); end
fprintf('Background simulation saved: %s\n',outputDir);
disp(result.backgroundInfo(:,{'Mode','ActualStartSec','ActualEndExclusiveSec','ActualBackgroundSplDb','ActualSnrDb'}));
end

function checkpoint(callback,stage,fraction)
% Poll optional UI control without changing numerical inputs or outputs.
if ~isempty(callback) && ~callback(stage,fraction)
    error('background:Cancelled','Cancelled before output saving. No files saved.');
end
end

function metrics = windowMetrics(r)
% Return nonoverlapping 1 s received-time window RMS/SNR and placement coverage.
% Coverage describes insertion, NOT siren ground truth or AI scoring eligibility.
fs = r.fs; n = numel(r.timeSec); starts = (1:fs:n)';
rows = zeros(numel(starts),7);
for k=1:numel(starts)
    stop = min(starts(k)+fs-1,n);
    ix = starts(k):stop;
    sp = sqrt(mean(r.siren_signal(ix).^2));
    bp = sqrt(mean(r.background_signal(ix).^2));
    snr = NaN;
    if bp>0, snr = 20*log10(sp/bp); end
    rows(k,:) = [(starts(k)-1)/fs,stop/fs,mean(r.background_interval_mask(ix)), ...
        sp,bp,sqrt(mean(r.final_signal(ix).^2)),snr];
end
metrics = array2table(rows,'VariableNames',{'StartSec','EndExclusiveSec','BackgroundCoverage', ...
    'SirenRmsPa','BackgroundRmsPa','MixedRmsPa','SnrDb'});
end

function drawFigures(r,w,visible,outputDir)
% Save pressure/placement/RMS and paired spectrogram PNGs; does not alter audio.
f = figure('Name','Doppler + background','Visible',visible,'Position',[100,100,1000,850]);
tiledlayout(4,1);
nexttile; plot(r.timeSec,r.siren_signal); ylabel('Siren [Pa]'); markInterval(r);
nexttile; plot(r.timeSec,r.background_signal); ylabel('Background [Pa]'); markInterval(r);
nexttile; plot(r.timeSec,r.final_signal); ylabel('Mixed [Pa]'); markInterval(r);
nexttile;
levels = 20*log10([w.SirenRmsPa,w.BackgroundRmsPa,w.MixedRmsPa]/2e-5);
levels(~isfinite(levels)) = NaN;
plot((w.StartSec+w.EndExclusiveSec)/2,levels,'-o');
ylabel('1 s RMS SPL [dB]'); xlabel('Reception time [s]');
legend('Siren','Background','Mixed'); grid on;
exportgraphics(f,fullfile(outputDir,'background_waveforms.png'),'Resolution',120);
if strcmp(visible,'off'), close(f); end
f = figure('Name','Siren and mixture spectra','Visible',visible,'Position',[100,100,1000,650]);
tiledlayout(2,1);
nexttile; spectrogram(r.siren_signal,512,480,1024,r.fs,'yaxis');
clim([-80,30]); title('Siren only: pressure PSD');
nexttile; spectrogram(r.final_signal,512,480,1024,r.fs,'yaxis');
clim([-80,30]); title('Siren + background: same PSD scale');
exportgraphics(f,fullfile(outputDir,'background_spectrograms.png'),'Resolution',120);
if strcmp(visible,'off'), close(f); end
end

function markInterval(r)
% Mark actual insertion bounds [s] and simultaneous geometric CPA if available.
grid on;
if r.backgroundInfo.Enabled
    xline(r.backgroundInfo.ActualStartSec,'--');
    xline(r.backgroundInfo.ActualEndExclusiveSec,'--');
end
cpa = r.backgroundInfo.GeometricCpaTimeSec;
if isfinite(cpa) && cpa>=0 && cpa<=r.timeSec(end), xline(cpa,':'); end
end
