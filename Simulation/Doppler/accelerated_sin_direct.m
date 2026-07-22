clear; clc;

%% Accelerated Doppler simulation for a pure tone
fs = 16000;             % Sampling frequency [Hz]
c = 343;                % Speed of sound [m/s]
f0 = 1000;              % Source frequency [Hz]
duration = 6.0;         % Simulation time [s]
t = (0:1/fs:duration-1/fs)';

% Source motion.
% The source passes x = 0 at t_cross. v_cross is the speed at that moment.
t_cross = duration / 2;
v_cross = 60 * 1000 / 3600;   % [m/s] 60 km/h
accel = 3.0;                  % [m/s^2] positive value accelerates in +x

% Geometry
mic_pos = [0, 10, 1.2];       % Microphone position [x, y, z] [m]
y_source = 0;
z_source = 1.5;

% Estimate the emission time tau for each observation time t.
% It satisfies: t = tau + distance(source(tau), mic) / c.
tau = t;
for k = 1:8
    [~, distance_tau] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos);
    tau = t - distance_tau / c;
end

[source_pos, distance] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos);
attenuation = 1 ./ max(distance, 1e-6);

% Received signal. The phase is based on the emission time tau.
mic_signal = attenuation .* sin(2 * pi * f0 * tau);
mic_signal = mic_signal / max(abs(mic_signal));

% Useful diagnostic values
velocity_x = v_cross + accel * (tau - t_cross);
relative_pos = source_pos - mic_pos;
radial_velocity = sum([velocity_x, zeros(size(velocity_x)), zeros(size(velocity_x))] .* relative_pos, 2) ./ distance;
observed_frequency = f0 ./ (1 + radial_velocity / c);

figure('Name', 'Accelerated Doppler Simulation (Pure Tone)', 'Position', [100, 100, 850, 900]);

subplot(4, 1, 1);
plot(t, source_pos(:,1), 'LineWidth', 1.3);
title('Source x position');
xlabel('Time [s]'); ylabel('x [m]'); grid on;

subplot(4, 1, 2);
plot(t, velocity_x, 'LineWidth', 1.3);
title('Source velocity');
xlabel('Time [s]'); ylabel('v_x [m/s]'); grid on;

subplot(4, 1, 3);
plot(t, observed_frequency, 'LineWidth', 1.3);
title('Estimated observed frequency');
xlabel('Time [s]'); ylabel('Frequency [Hz]'); grid on;

subplot(4, 1, 4);
spectrogram(mic_signal, 512, 480, 1024, fs, 'yaxis');
title('Spectrogram');
colormap jet;

audiowrite('../data/output/doppler_accelerated_sin_direct.wav', mic_signal, fs);

function [source_pos, distance] = sourceTrajectory(tau, t_cross, v_cross, accel, y_source, z_source, mic_pos)
    x = v_cross .* (tau - t_cross) + 0.5 .* accel .* (tau - t_cross).^2;
    source_pos = [x, y_source .* ones(size(tau)), z_source .* ones(size(tau))];
    delta = source_pos - mic_pos;
    distance = sqrt(sum(delta.^2, 2));
end
