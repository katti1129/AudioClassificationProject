clear; clc; close all;

%% Basic parameters
fs = 16000;
c = 343;
f_tone = 1000;
duration = 0.08;

%% Geometry: 2D vertical slice, using [x, z]
source = [0.0, 1.5];
mic = [50.0, 1.2];

obstacle_x = 22.0;
obstacle_height = 10.0;
obstacle_width = 1.0;

%% Input signal
t = (0:1/fs:duration).';
input_signal = sin(2*pi*f_tone*t);

%% Direct path
d_direct = norm(mic - source);
delay_direct = d_direct / c;
gain_direct = 1 / d_direct;

% Height of the line-of-sight path at the obstacle position.
alpha = (obstacle_x - source(1)) / (mic(1) - source(1));
z_los_at_obstacle = source(2) + alpha * (mic(2) - source(2));

is_between_source_and_mic = alpha > 0 && alpha < 1;
is_blocked = is_between_source_and_mic && obstacle_height > z_los_at_obstacle;

%% Knife-edge diffraction over the obstacle top
Q = [obstacle_x, obstacle_height];

d1 = norm(Q - source);
d2 = norm(mic - Q);
d_diff = d1 + d2;
delay_diff = d_diff / c;

lambda = c / f_tone;
h = obstacle_height - z_los_at_obstacle;

% Fresnel-Kirchhoff knife-edge parameter.
% h > 0 means the edge intrudes into the line-of-sight path.
v = h * sqrt((2 / lambda) * (1 / d1 + 1 / d2));

if v <= -0.78
    diffraction_loss_dB = 0;
else
    diffraction_loss_dB = 6.9 + 20*log10(sqrt((v - 0.1)^2 + 1) + v - 0.1);
end

diffraction_gain = 10^(-diffraction_loss_dB / 20);
gain_diff = (1 / d_diff) * diffraction_gain;

%% Generate delayed signals
delay_direct_samples = round(delay_direct * fs);
delay_diff_samples = round(delay_diff * fs);

direct_signal = [zeros(delay_direct_samples, 1); gain_direct * input_signal];
diff_signal = [zeros(delay_diff_samples, 1); gain_diff * input_signal];

% If the direct line is blocked, remove the direct path and keep diffraction.
if is_blocked
    direct_signal(:) = 0;
end

max_len = max(length(direct_signal), length(diff_signal));
direct_signal(end+1:max_len, 1) = 0;
diff_signal(end+1:max_len, 1) = 0;

mic_signal = direct_signal + diff_signal;
time_out = (0:length(mic_signal)-1).' / fs;

%% Normalize only for listening and plotting
plot_signal = mic_signal;
if max(abs(plot_signal)) > 0
    plot_signal = plot_signal / max(abs(plot_signal));
end

%% Save audio
if ~exist("data/output", "dir")
    mkdir("data/output");
end
audiowrite("data/output/sin_single_obstacle_diffraction.wav", plot_signal, fs);

%% Plot waveform
figure("Name", "Single Obstacle Diffraction - Sine Wave");

subplot(3,1,1);
plot(t, input_signal, "k");
grid on;
xlabel("Time [s]");
ylabel("Amplitude");
title("Input sine wave");

subplot(3,1,2);
plot(time_out, direct_signal, "b"); hold on;
plot(time_out, diff_signal, "r");
grid on;
xlabel("Time [s]");
ylabel("Amplitude");
legend("Direct path", "Diffracted path");
title("Direct and diffracted components");

subplot(3,1,3);
plot(time_out, plot_signal, "k");
grid on;
xlabel("Time [s]");
ylabel("Normalized amplitude");
title("Microphone signal");

%% Plot geometry
figure("Name", "Geometry");
hold on; grid on; axis equal;
plot(source(1), source(2), "ro", "MarkerFaceColor", "r");
plot(mic(1), mic(2), "bo", "MarkerFaceColor", "b");
plot([source(1), mic(1)], [source(2), mic(2)], "k--");

rectangle( ...
    "Position", ...
    [obstacle_x - obstacle_width/2, 0, obstacle_width, obstacle_height], ...
    "FaceColor", [0.4 0.4 0.4], ...
    "EdgeColor", "k");

plot([source(1), Q(1), mic(1)], [source(2), Q(2), mic(2)], "r-", "LineWidth", 1.5);
plot(Q(1), Q(2), "rx", "MarkerSize", 10, "LineWidth", 2);

xlabel("x [m]");
ylabel("z [m]");
legend("Source", "Mic", "Line of sight", "Obstacle", "Diffraction path", "Diffraction point");
title("Single knife-edge diffraction model");
xlim([-2, mic(1)+2]);
ylim([0, max(obstacle_height, source(2)) + 2]);

%% Print summary
fprintf("=== Single obstacle diffraction simulation ===\n");
fprintf("Tone frequency          : %.1f Hz\n", f_tone);
fprintf("Direct distance         : %.3f m\n", d_direct);
fprintf("Direct delay            : %.6f s (%d samples)\n", delay_direct, delay_direct_samples);
fprintf("Line-of-sight height    : %.3f m at obstacle\n", z_los_at_obstacle);
fprintf("Obstacle height         : %.3f m\n", obstacle_height);
fprintf("Direct path blocked     : %d\n", is_blocked);
fprintf("Diffraction path length : %.3f m\n", d_diff);
fprintf("Diffraction delay       : %.6f s (%d samples)\n", delay_diff, delay_diff_samples);
fprintf("Knife-edge v            : %.3f\n", v);
fprintf("Diffraction loss        : %.3f dB\n", diffraction_loss_dB);
fprintf("Output file             : data/output/sin_single_obstacle_diffraction.wav\n");
