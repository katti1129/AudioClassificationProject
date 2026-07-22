%距離計算、遅延、簡易減衰
clear; clc;

%% パラメータ設定
fs = 16000;              % サンプリング周波数 [Hz]
c = 343;                 % 音速 [m/s]

%% 音源とマイク位置（3D）
source_pos = [1.0, 1.0, 1.5];      % 音源位置
mic_pos    = [5, 2, 1.5];      % マイク位置

%% 距離計算
distance = norm(source_pos - mic_pos);

%% 遅延計算
delay_time = distance / c;           % 秒
delay_samples = round(delay_time * fs);

%% 減衰（逆距離）
attenuation = 1 / distance;

%% 入力信号（テスト用：正弦波）
t = 0:1/fs:0.01;   % 0.01秒
f = 1000;       % 周波数 [Hz]
input_signal = sin(2 * pi * f * t); %sin波が横ベクトル出力[0, 0, 0]


%% 遅延信号生成
output_signal = [zeros(1, delay_samples), attenuation * input_signal];

%% 時間軸調整
t_out = (0:length(output_signal)-1) / fs;

%% プロット
figure;
subplot(2,1,1);
plot(t, input_signal);
xlim([0 0.03])
ylim([-1.1 1.1])
title('入力信号（音源）');
xlabel('Time [s]');
ylabel('Amplitude');

subplot(2,1,2);
plot(t_out, output_signal);
xlim([0 0.03])
ylim([-1.1 1.1])
title('出力信号（マイク）');
xlabel('Time [s]');
ylabel('Amplitude');
exportgraphics(gcf, './form/sin_waveform.png', 'Resolution', 300);

%% 距離・遅延表示
fprintf('距離: %.2f m\n', distance);
fprintf('遅延: %.5f 秒（%d サンプル）\n', delay_time, delay_samples);
fprintf('減衰: %.5f\n', attenuation);
