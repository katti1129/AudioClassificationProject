clear; clc;

%% Accelerated Doppler simulation for a real audio file
input_file = '../data/input/ambulance.wav';
[input_signal, fs_in] = audioread(input_file);

target_fs = 16000;
if fs_in ~= target_fs
    input_signal = resample(input_signal, target_fs, fs_in);
end
fs = target_fs;

if size(input_signal, 2) > 1
    input_signal = mean(input_signal, 2);
end

duration = length(input_signal) / fs;
t = (0:1/fs:duration-1/fs)';
t_in = t;

%% Physical and motion parameters
c = 343;                        % Speed of sound [m/s]
d0 = 1.0;                       % Reference distance for attenuation [m]

% Source motion.
% The source passes x = 0 at t_cross. v_cross is the speed at that moment.
t_cross = duration / 2;
v_cross = 60 * 1000 / 3600;     % [m/s] 60 km/h
accel = 3.0;                    % [m/s^2] positive value accelerates in +x

% Geometry
mic_pos = [0, 10, 1.2];         % Microphone position [x, y, z] [m]
y_source = 0;
z_source = 1.5;

%% Retarded-time calculation
% Received sound at time t was emitted at tau.
% tau satisfies: t = tau + distance(source(tau), mic) / c.
tau = t;
for k = 1:8
    [~, distance_tau] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos);
    tau = t - distance_tau / c;
end

[source_pos, distance] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos);
attenuation = d0 ./ max(distance, 1e-6);

%% Waveform resampling and output
doppler_signal = interp1(t_in, input_signal, tau, 'linear', 0);
output_signal = attenuation .* doppler_signal;

peak = max(abs(output_signal));
if peak > 0
    output_signal = 0.99 * output_signal / peak;
end

audiowrite('../data/output/doppler_accelerated_ambulance_direct.wav', output_signal, fs);

%% Visualization
velocity_x = v_cross + accel * (tau - t_cross);

figure('Name', 'Accelerated Doppler Simulation (Direct Sound)', 'Position', [100, 100, 850, 900]);

subplot(4, 1, 1);
plot(t, source_pos(:,1), 'LineWidth', 1.3);
title('Source x position');
xlabel('Time [s]'); ylabel('x [m]'); grid on;

subplot(4, 1, 2);
plot(t, velocity_x, 'LineWidth', 1.3);
title('Source velocity');
xlabel('Time [s]'); ylabel('v_x [m/s]'); grid on;

subplot(4, 1, 3);
plot(t, distance, 'LineWidth', 1.3);
title('Distance from source to microphone');
xlabel('Time [s]'); ylabel('Distance [m]'); grid on;

subplot(4, 1, 4);
spectrogram(output_signal, 2048, 2000, 2048, fs, 'yaxis');
title('Spectrogram');
colormap jet;
ylim([0.5, 1.5]);

function [source_pos, distance] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos)
    x = v_cross .* (tau - t_cross) + 0.5 .* accel .* (tau - t_cross).^2;
    source_pos = [x, y_source .* ones(size(tau)), z_source .* ones(size(tau))];
    delta = source_pos - mic_pos;
    distance = sqrt(sum(delta.^2, 2));
end
