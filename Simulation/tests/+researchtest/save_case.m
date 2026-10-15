function save_case(r,detail,checks,o)
%SAVE_CASE Export per-case evidence without altering pressure scaling.
% Inputs: simulator result, diagnostics, checks, options. Output: disk files.
dest=r.output.directory;
writetable(checks,fullfile(dest,'checks.csv'));
writetable(detail.events,fullfile(dest,'gate_events.csv'));
if width(detail.warp)>0,writetable(detail.warp,fullfile(dest,'diffraction_time_warp.csv'));end
save(fullfile(dest,'quality_diagnostics.mat'),'detail');
if ~o.saveFigures,return;end
t=r.timeSec;fs=r.sampleRateHz;
f=figure('Visible','off','Position',[100 100 1100 900]);clean=onCleanup(@()close(f));
v={r.audio.inputPa,r.signals.directPa,r.signals.reflectedPa,r.signals.diffractedPa,r.signals.finalPa};
names={'Input at reference distance','Direct','Reflected (ground + obstacle)','Diffracted','Final'};
for k=1:5
    subplot(5,1,k);plot(t,v{k});ylabel('Pa');title(names{k});grid on;
    if k==5,xlabel('Receiver / input time [s]');end
end
exportgraphics(f,fullfile(dest,'waveforms.png'),'Resolution',130);clear clean;
f=figure('Visible','off','Position',[100 100 1100 650]);clean=onCleanup(@()close(f));
% Common 80 dB display range for input/output; do not alter signal levels.
peakSpectrum=-Inf;axesHandles=gobjects(2,1);
for k=1:2
    axesHandles(k)=subplot(2,1,k);
    if k==1,y=r.audio.inputPa;name='Input';else,y=r.signals.finalPa;name='Final';end
    [s,freq,tt]=spectrogram(y,hann(512,'periodic'),384,1024,fs);
    spectrumDb=20*log10(max(abs(s),1e-12));peakSpectrum=max(peakSpectrum,max(spectrumDb,[],'all'));
    imagesc(tt,freq,spectrumDb);axis xy;ylim([0 4000]);
    ylabel('Hz');title([name,' STFT magnitude (dB re 1 Pa; uncalibrated window gain)']);colorbar;
end
for k=1:2,clim(axesHandles(k),[peakSpectrum-80 peakSpectrum]);end
xlabel('Time [s]');exportgraphics(f,fullfile(dest,'spectrograms.png'),'Resolution',130);clear clean;
f=figure('Visible','off','Position',[100 100 1100 750]);clean=onCleanup(@()close(f));
subplot(3,1,1);plot(t,r.paths.direct.distanceM);ylabel('Distance [m]');grid on;
subplot(3,1,2);plot(t,r.paths.direct.dopplerFactor);ylabel('Direct frequency ratio');grid on;
subplot(3,1,3);
if ~isempty(detail.warp)
    w=detail.warp;plot(w.StartSec(w.BothActive),w.TimeWarp(w.BothActive),'.');
else,text(.1,.5,'No active diffraction intervals');end
ylabel('Diffraction time-warp');xlabel('Time [s]');grid on;
exportgraphics(f,fullfile(dest,'path_metrics.png'),'Resolution',130);clear clean;
end
