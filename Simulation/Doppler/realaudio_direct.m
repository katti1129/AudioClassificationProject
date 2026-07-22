clear; clc;

%% 1. wavファイル読み込みとリサンプリング
input_file = '../data/input/ambulance.wav'; 
[input_signal, fs_in] = audioread(input_file);

target_fs = 16000; % ★ AIモデルの学習に用いたサンプリング周波数に設定 ★

% 入力音源のサンプリング周波数がターゲットと異なる場合、リサンプリングを実行
if fs_in ~= target_fs
    disp(['サンプリング周波数を ', num2str(fs_in), ' Hz から ', num2str(target_fs), ' Hz に変換します...']);
    input_signal = resample(input_signal, target_fs, fs_in);
end

fs = target_fs; % 以降のシミュレーションはこの fs で計算される

%% モノラル化（ステレオの場合）
if size(input_signal, 2) > 1
    input_signal = mean(input_signal, 2);
end

%% 2. 時間軸の作成とパラメータ設定
c = 343;                              % 音速 [m/s]
v = 60 * 1000 / 3600; % 約16.67 m/s (60km/h)                              
duration = length(input_signal) / fs; % 音源の長さ [秒]

% マイクでの観測時間軸（縦ベクトルとして作成）
t = (0:1/fs:duration-1/fs)';          

%% 3. 音源とマイクの動的位置設定（3D）
% マイク位置（固定）
mic_pos = [0, 10, 1.2]; 

% 音源位置（x軸上を -20m からスタートして速度vで移動、y軸方向に2mの距離）
x_pos = v * (t - duration/2);
y_pos = 0 * zeros(size(t));% 全ての時間ステップにおいて、音源の y座標を 10 にする。
z_pos = 1.5 * ones(size(t));% 全ての時間ステップにおいて、音源の z座標を 0 にする。
source_pos = [x_pos, y_pos, z_pos]; % [サンプル数 × 3] の行列

%% 4. 距離と到達遅延の動的計算
% 各時刻におけるマイクと音源の距離を計算（ピタゴラスの定理）
distance = sqrt((source_pos(:,1) - mic_pos(1)).^2 + ...
                (source_pos(:,2) - mic_pos(2)).^2 + ...
                (source_pos(:,3) - mic_pos(3)).^2);

delay_time = distance / c;            % 到達遅延時間 [秒] (時間変化する配列)

% 距離減衰（逆距離則）
attenuation = 1 ./ distance;          % (時間変化する配列)

%% 5. ドップラー効果の付与（波形のリサンプリング）
% 観測時刻 t において、参照すべき「過去の音源の時刻」
t_req = t - delay_time;

% 元の音声データの時間軸
t_in = (0:length(input_signal)-1)' / fs;

% 【ここがドップラーの正体】 interp1で t_req のタイミングの振幅値を補間して取得
% 範囲外（まだ音が届いていない時など）は 0 で埋める（'extrap'を0にする）
doppler_signal = interp1(t_in, input_signal, t_req, 'linear', 0);

%% 6. 減衰適用と正規化
output_signal = attenuation .* doppler_signal;
%output_signal = output_signal * 50;

% 音割れを防ぐために正規化（最大振幅を1にする）
%output_signal = output_signal / max(abs(output_signal));AI評価にあたっては正規化しないほうがいい

%% 7. 音声の保存・可視化
% 出力ファイルの保存
audiowrite('../data/output/doppler_ambulance_output_1.wav', output_signal, fs);

% 結果の可視化
% --- 元音源の振幅チェック ---
max_amp = max(abs(input_signal));
fprintf('元音源の最大振幅: %f\n', max_amp);

figure;
subplot(4, 1, 1);
plot(t, input_signal, 'k');
title('もとの波形（直接音）');
xlabel('時間 [s]'); ylabel('振幅');
grid on;

subplot(4,1,2);
plot(t, distance);
title('音源とマイクの距離推移'); xlabel('時間 [s]'); ylabel('距離 [m]');


% --- (2) 合成波形 ---
subplot(4, 1, 3);
plot(t, output_signal, 'k');
title('観測された波形（直接音）');
xlabel('時間 [s]'); ylabel('振幅');
grid on;

subplot(4,1,4);
spectrogram(output_signal, 256, 250, 256, fs, 'yaxis');
title('ドップラーシフトと減衰の確認（スペクトログラム）');
colormap jet;




% サブプロット下段：スペクトログラム
%subplot(3,1,3);

% 【修正1】窓サイズ(NFFT)を 256 から 1024 または 2048 に増やして、周波数を細かく見る
%nfft = 2048; 
%window = 2048;
%noverlap = 2000; % 重なりを増やして時間を滑らかに
%spectrogram(output_signal, window, noverlap, nfft, fs, 'yaxis');

% 【修正2】Y軸の表示範囲を、サイレンの音（770Hzと960Hz）がある帯域だけにズームする
% ※ spectrogramのY軸は kHz 単位で表示されるため、0.5kHz～1.5kHz に制限
%ylim([0.5, 1.5]); 

%title('ドップラーシフト（500Hz〜1500Hz拡大）');
%colormap jet;

% 再生（MATLAB上で音を聞く場合）
% sound(output_signal, fs);