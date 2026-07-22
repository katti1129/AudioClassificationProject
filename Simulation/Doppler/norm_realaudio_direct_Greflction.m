%%パラメータ変更
cpa_horizontal = 10; % 水平方向の最接近距離 [m]
v = 100 * 1000/3600;  % 速度 60km/h -> 約16.67 m/s
ref_coeff = 0.8;     % 地面の反射係数
audio_savepath = '../data/dataset/velocity/ambulance_CPA10m_V100_R080.wav';


%% 1. 音源の読み込みと物理音圧(Pa)への変換
% ※ 'ambulance.wav' を実際のファイル名に変更してください
[input_signal, fs] = audioread('../data/input/ambulance.wav');

% モノラル化
if size(input_signal, 2) > 1
    input_signal = mean(input_signal, 2);
end

% 変更前 : 一旦デジタル最大振幅を1.0に正規化（波形の形だけを抽出）
%signal_norm = input_signal / max(abs(input_signal));

% 変更後：実効値を1に正規化
signal_norm = input_signal / rms(input_signal);



% 【最重要】1m地点での目標音圧レベル (136 dB SPL) を定義し、Pa単位に変換
P0 = 2e-5; % 基準音圧(人間の最小可聴域) 20 μPa
SPL_1m = 136;%1mで136dB
P_1m = P0 * 10^(SPL_1m / 20); % 約 126.19 Pa

% 波形データを無次元から「パスカル(Pa)」単位に変換
% これにより、signal_paの最大値は 126.19 [Pa] になります。
signal_pa = signal_norm * P_1m;

fprintf('1m地点のRMS音圧: %.3f Pa\n', rms(signal_pa));
spl_check_1m = 20 * log10(rms(signal_pa) / P0);
fprintf('1m地点の音圧レベル: %.2f dB SPL\n', spl_check_1m);

% 時間軸の作成
duration = length(input_signal) / fs; 
t_in = (0:1/fs:duration-1/fs)';

%% 2. 物理パラメータの設定
c = 343;             % 音速 [m/s]
%v = 60 * 1000/3600;  % 速度 60km/h -> 約16.67 m/s
%ref_coeff = 0.8;     % 地面の反射係数
d0 = 1.0;            % 基準距離 [m]

z_s = 1.5; % サイレンの高さ [m]
z_m = 1.2; % マイクの高さ [m]

%cpa_horizontal = 20; % 水平方向の最接近距離 [m]

mic_pos = [0, cpa_horizontal, z_m]; % マイク座標

%% 3. 移動軌跡
t = (0:1/fs:duration-1/fs)';
x_pos = v * (t - duration/2);
y_pos = zeros(size(t)); 

source_pos_dir = [x_pos, y_pos, z_s * ones(size(t))];
source_pos_ref = [x_pos, y_pos, -z_s * ones(size(t))];

%% 4. 距離と到達遅延の計算
dist_dir = sqrt(sum((source_pos_dir - mic_pos).^2, 2));
delay_dir = dist_dir / c;

dist_ref = sqrt(sum((source_pos_ref - mic_pos).^2, 2));
delay_ref = dist_ref / c;

%% 5. ドップラー効果の付与
t_req_dir = t - delay_dir;
t_req_ref = t - delay_ref;

% Pa単位のまま補間
signal_dir_pa = interp1(t_in, signal_pa, t_req_dir, 'linear', 0);
signal_ref_pa = interp1(t_in, signal_pa, t_req_ref, 'linear', 0);

%% 6. 距離減衰と合成（パスカル空間での計算）
output_dir_pa = signal_dir_pa .* (d0 ./ dist_dir);
output_ref_pa = signal_ref_pa .* (d0 ./ dist_ref) * ref_coeff;

% マイクで観測される最終的な物理音圧 [Pa]
final_output_pa = output_dir_pa + output_ref_pa;

%% 7. WAVファイルへの書き出し（デジタル振幅への再変換）
% WAVファイルは -1.0 〜 1.0 の範囲しか保存できません。
% そこで、「136 dB SPL (約126.19 Pa) をデジタル振幅の 1.0 とする」という
% デジタルマッピングルールをここで適用して割り算します。
final_saved_audio = final_output_pa / P_1m;

audiowrite(audio_savepath, final_saved_audio, fs);

%% 8. 結果の可視化
figure('Name', 'Strict Physical dB SPL Simulation', 'Position', [100, 100, 800, 1000]);

% --- (1) 距離の変化 ---
subplot(4, 1, 1);
plot(t, dist_dir, 'b', 'LineWidth', 1.5); hold on;
plot(t, dist_ref, 'r--', 'LineWidth', 1.5);
yline(20, 'k--', '20m地点', 'LabelHorizontalAlignment', 'left');
title('音源とマイクの距離変化');
xlabel('時間 [s]'); ylabel('距離 [m]');
legend('直接音', '反射音'); grid on;

% --- (2) 物理音圧 [Pa] ---
subplot(4, 1, 2);
plot(t, final_output_pa, 'k');
title('観測された物理音圧 [Pa] (1mで最大約126.19 Pa)');
xlabel('時間 [s]'); ylabel('音圧 [Pa]'); grid on;

% --- (3) 短時間RMS音圧レベル [dB SPL] ---
window_size = round(fs * 0.125);   % 125 ms（騒音計Fast特性相当）

% 短時間RMSの計算
rms_pa = sqrt(movmean(final_output_pa.^2, window_size));

% dB SPLへ変換
SPL_dB_time = 20 * log10(max(rms_pa, eps) / P0);                             

subplot(4,1,3);
plot(t, SPL_dB_time, 'g', 'LineWidth', 1.5); hold on;
yline(110,'k--','110 dB SPL','LabelHorizontalAlignment','left');

title('観測された短時間RMS音圧レベル [dB SPL]');
xlabel('時間 [s]');
ylabel('dB SPL');
ylim([80 140]);
grid on;

% --- (4) 高解像度スペクトログラム ---
subplot(4, 1, 4);
spectrogram(final_saved_audio, 2048, 2000, 2048, fs, 'yaxis');
title('スペクトログラム');
colormap jet; ylim([0.5, 1.5]);


[min_dist, idx] = min(dist_dir);

fprintf("最短距離 = %.2f m\n", min_dist);

fprintf("その時の直接音RMS = %.3f Pa\n", ...
    rms(output_dir_pa(idx-1000:idx+1000)));                

fprintf("その時のdB = %.2f dB SPL\n", ...
    20*log10(rms(output_dir_pa(idx-1000:idx+1000))/P0));

fprintf("直接音距離\n");
fprintf("  最小距離 = %.2f m\n", min(dist_dir));
fprintf("  最大距離 = %.2f m\n", max(dist_dir));

fprintf("\n距離減衰係数\n");
fprintf("  最大 = %.4f\n", max(d0 ./ dist_dir));
fprintf("  最小 = %.4f\n", min(d0 ./ dist_dir));