clear; clc;

%% 1. wavファイル読み込み、リサンプリング、物理音圧(Pa)への変換
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

% 【最重要】元のWAVの音量に依存しないよう、最大振幅を1.0に揃える。
% これにより、「この音源の最大出力（振幅1.0）＝ 1m地点での136dB SPL」という絶対基準が成立します。
input_signal = input_signal / max(abs(input_signal));

% 1m地点での目標音圧レベル (136 dB SPL) を物理単位「パスカル(Pa)」に変換【物理的保証】
P0 = 2e-5; % 基準音圧 20 μPa
SPL_1m = 136;
P_1m = P0 * 10^(SPL_1m / 20); % 約 126.19 Pa

% 波形データを無次元から「パスカル(Pa)」単位に変換
signal_pa = input_signal * P_1m;

%% 2. 時間軸の作成とパラメータ設定
c = 343;                              % 音速 [m/s]
v = 60 * 1000 / 3600; % 約16.67 m/s (60km/h)                               
duration = length(signal_pa) / fs; % 音源の長さ [秒]

% マイクでの観測時間軸（縦ベクトルとして作成）
t = (0:1/fs:duration-1/fs)';          

%% 3. 音源とマイクの動的位置設定（3D）
% マイク位置（固定） ※タイポ [1,2] を [1.2] に修正
mic_pos = [0, 10, 1.2]; 

% 音源位置（x軸上を移動、y軸方向に10mの距離、z軸方向は1.5m固定）
x_pos = v * (t - duration/2);
y_pos = zeros(size(t));
z_pos = 1.5 * ones(size(t));
source_pos = [x_pos, y_pos, z_pos]; % [サンプル数 × 3] の行列

%% 4. 距離と到達遅延の動的計算
% 各時刻におけるマイクと音源の距離を計算（ピタゴラスの定理）
distance = sqrt((source_pos(:,1) - mic_pos(1)).^2 + ...
                (source_pos(:,2) - mic_pos(2)).^2 + ...
                (source_pos(:,3) - mic_pos(3)).^2);

delay_time = distance / c;            % 到達遅延時間 [秒]

% 基準距離 d0 = 1.0m とした逆距離則による減衰係数
d0 = 1.0;
attenuation = d0 ./ distance;          

%% 5. ドップラー効果の付与（波形のリサンプリング）
% 観測時刻 t において、参照すべき「過去の音源の時刻」
t_req = t - delay_time;

% 元の音声データの時間軸
t_in = (0:length(signal_pa)-1)' / fs;

% interp1で t_req のタイミングの物理音圧(Pa)を補間して取得
doppler_signal_pa = interp1(t_in, signal_pa, t_req, 'linear', 0);

%% 6. 減衰適用（パスカル空間での物理計算）
output_signal_pa = attenuation .* doppler_signal_pa;

%% 7. WAVファイルへの書き出し（デジタル振幅への再変換）
% 136 dB SPL (約126.19 Pa) をデジタル振幅の 1.0 とするマッピングルールを適用。
% 固定ゲイン掛けや出力正規化（maxでの割り算）はAIの評価を歪めるため行いません。
final_saved_audio = output_signal_pa / P_1m;

% 出力ファイルの保存
audiowrite('../data/output/doppler_ambulance_pure_pa.wav', final_saved_audio, fs);

%% 8. 結果の可視化（物理変化を追う4段グラフに整理）
figure('Name', 'Doppler Strict Physical Scale (Direct Only)', 'Position', [100, 100, 800, 900]);

% --- (1) 距離の推移 ---
subplot(4, 1, 1);
plot(t, distance, 'b', 'LineWidth', 1.5); hold on;
yline(20, 'k--', '20m地点（法規基準測定位置）', 'LabelHorizontalAlignment', 'left');
title('音源とマイクの距離推移'); 
xlabel('時間 [s]'); ylabel('距離 [m]');
grid on;

% --- (2) 観測された物理音圧 [Pa] ---
subplot(4, 1, 2);
plot(t, output_signal_pa, 'k');
title('観測された物理音圧 [Pa]');
xlabel('時間 [s]'); ylabel('音圧 [Pa]');
grid on;

% --- (3) 音圧レベル [dB SPL] の推移（理論値の証明） ---
window_size = round(fs * 0.05); % 50msの窓でエンベロープを取得
envelope_pa = movmax(abs(output_signal_pa), window_size);
SPL_dB_time = 20 * log10(envelope_pa / P0);
SPL_dB_time(SPL_dB_time < 0) = 0; % マイナス無限大回避

subplot(4, 1, 3);
plot(t, SPL_dB_time, 'g', 'LineWidth', 1.5); hold on;
yline(110, 'k--', '法規基準: 110 dB SPL', 'LabelHorizontalAlignment', 'left');
title('観測された絶対音圧レベルの推移 [dB SPL]');
xlabel('時間 [s]'); ylabel('dB SPL');
ylim([80 140]); grid on;

% --- (4) 高解像度スペクトログラム ---
subplot(4, 1, 4);
nfft = 2048; 
window = 2048;
noverlap = 2000; % 重なりを増やして時間を滑らかに
spectrogram(final_saved_audio, window, noverlap, nfft, fs, 'yaxis');
title('ドップラーシフト（500Hz〜1500Hz拡大）');
colormap jet;
ylim([0.5, 1.5]); % サイレンの主要帯域（0.5kHz〜1.5kHz）にズーム