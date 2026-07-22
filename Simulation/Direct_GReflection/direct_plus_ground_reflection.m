%距離計算、遅延、簡易減衰、地面反射(鏡像法)

%% acoustic_sim_step2_ground_reflection.m

clear; clc;

%% パラメータ
fs = 16000;          % サンプリング周波数
c = 343;             % 音速 [m/s]
reflection_coef = 0.7; % 反射係数

%% 座標設定 [x, y, z]
source = [1.0, 1.0, 1.5];      % 音源位置
mic    = [5, 2, 1.5];      % マイク位置

%% 音源（テスト用）
t = 0:1/fs:0.01;     
input_signal = sin(2*pi*1000*t)';  % 1kHz。転置を実施している

%% ========= ① 直接音 =========
%距離計算
distance = norm(source - mic);

%% 遅延計算
delay_time = distance / c;
delay_direct = round(delay_time * fs);

%減衰計算
attenuation = 1 / distance;

%遅延信号生成
direct_signal = [zeros(delay_direct, 1); attenuation * input_signal];

%% ========= ② 反射音（鏡像法） =========
% 鏡像音源（z反転）
image_source = [source(1), source(2), -source(3)];

% 距離計算
dist_reflect = norm(image_source - mic);

% 遅延計算
dealy_time_dist = dist_reflect / c;
delay_reflect = round(dealy_time_dist * fs);

% 減衰（距離＋反射係数）
atten_reflect = (1 / dist_reflect) * reflection_coef;

reflect_signal = [zeros(delay_reflect,1); atten_reflect * input_signal];

%% ========= ③ 信号合成 =========
max_len = max(length(direct_signal), length(reflect_signal));

direct_signal(end+1:max_len) = 0;
reflect_signal(end+1:max_len) = 0;

mic_signal = direct_signal + reflect_signal;

%% ========= ④ プロット =========
time = (0:length(mic_signal)-1) / fs;

figure;
subplot(2,1,1);
plot(t, input_signal);
xlim([0 0.03])
ylim([-1.1 1.1])
title('入力信号（音源）');
xlabel('Time [s]');
ylabel('Amplitude');

subplot(2,1,2);
plot(time, mic_signal);
xlabel('Time [s]');
ylabel('Amplitude');
title('Direct + Ground Reflection');
xlim([0 0.03]); % 見やすく
ylim([-1.1 1.1])
exportgraphics(gcf, './form/sin_groundreflection_waveform.png', 'Resolution', 300);

%% ========= 距離・遅延用デバック =========
%直接音
fprintf('距離: %.2f m\n', distance);
fprintf('遅延: %.5f 秒（%d サンプル）\n', delay_time, delay_direct);
fprintf('減衰: %.5f\n', attenuation);

%反射音
fprintf('距離: %.2f m\n', dist_reflect);
fprintf('遅延: %.5f 秒（%d サンプル）\n', dealy_time_dist, delay_reflect);
fprintf('減衰: %.5f\n', atten_reflect);
%fprintf(reflect_signal);