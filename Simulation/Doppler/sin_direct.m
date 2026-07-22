% --- 設定 ---
fs = 16000;             % サンプリング周波数 [Hz]
c = 343;                % 音速 [m/s]
v = 40;                 % 音源の速度 [m/s] (通過速度)
duration = 2.0;         % シミュレーション時間 [s]
t = 0:1/fs:duration;    % 時間軸 [s]

% --- 音源位置の定義（x軸上を移動） ---
% x方向：-20mから20mへ移動、y方向：2mの距離を保つ
source_pos = [-20 + v*t; 2*ones(size(t)); zeros(size(t))];
mic_pos = [0; 0; 0];

% --- 到達時間（遅延）の計算 ---
dist = sqrt(sum((source_pos - mic_pos).^2, 1)); % 距離の推移
delay_time = dist / c;                          % 到達遅延時間 [s]

% --- 信号の生成 ---
f0 = 1000;                                      % 入力音源の周波数 [Hz]
% 到達時間を含めた位相計算（これがドップラー効果を再現する）
mic_signal = sin(2 * pi * f0 * (t - delay_time));

% --- 可視化 ---
subplot(2,1,1);
plot(t, dist); title('音源とマイクの距離推移'); xlabel('時間 [s]'); ylabel('距離 [m]');
subplot(2,1,2);
spectrogram(mic_signal, 256, 250, 256, fs, 'yaxis');
title('ドップラーシフトの確認（スペクトログラム）');