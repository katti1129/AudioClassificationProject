%% 1. 基本設定（空間と音響パラメータ）
num_obstacles = 100;     % 障害物の数
c = 343;                 % 音速 [m/s]
f = 500;                 % 対象とする周波数 [Hz]（サイレンの基本波付近）
lambda = c / f;          % 波長 [m]

% 音源とマイクの位置 [X, Y, Z]
source_pos = [0, 0, 1.5];
mic_pos = [50, 0, 1.2];  % 50m先にマイクを配置

% 音源とマイクの直線距離 d
d_total = norm(mic_pos - source_pos);

%% 2. 障害物のランダム生成
% X: 0〜50m, Y: -20〜20m の範囲に散りばめる
rng(1); % 乱数のシードを固定して再現性を確保
obs_x = rand(num_obstacles, 1) * 50;
obs_y = (rand(num_obstacles, 1) * 40) - 20;

% 障害物のサイズ（幅、奥行き、高さ）をランダムに設定 [0.5m 〜 2.5m]
obs_w = 0.5 + rand(num_obstacles, 1) * 2;
obs_d = 0.5 + rand(num_obstacles, 1) * 2;
obs_h = 1.0 + rand(num_obstacles, 1) * 2; 

%% 3. 厳密なフレネルゾーン計算とデータ収集用配列の初期化
% エクセルに記録するための配列を用意
dist_to_line_all = zeros(num_obstacles, 1);
fresnel_radius_all = zeros(num_obstacles, 1);
valid_obstacles = false(num_obstacles, 1);

for i = 1:num_obstacles
    % 障害物の中心座標（底面が0なので、Zの中心は高さの半分）
    obs_center = [obs_x(i), obs_y(i), obs_h(i)/2];
    
    % --- ① 音源・マイクの直線と障害物との最短距離の計算 ---
    vec_sm = mic_pos - source_pos;
    vec_so = obs_center - source_pos;
    dist_to_line = norm(cross(vec_sm, vec_so)) / norm(vec_sm);
    dist_to_line_all(i) = dist_to_line;
    
    % --- ② 障害物の位置における「正確なフレネル楕円体の半径」の計算 ---
    % 音源からの直線上の距離 x を求める（プロジェクション）
    x_projected = dot(vec_so, vec_sm) / norm(vec_sm);
    
    % 障害物が音源とマイクの間（0 〜 d_total）にある場合のみ、その位置でのローカル半径を計算
    if x_projected > 0 && x_projected < d_total
        % 第1フレネルゾーンのローカル半径公式: R(x) = sqrt( (lambda * x * (d - x)) / d )
        fresnel_local_radius = sqrt((lambda * x_projected * (d_total - x_projected)) / d_total);
    else
        fresnel_local_radius = 0; % 範囲外
    end
    fresnel_radius_all(i) = fresnel_local_radius;
    
    % --- ③ 当たり判定（障害物の半径を差し引いてフレネル内に入っているか） ---
    if dist_to_line - (obs_w(i)/2) <= fresnel_local_radius
        valid_obstacles(i) = true;
    end
end

%% 4. テーブルの作成とExcelファイルへの書き出し
% 100個のデータを一目でわかる列名でテーブルに統合
Obstacle_ID = (1:num_obstacles)';
X_Position = obs_x;
Y_Position = obs_y;
Total_Height = obs_h;
Distance_to_Line = dist_to_line_all;
Fresnel_Local_Radius = fresnel_radius_all;
Inside_Fresnel = valid_obstacles; % 1なら計算対象、0なら無視してOK

output_table = table(Obstacle_ID, X_Position, Y_Position, Total_Height, ...
                     Distance_to_Line, Fresnel_Local_Radius, Inside_Fresnel);

% ファイル名の設定（ExcelがPCに入っていない環境を考慮し、CSV形式での出力も選べます）
filename = 'acoustic_environment_data.xlsx'; 
writetable(output_table, filename);
fprintf('シミュレーションデータをエクセルファイルとして保存しました: %s\n', filename);

%% 5. 3D可視化（確認用）
figure('Name', 'Acoustic Environment Map');
hold on; grid on; view(3);
xlabel('X [m]'); ylabel('Y [m]'); zlabel('Z [m]');
title(sprintf('フレネルフィルター結果 (計算対象: %d / 100個)', sum(Inside_Fresnel)));

% 音源とマイク
plot3(source_pos(1), source_pos(2), source_pos(3), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');
plot3(mic_pos(1), mic_pos(2), mic_pos(3), 'bo', 'MarkerSize', 10, 'MarkerFaceColor', 'b');
plot3([source_pos(1), mic_pos(1)], [source_pos(2), mic_pos(2)], [source_pos(3), mic_pos(3)], 'k--');

% 障害物の描画
for i = 1:num_obstacles
    if Inside_Fresnel(i)
        plot3([obs_x(i), obs_x(i)], [obs_y(i), obs_y(i)], [0, obs_h(i)], 'r-', 'LineWidth', 2.5);
    else
        plot3([obs_x(i), obs_x(i)], [obs_y(i), obs_y(i)], [0, obs_h(i)], 'Color', [0.7 0.7 0.7], 'LineWidth', 1);
    end
end