clear; clc;

%% パラメータ設定
fs = 16000;              % サンプリング周波数 [Hz]
c = 343;                 % 音速 [m/s]

%% 音源とマイク位置（3D）
source_pos = [0, 0, 0];      % 音源位置
mic_pos    = [5, 0, 0];      % マイク位置

%% 距離計算
distance = norm(source_pos - mic_pos);

%% 遅延計算
delay_time = distance / c;           % 秒
delay_samples = round(delay_time * fs);

%% 減衰（逆距離）
attenuation = 1 / distance;

%% wavファイル読み込み
[input_signal, fs] = audioread('./data/input/Ambulance-Siren01-2.wav');

%% モノラル化（必要なら）
% mean関数 : 行の平均: mean(A, 2) は、行列 A の各行の平均を含む列ベクトルを返します。
input_signal = mean(input_signal, 2);

%% 遅延付加。zerosで縦ベクトルに0を並べて、input_signalを縦結合。
delayed_signal = [zeros(delay_samples,1); input_signal];

%% 長さ調整。fs = 16000に揃える
delayed_signal = delayed_signal(1:length(input_signal));

%% 減衰適用
output_signal = attenuation * delayed_signal;

%% 正規化
%正規化とは最大値を1に揃える処理。
%つまり：一番大きい部分を基準に拡大しています。
%output_signal = output_signal / max(abs(output_signal));

%%時間に変換
t = (0:length(input_signal)-1) / fs;
t_out = (0:length(output_signal)-1) / fs;

%% 再生
%%sound(output_signal, fs);

%% 保存
audiowrite('.data/output/output.wav', output_signal, fs);

%% グラフプロット
figure;
subplot(2,1,1);
plot(t, input_signal);
xlim([0 0.05])
ylim([-0.1 0.1])
title('入力信号（音源）');
xlabel('Time [s]');
ylabel('Amplitude');

subplot(2,1,2);
plot(t_out, output_signal);
xlim([0 0.05])
ylim([-0.1 0.1])
title('出力信号（マイク）');
xlabel('Time [s]');
ylabel('Amplitude');

%% 距離・遅延デバック表示
fprintf('距離: %.2f m\n', distance);
fprintf('遅延: %.5f 秒（%d サンプル）\n', delay_time, delay_samples);
fprintf('減衰: %.5f\n', attenuation);



