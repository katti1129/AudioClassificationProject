%距離計算、遅延、簡易減衰、地面反射(鏡像法)，壁反射
%% acoustic_sim_step3_multi_reflection.m
clear; clc;

%% パラメータ
fs = 16000;
c = 343;
reflection_coef = 0.8;

%% テスト信号
t = 0:1/fs:0.01;
input_signal = sin(2*pi*1000*t)';

%% 座標 [x, y, z]
source = [1.0, 1.0, 1.5];      % 音源位置
mic    = [5.0, 2.0, 1.5];      % マイク位置

%% ========= ① 直接音 =========
dist_direct = norm(source - mic);
delay_direct = round((dist_direct / c) * fs);
atten_direct = 1 / dist_direct;

direct_signal = [zeros(delay_direct,1); atten_direct * input_signal];

%% ========= ② 鏡像音源（複数） =========
image_sources = [];

% 地面（z=0）
image_sources = [image_sources;
    source(1), source(2), -source(3)];

% 左壁（x=0）
image_sources = [image_sources;
    -source(1), source(2), source(3)];

% 奥壁（y=0）
image_sources = [image_sources;
    source(1), -source(2), source(3)];

%% ========= ③ 各反射音を計算 =========
reflect_signal_total =[];
count = 0;

for i = 1:size(image_sources,1)%%size(image_sources, 1) → 行の数（今回は 3）

    img = image_sources(i,:);

    % 距離
    d = norm(img - mic);

    % 遅延
    delay = round((d / c) * fs);

    % 減衰
    atten = (1 / d) * reflection_coef;

    % 信号生成
    sig = [zeros(delay,1); atten * input_signal];

    % 初回のループ処理用
    if isempty(reflect_signal_total)
        % 1回目は代入するだけ
        reflect_signal_total = sig;
    else
        % 2回目以降は長さを揃えて足す
        
        % 長さ合わせ（縦ベクトル同士として処理）
        max_len = max(length(reflect_signal_total), length(sig));
        
        % ここで「縦」であることを維持して拡張
        reflect_signal_total(end+1:max_len, 1) = 0; 
        sig(end+1:max_len, 1) = 0;
    
        % 加算
        reflect_signal_total = reflect_signal_total + sig;
    end

    %反射音
    count = count + 1;               % 1. まずカウントを増やす
    fprintf('反射音 %d 回目\n', count); % 2. %d を使って表示する
    fprintf('距離: %.2f m\n', d);
    fprintf('遅延: %.5f 秒（%d サンプル）\n', d / c, delay);
    fprintf('減衰: %.5f\n', atten);
end

%% ========= ④ 直接音と合成 =========
max_len = max(length(direct_signal), length(reflect_signal_total));

direct_signal(end+1:max_len) = 0;
reflect_signal_total(end+1:max_len) = 0;

mic_signal = direct_signal + reflect_signal_total;

%% ========= ⑤ 可視化 =========
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
xlim([0 0.03])
ylim([-1.1 1.1])
xlabel('Time [s]');
ylabel('Amplitude');
title('Multi Reflection (Ground + Walls)');
%xlim([0 0.03]);

exportgraphics(gcf, './form/sin_ground_wall_reflection_waveform.png', 'Resolution', 300);

%% ========= 距離・遅延用デバック =========
%直接音
fprintf('直接音\n');
fprintf('距離: %.2f m\n', dist_direct);
fprintf('遅延: %.5f 秒（%d サンプル）\n', dist_direct / c, delay_direct);
fprintf('減衰: %.5f\n', atten_direct);

%反射音
%fprintf('距離: %.2f m\n', d);
%fprintf('遅延: %.5f 秒（%d サンプル）\n', d / c, delay);
%fprintf('減衰: %.5f\n', atten);
%fprintf(reflect_signal);