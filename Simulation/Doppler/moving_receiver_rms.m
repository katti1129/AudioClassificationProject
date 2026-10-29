function [result, outputDir] = moving_receiver_rms(config)
%MOVING_RECEIVER_RMS Run real-WAV constant-velocity simulation and save outputs.
% Input: optional config structure (see moving_receiver_rms_config).
% Outputs: result (Pa waveforms/paths/config) and unique output folder.
% Calling with no arguments is the GUI Editor Run / command-line entry point.
if nargin < 1, config = moving_receiver_rms_config(); end
result = simulate_moving_receiver_rms(config);
signals = [result.direct_signal, result.reflected_signal, result.final_signal];
digital = signals/config.wavFullScalePa;
if any(~isfinite(digital), 'all') || max(abs(digital), [], 'all') >= 1
    error('doppler:Clipping', ['Fixed-scale WAV would clip. No audio was saved. ' ...
        'Choose a common larger wavFullScalePa for the experiment; no automatic normalization.']);
end
if ~isfolder(config.outputRoot), mkdir(config.outputRoot); end
[~, suffix] = fileparts(tempname(config.outputRoot));
outputDir = fullfile(config.outputRoot, ['RMS_' suffix]);
mkdir(outputDir);
names = ["direct", "reflected", "final"];
for k = 1:3
    audioPath = fullfile(outputDir, names(k)+".wav");
    audiowrite(audioPath, digital(:,k), result.fs, 'BitsPerSample', 24);
    [saved, savedFs] = audioread(audioPath);
    assert(savedFs == result.fs && isequal(size(saved), size(digital(:,k))));
    assert(max(abs(saved-digital(:,k))) <= 2^-23, 'WAV readback error.');
end
result.outputDir = outputDir;
save(fullfile(outputDir, 'result.mat'), 'result', '-v7.3');
calibration = table(result.fs, result.inputDurationSec, result.referenceRmsPa, ...
    config.sourceSplDb, config.referenceDistanceM, config.wavFullScalePa, ...
    string(config.inputFile), 'VariableNames', {'FsHz','InputDurationSec', ...
    'ReferenceRmsPa','SourceSplDb','ReferenceDistanceM','WavFullScalePa','InputFile'});
writetable(calibration, fullfile(outputDir, 'calibration.csv'));
summary = table(names', sqrt(mean(signals.^2,1))', max(abs(signals),[],1)', ...
    max(abs(digital),[],1)', 'VariableNames', {'Component','WholeOutputRmsPa','PeakPa','PeakWav'});
writetable(summary, fullfile(outputDir, 'signal_summary.csv'));
if config.makeFigures
    saveFigures(result, outputDir, config.figureVisible);
end
fprintf('RMS calibration: %.6f dB SPL at %.3f m (assumed source level)\n', ...
    20*log10(sqrt(mean(result.source_signal_pa.^2))/2e-5), config.referenceDistanceM);
fprintf('Source %.3f m/s; Receiver %.3f m/s; output: %s\n', ...
    norm(config.source.velocityMps), norm(config.receiver.velocityMps), outputDir);
end

function saveFigures(r, outputDir, visibility)
% Save geometry/delay/Doppler, pressure/RMS, and input/output spectrogram PNGs.
f = figure('Name','Moving receiver: geometry and propagation','Visible',visibility);
tiledlayout(3,1);
nexttile;
s = reshape(r.config.source.positionM,1,3) + r.timeSec*reshape(r.config.source.velocityMps,1,3);
q = reshape(r.config.receiver.positionM,1,3) + r.timeSec*reshape(r.config.receiver.velocityMps,1,3);
plot(s(:,1),s(:,2),q(:,1),q(:,2)); axis equal; grid on;
xlabel('x [m]'); ylabel('y [m]'); legend('Source','Receiver');
nexttile;
plot(r.timeSec,r.directPath.distanceM); hold on;
if ~isempty(r.reflectedPath), plot(r.timeSec,r.reflectedPath.distanceM); end
ylabel('Path length [m]'); grid on;
if ~isempty(r.reflectedPath), legend('Direct','Ground reflection'); end
nexttile;
plot(r.timeSec,r.directPath.dopplerFactor); hold on;
if ~isempty(r.reflectedPath), plot(r.timeSec,r.reflectedPath.dopplerFactor); end
xlabel('Reception time [s]'); ylabel('Frequency ratio'); grid on;
if ~isempty(r.reflectedPath), legend('Direct','Ground reflection'); end
exportgraphics(f,fullfile(outputDir,'geometry_doppler.png'));
if strcmp(visibility,'off'), close(f); end
f = figure('Name','Pressure and short-time RMS SPL','Visible',visibility);
tiledlayout(5,1);
nexttile; plot(r.inputTimeSec,r.source_signal_pa); ylabel('Source [Pa]');
nexttile; plot(r.timeSec,r.direct_signal); ylabel('Direct [Pa]');
nexttile; plot(r.timeSec,r.reflected_signal); ylabel('Reflected [Pa]');
nexttile; plot(r.timeSec,r.final_signal); ylabel('Final [Pa]');
% Do not let exact silence (-Inf dB) hide the finite RMS curve on the plot.
displaySpl = r.shortTimeSplDb;
displaySpl(~isfinite(displaySpl)) = NaN;
nexttile; plot(r.timeSec,displaySpl); ylabel('RMS SPL [dB]'); xlabel('Time [s]');
exportgraphics(f,fullfile(outputDir,'waveforms_rms.png'));
if strcmp(visibility,'off'), close(f); end
f = figure('Name','Source / received spectrograms','Visible',visibility);
tiledlayout(2,1);
window = min(512,numel(r.source_signal_pa));
nexttile;
spectrogram(r.source_signal_pa,window,floor(window*.9),1024,r.fs,'yaxis');
title('Input source [Pa]');
clim([-80,30]);
nexttile;
spectrogram(r.final_signal,window,floor(window*.9),1024,r.fs,'yaxis');
title('Final received [Pa]');
clim([-80,30]); % Same PSD color scale for both plots, no signal normalization.
exportgraphics(f,fullfile(outputDir,'spectrograms.png'));
if strcmp(visibility,'off'), close(f); end
end
