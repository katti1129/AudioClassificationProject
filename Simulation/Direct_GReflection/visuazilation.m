clear; clc;

%% 座標設定
source = [0, 1];   % (x, z) 高さ1m
mic    = [4, 1];   % (x, z) 高さ1m

% 地面 z=0
ground_z = 0;

%% 鏡像音源
image_source = [source(1), -source(2)];

%% 反射点（直線と地面の交点を計算）
% 直線：image_source → mic
x1 = image_source(1); z1 = image_source(2);
x2 = mic(1);          z2 = mic(2);

% z=0 での交点を求める（線形補間）
t = (0 - z1) / (z2 - z1);
reflect_point = [x1 + t*(x2 - x1), 0];

%% プロット
figure; hold on; grid on;

% 地面
plot([-1 5], [0 0], 'k', 'LineWidth', 2);

% 実音源
plot(source(1), source(2), 'ro', 'MarkerSize', 8, 'DisplayName','Source');

% マイク
plot(mic(1), mic(2), 'bo', 'MarkerSize', 8, 'DisplayName','Mic');

% 鏡像音源
plot(image_source(1), image_source(2), 'mo', 'MarkerSize', 8, 'DisplayName','Image Source');

% 実際の反射経路（折れ線）
plot([source(1) reflect_point(1)], [source(2) reflect_point(2)], 'r--', 'LineWidth',2);
plot([reflect_point(1) mic(1)], [reflect_point(2) mic(2)], 'r--', 'LineWidth',2);

% 鏡像の直線
plot([image_source(1) mic(1)], [image_source(2) mic(2)], 'g-', 'LineWidth',2);

% 反射点
plot(reflect_point(1), reflect_point(2), 'ks', 'MarkerSize',8, 'DisplayName','Reflection Point');

legend;
xlabel('x');
ylabel('z (高さ)');
title('鏡像法の可視化（反射 vs 直線）');

axis equal;
ylim([-2 3]);