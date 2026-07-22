%% 1. 音源の読み込みと基本設定
% ※ 'your_siren.wav' を実際のファイル名に変更してください
[input_signal, fs] = audioread('../data/input/ambulance.wav');

% モノラル化（ステレオの場合）
if size(input_signal, 2) > 1
    input_signal = mean(input_signal, 2);
end

% 自動で長さを取得し、入力用の時間軸 t_in を作成
duration = length(input_signal) / fs;
t_in = (0:1/fs:duration-1/fs)';

%% 2. 物理パラメータの設定
c = 343;             % 音速 [m/s]
v = 60 * 1000/3600;  % 救急車の速度 60km/h -> 約16.67 m/s
ref_coeff = 0.8;     % 地面の反射係数（アスファルトなどを想定）
d0 = 1.0;            % 基準距離 [m]

% 高さの設定
z_s = 1.5; % 音源（サイレン）の高さ [m]
z_m = 1.2; % マイクの高さ [m]

% マイクの3次元座標 [X, Y, Z]
mic_pos = [0, 10, z_m]; % マイクは X=0, Y=10m（道路脇）, Z=1.2m の位置

%% 3. 音源と鏡像音源の移動軌跡
% 観測用の時間軸 t
t = (0:1/fs:duration-1/fs)';

% X方向の移動：ちょうど真ん中の時間(duration/2)でマイクの正面(X=0)を通過するように設定
x_pos = v * (t - duration/2);
y_pos = zeros(size(t)); % 音源のY座標は常に0m（道路の中央）

% 直接音源の3次元座標
source_pos_dir = [x_pos, y_pos, z_s * ones(size(t))];

% 鏡像音源（地面反射）の3次元座標（Z座標だけマイナスにする）
source_pos_ref = [x_pos, y_pos, -z_s * ones(size(t))];

%% 4. 距離と到達遅延の計算
% 直接音の距離と遅延
dist_dir = sqrt((source_pos_dir(:,1) - mic_pos(1)).^2 + ...
                (source_pos_dir(:,2) - mic_pos(2)).^2 + ...
                (source_pos_dir(:,3) - mic_pos(3)).^2);
delay_dir = dist_dir / c;

% 反射音の距離と遅延
dist_ref = sqrt((source_pos_ref(:,1) - mic_pos(1)).^2 + ...
                (source_pos_ref(:,2) - mic_pos(2)).^2 + ...
                (source_pos_ref(:,3) - mic_pos(3)).^2);
delay_ref = dist_ref / c;

% 計算した距離の差を確認
disp('--- 最初の5点の直接音と反射音の距離 ---');
disp([dist_dir(1:5), dist_ref(1:5)]);

% 遅延時間の差を確認
disp('--- 最初の5点の遅延時間差(ms) ---');
disp((dist_ref(1:5) - dist_dir(1:5)) / 343 * 1000);

%% 5. ドップラー効果の付与（interp1による波形の再配置）
% マイクが時刻 t に受け取る音は、音源が (t - delay) に発した音
t_req_dir = t - delay_dir;
t_req_ref = t - delay_ref;

% 線形補間で波形を生成（範囲外の時間は 0 で埋める）
signal_dir = interp1(t_in, input_signal, t_req_dir, 'linear', 0);
signal_ref = interp1(t_in, input_signal, t_req_ref, 'linear', 0);

%% 6. 距離減衰と合成
% 1/d の減衰を適用
output_dir = signal_dir .* (d0 ./ dist_dir);
output_ref = signal_ref .* (d0 ./ dist_ref) * ref_coeff; % 反射係数も掛ける

% 最終合成波形
final_output = output_dir + output_ref;
%final_output = final_output * 50;

%% 7. 音声の保存・可視化
% 出力ファイルの保存
audiowrite('../data/output/doppler_gref_ambulance_output.wav', final_output, fs);

%% 7. 結果の可視化（3段グラフ）
figure('Name', 'Doppler and Ground Reflection Simulation', 'Position', [100, 100, 800, 800]);

% --- (1) 距離の変化 ---
subplot(3, 1, 1);
plot(t, dist_dir, 'b', 'LineWidth', 1.5); hold on;
plot(t, dist_ref, 'r--', 'LineWidth', 1.5);
title('音源とマイクの距離変化');
xlabel('時間 [s]'); ylabel('距離 [m]');
legend('直接音の経路', '地面反射の経路');
grid on;

% --- (2) 合成波形 ---
subplot(3, 1, 2);
plot(t, final_output, 'k');
title('観測された波形（直接音 ＋ 反射音）');
xlabel('時間 [s]'); ylabel('振幅');
grid on;

% --- (3) 高解像度スペクトログラム ---
subplot(3, 1, 3);
nfft = 2048; % 周波数分解能を高めてドップラーのS字を綺麗に出す
window = 2048;
noverlap = 2000;
spectrogram(final_output, window, noverlap, nfft, fs, 'yaxis');
title('スペクトログラム（ドップラー効果と干渉縞）');
colormap jet;
% ※ サイレンの音（例: 500Hz〜1500Hz付近）にズームイン。必要に応じて変更してください。
ylim([0.5, 1.5]);