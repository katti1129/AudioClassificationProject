function config = background_simulation_config()
%BACKGROUND_SIMULATION_CONFIG Defaults for existing Doppler + background mix.
% Input: none. Output: config with unchanged siren physics and mix settings.
config = moving_receiver_rms_config();
root = fileparts(fileparts(mfilename('fullpath')));
config.outputRoot = fullfile(root,'data','output','doppler_background');
config.background.enabled = true;
config.background.file = fullfile(root,'data','background_audio', ...
    'UrbanSound8K','engine_idling','fold10','102857-5-0-0.wav');
config.background.sourceStartSec = 0;   % Offset in background WAV after resampling [s]
config.background.timeReference = 'cpa'; % 'start' (receiver timeline) or 'cpa'
config.background.startOffsetSec = -2; % Relative to the selected time reference [s]
config.background.durationSec = 4;     % Half-open inserted interval [start,end) [s]
config.background.mode = 'fixed_rms';  % 'fixed_rms' or 'snr'
config.background.splDb = 80;          % Unweighted RMS SPL at receiver; assumed [dB]
config.background.snrDb = 0;           % Used only by mode='snr'; interval RMS ratio [dB]
config.background.fadeSec = 0.02;      % Raised-cosine edit fade at both ends [s]; 0 disables
% No looping or random selection: short files/out-of-range insertion raise errors.
end
