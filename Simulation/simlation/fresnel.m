%% 1. 基本設定（シミュレーション・パラメータ）
c = 343;                 % 音速 [m/s]
f = 500;                 % 対象とする周波数 [Hz]
lambda = c / f;          % 波長 [m]

% 音源とマイクの位置 [X, Y, Z]
source_pos = [0, 0, 1.5];
mic_pos = [50, 0, 1.2];  % 50m先にマイクを配置（長軸方向をX軸とする）

%% 2. フレネル楕円体のパラメータ計算
% 音源とマイクの直線距離 d
d = norm(mic_pos - source_pos);

% 楕円体の全長（長軸の長さ）2a
% 波の干渉条件により、Path Length L = d + lambda/2 となる
a = (d + lambda / 2) / 2;

% 楕円体の最大半径（短軸の長さ）b, c
% 中心 (d/2) における短軸半径 Rmax = 0.5 * sqrt(lambda * d)
b = sqrt(a^2 - (d/2)^2);
c_radius = b; % 回転体（プロレート・スフェロイド）とするためbと同じ

%% 3. 3Dメッシュデータの生成（楕円体の生成）
% グリッド点数を設定
n_points = 50;
[X_mesh, Y_mesh, Z_mesh] = ellipsoid(d/2, 0, 1.35, a, b, c_radius, n_points); % 中心位置（高さは平均）

%% 4. 可視化（プロット）
figure('Name', '3D Fresnel Zone Spheroid', 'Position', [100, 100, 800, 600]);
hold on; grid on; axis equal; view(3);
xlabel('X [m] (直接音経路)'); ylabel('Y [m]'); zlabel('Z [m]');
title(sprintf('第1フレネルゾーン: 距離%dm, 周波数%dHz (波長%.2fm)\nラグビーボール状の通り道を視覚化', d, f, lambda));

% 楕円体のメッシュをプロット（半透明にする）
surf(X_mesh, Y_mesh, Z_mesh, 'FaceColor', 'blue', 'FaceAlpha', 0.1, 'EdgeColor', [0.7 0.7 0.7], 'EdgeAlpha', 0.2);

% 音源とマイクをプロット
plot3(source_pos(1), source_pos(2), source_pos(3), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
plot3(mic_pos(1), mic_pos(2), mic_pos(3), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
plot3([source_pos(1), mic_pos(1)], [source_pos(2), mic_pos(2)], [source_pos(3), mic_pos(3)], 'k--'); % 中心軸

% 地面をプロット
patch([0 50 50 0], [-10 -10 10 10], [0 0 0 0], [0.8 0.8 0.8], 'FaceAlpha', 0.5);

% カメラ視点を調整
xlim([-5, d+5]); ylim([-10, 10]); zlim([0, 5]);