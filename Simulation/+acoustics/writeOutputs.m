function results = writeOutputs(results, config)
%WRITEOUTPUTS Save calibrated component audio and the physical MATLAB result.
%   RESULTS = WRITEOUTPUTS(RESULTS, CONFIG) writes direct, reflected,
%   diffracted, and final WAV files with one shared pressure scale. Signals
%   in RESULTS remain in Pa. WAV samples equal pressure/PaPerFullScale.
%   PaPerFullScale and all file paths are returned in RESULTS.output.

arguments
    results (1,1) struct
    config (1,1) struct
end

simulationId = char(results.simulationId);
simulationDirectory = fullfile(config.output.rootDir, simulationId);
audioDirectory = fullfile(simulationDirectory, 'audio');
figureDirectory = fullfile(simulationDirectory, 'figures');

if isfolder(simulationDirectory) && ~config.output.overwrite
    error('acoustics:OutputExists', ...
        'Output directory already exists and overwrite=false: %s', simulationDirectory);
end
if ~isfolder(audioDirectory), mkdir(audioDirectory); end
if ~isfolder(figureDirectory), mkdir(figureDirectory); end

signalFields = {'directPa','reflectedPa','diffractedPa','finalPa'};
peakPa = 0;
for k = 1:numel(signalFields)
    if isfield(results.signals, signalFields{k})
        values = results.signals.(signalFields{k});
        if ~isempty(values)
            peakPa = max(peakPa, max(abs(values), [], 'all'));
        end
    end
end

referencePressurePa = config.physics.referencePressurePa;
nominalPaPerFullScale = referencePressurePa ...
    * 10^(config.output.fullScaleSPLdB / 20);
requiredPaPerFullScale = peakPa / config.output.clippingHeadroom;
scaleExceeded = requiredPaPerFullScale > nominalPaPerFullScale;
switch lower(string(config.output.wavClippingPolicy))
    case "error"
        if scaleExceeded
            requiredSPLdB=20*log10(requiredPaPerFullScale/referencePressurePa);
            error('acoustics:WavFullScaleExceeded', ...
                ['Peak pressure exceeds the fixed dataset WAV scale. Set ' ...
                 'output.fullScaleSPLdB to at least %.3f dB SPL or explicitly ' ...
                 'choose wavClippingPolicy="adaptive_shared".'],requiredSPLdB);
        end
        paPerFullScale=nominalPaPerFullScale;
        adaptiveScaleUsed=false;
    case "adaptive_shared"
        paPerFullScale=max(nominalPaPerFullScale,requiredPaPerFullScale);
        adaptiveScaleUsed=scaleExceeded;
end

audioFiles = struct();
if config.output.writeComponentWav
    wavMap = {
        'directPa',     'direct';
        'reflectedPa',  'reflected';
        'diffractedPa', 'diffracted';
        'finalPa',      'final'};
    for k = 1:size(wavMap, 1)
        field = wavMap{k, 1};
        suffix = wavMap{k, 2};
        if ~isfield(results.signals, field), continue; end
        filename = fullfile(audioDirectory, sprintf('%s_%s.wav', simulationId, suffix));
        digitalSignal = results.signals.(field) / paPerFullScale;
        if any(abs(digitalSignal) > 1 + 10*eps, 'all')
            error('acoustics:InternalWavScaleError', ...
                'Shared WAV scale failed to prevent clipping for %s.', field);
        end
        audiowrite(filename, digitalSignal, results.sampleRateHz, ...
            'BitsPerSample', config.output.wavBitsPerSample, ...
            'Title', sprintf('%s %s', simulationId, suffix), ...
            'Comment', sprintf('PaPerFullScale=%.17g', paPerFullScale));
        audioFiles.(suffix) = filename;
    end
end

output.directory = simulationDirectory;
output.audioDirectory = audioDirectory;
output.figureDirectory = figureDirectory;
output.audioFiles = audioFiles;
output.nominalPaPerFullScale = nominalPaPerFullScale;
output.paPerFullScale = paPerFullScale;
output.adaptiveScaleUsed = adaptiveScaleUsed;
output.peakPa = peakPa;
output.clippingHeadroom = config.output.clippingHeadroom;
output.wavClippingPolicy = config.output.wavClippingPolicy;
output.matFile = fullfile(simulationDirectory, sprintf('%s_physical_results.mat', simulationId));
output.excelFile = fullfile(simulationDirectory, sprintf('%s_metadata.xlsx', simulationId));
output.figureFiles = struct();

results.output = output;
results.config = config;

if config.output.writeMat
    save(output.matFile, 'results', '-v7.3');
end
end
