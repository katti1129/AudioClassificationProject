%% acoustic_sim_step2_visualize_3D.m
clear; clc;

%% 座標設定 [x, y, z]
source = [0, 0, 1];   % 音源（高さ1m）
mic    = [4, 2, 1];   % マイク（少し斜めに配置）

%% 鏡像音源（z反転）
image_source = [source(1), source(2), -source(3)];

%% 直線（鏡像音源 → マイク）と地面(z=0)の交点を求める
p1 = image_source;
p2 = mic;

t = (0 - p1(3)) / (p2(3) - p1(3));  % z=0になるパラメータ
reflect_point = p1 + t * (p2 - p1);

%% 距離確認（重要）
dist_reflect_real = norm(source - reflect_point) + norm(reflect_point - mic);
dist_image = norm(image_source - mic);

disp("実際の反射経路の長さ:");
disp(dist_reflect_real);

disp("鏡像直線の長さ:");
disp(dist_image);

%% 可視化
figure; hold on; grid on;

% 地面（z=0）
[X, Y] = meshgrid(-1:0.5:5, -1:0.5:5);
Z = zeros(size(X));
surf(X, Y, Z, 'FaceAlpha',0.2, 'EdgeColor','none');

% 音源
plot3(source(1), source(2), source(3), 'ro', 'MarkerSize',10, 'DisplayName','Source');

% マイク
plot3(mic(1), mic(2), mic(3), 'bo', 'MarkerSize',10, 'DisplayName','Mic');

% 鏡像音源
plot3(image_source(1), image_source(2), image_source(3), 'mo', 'MarkerSize',10, 'DisplayName','Image Source');

% 実際の反射経路（折れ線）
plot3([source(1) reflect_point(1)], ...
      [source(2) reflect_point(2)], ...
      [source(3) reflect_point(3)], ...
      'r--', 'LineWidth',2);

plot3([reflect_point(1) mic(1)], ...
      [reflect_point(2) mic(2)], ...
      [reflect_point(3) mic(3)], ...
      'r--', 'LineWidth',2);

% 鏡像直線
plot3([image_source(1) mic(1)], ...
      [image_source(2) mic(2)], ...
      [image_source(3) mic(3)], ...
      'g-', 'LineWidth',2);

% 反射点
plot3(reflect_point(1), reflect_point(2), reflect_point(3), ...
      'ks', 'MarkerSize',10, 'DisplayName','Reflection Point');

legend;
xlabel('x'); ylabel('y'); zlabel('z (高さ)');
title('3D鏡像法：反射経路 vs 直線');

axis equal;
view(45,30);