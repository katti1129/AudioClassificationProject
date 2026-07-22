clear; clc;

%% 1. Read audio and convert it to physical sound pressure [Pa]
input_file = '../data/input/ambulance.wav';
[input_signal, fs] = audioread(input_file);

if size(input_signal, 2) > 1
    input_signal = mean(input_signal, 2);
end

signal_norm = input_signal / max(abs(input_signal));

% Reference sound pressure.
% 110 dB SPL at 20 m is almost equivalent to 136 dB SPL at 1 m
% when spherical spreading is assumed.
P0 = 2e-5;                  % Reference pressure [Pa]
SPL_20m = 110;              % Sound pressure level at 20 m [dB SPL]
P_20m = P0 * 10^(SPL_20m / 20);

signal_pa = signal_norm * P_20m;

duration = length(input_signal) / fs;
t = (0:1/fs:duration-1/fs)';
t_in = t;

%% Physical and motion parameters
c = 343;                        % Speed of sound [m/s]
d_ref = 20.0;                   % Reference distance for P_20m [m]
ref_coeff = 0.8;                % Ground reflection coefficient

% Source motion.
% The source passes x = 0 at t_cross. v_cross is the speed at that moment.
t_cross = duration / 2;
v_cross = 60 * 1000 / 3600;     % [m/s] 60 km/h
accel = 3.0;                    % [m/s^2] positive value accelerates in +x

% Geometry
z_source = 1.5;
z_mic = 1.2;
mic_pos = [0, 10, z_mic];       % Microphone position [x, y, z] [m]
y_source = 0;

%% Direct sound
tau_dir = t;
for k = 1:8
    [~, dist_dir] = sourceTrajectory(tau_dir, t_cross, v_cross, accel, y_source, z_source, mic_pos);
    tau_dir = t - dist_dir / c;
end
[source_pos_dir, dist_dir] = sourceTrajectory(tau_dir, t_cross, v_cross, accel, y_source, z_source, mic_pos);
signal_dir_pa = interp1(t_in, signal_pa, tau_dir, 'linear', 0);
output_dir_pa = signal_dir_pa .* (d_ref ./ max(dist_dir, 1e-6));

%% Ground reflection by image source method
tau_ref = t;
z_image_source = -z_source;
for k = 1:8
    [~, dist_ref] = sourceTrajectory(tau_ref, t_cross, v_cross, accel, y_source, z_image_source, mic_pos);
    tau_ref = t - dist_ref / c;
end
[~, dist_ref] = sourceTrajectory(tau_ref, t_cross, v_cross, accel, y_source, z_image_source, mic_pos);
signal_ref_pa = interp1(t_in, signal_pa, tau_ref, 'linear', 0);
output_ref_pa = ref_coeff .* signal_ref_pa .* (d_ref ./ max(dist_ref, 1e-6));

%% Output
final_output_pa = output_dir_pa + output_ref_pa;

% Convert Pa back to digital amplitude for WAV output.
% This keeps the same mapping as the reference: P_20m corresponds to 1.0.
final_saved_audio = final_output_pa / P_20m;

audiowrite('../data/output/doppler_accelerated_ambulance_Greflection_pa20m.wav', final_saved_audio, fs);

%% Visualization
velocity_x = v_cross + accel * (tau_dir - t_cross);

figure('Name', 'Accelerated Doppler Simulation (Direct + Ground Reflection)', 'Position', [100, 100, 850, 900]);

subplot(4, 1, 1);
plot(t, source_pos_dir(:,1), 'LineWidth', 1.3);
title('Source x position');
xlabel('Time [s]'); ylabel('x [m]'); grid on;

subplot(4, 1, 2);
plot(t, velocity_x, 'LineWidth', 1.3);
title('Source velocity');
xlabel('Time [s]'); ylabel('v_x [m/s]'); grid on;

subplot(4, 1, 3);
plot(t, dist_dir, 'b', 'LineWidth', 1.3); hold on;
plot(t, dist_ref, 'r--', 'LineWidth', 1.3);
yline(d_ref, 'k--', '20 m reference', 'LabelHorizontalAlignment', 'left');
title('Propagation distance');
xlabel('Time [s]'); ylabel('Distance [m]');
legend('Direct', 'Ground reflection'); grid on;

subplot(4, 1, 4);
spectrogram(final_saved_audio, 2048, 2000, 2048, fs, 'yaxis');
title('Spectrogram');
colormap jet;
ylim([0.5, 1.5]);

figure('Name', 'Accelerated Doppler Physical Sound Pressure', 'Position', [980, 100, 850, 650]);

subplot(2, 1, 1);
plot(t, final_output_pa, 'k');
title('Observed sound pressure [Pa]');
xlabel('Time [s]'); ylabel('Sound pressure [Pa]'); grid on;

window_size = round(fs * 0.05);
envelope_pa = movmax(abs(final_output_pa), window_size);
SPL_dB_time = 20 * log10(max(envelope_pa, eps) / P0);

subplot(2, 1, 2);
plot(t, SPL_dB_time, 'g', 'LineWidth', 1.3); hold on;
yline(SPL_20m, 'k--', '110 dB SPL at 20 m', 'LabelHorizontalAlignment', 'left');
title('Observed sound pressure level [dB SPL]');
xlabel('Time [s]'); ylabel('dB SPL'); grid on;

function [source_pos, distance] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos)
    x = v_cross .* (tau - t_cross) + 0.5 .* accel .* (tau - t_cross).^2;
    source_pos = [x, y_source .* ones(size(tau)), z_source .* ones(size(tau))];
    delta = source_pos - mic_pos;
    distance = sqrt(sum(delta.^2, 2));
end
