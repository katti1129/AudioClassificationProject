%% MAIN_SIMULATION Integrated ambulance acoustic simulation entry point.
% Edit only the CONFIG fields below for a new experiment. All distances are
% in metres, time in seconds, velocity in m/s, acceleration in m/s^2,
% frequency in Hz, and calibrated acoustic signals in Pa.

clear; clc;

config = default_config();

%% 実験条件（ここで指定した値が default_config.m より優先される）
% 1回の実行につき1条件。まず1項目ずつ変更し、他の条件は固定する。
% 以下の有効な設定値は既定条件と同じ。候補値は自動で一括実行されない。
% 位置・速度・加速度は [x, y, z]。単位は m、m/s、m/s^2。

%% 1. 救急車の位置・速度・加速度
config.source.initialPositionM = [-50, 0, 1.5];
config.source.initialVelocityMps = [60/3.6, 0, 0]; % 候補: 0, 30/3.6, 60/3.6
config.source.accelerationMps2 = [0, 0, 0];        % 候補: x方向 -1, 0, 1
% 負の速度は逆方向。減速実験では観測中に停止・反転しないか確認する。
% 音源・受音点とも、観測中の速度は音速未満である必要がある。

%% 2. 歩行者（受音点）の位置・速度・加速度
config.receiver.initialPositionM = [0, 10, 1.2];
config.receiver.initialVelocityMps = [0, 0, 0];    % 候補: 0, 4/3.6, -4/3.6
config.receiver.accelerationMps2 = [0, 0, 0];
% 同方向・逆方向・横断を比較する。横断例: [0, 4/3.6, 0]。
% 距離だけの比較では両者の速度・加速度を0にする。
% 例: 音源 [0,0,1.5]、受音点 [10,0,1.5], [30,0,1.5], [50,0,1.5]。
% 移動時は初期距離だけでなく最接近距離・通過時刻も確認する。

%% 3. 障害物の有無・配置・個数・寸法・材質
config.obstacle.enabled = true;                  % false: 障害物なし
config.obstacle.seed = 1;                        % 複数配置で反復: 1, 2, 3, ...
config.obstacle.count = 24;                      % 個数の比較例: 8, 16, 24
config.obstacle.boundsMinM = [-45, -5, 0];
config.obstacle.boundsMaxM = [45, 18, 0];
config.obstacle.widthRangeM = [0.8, 3.0];
config.obstacle.depthRangeM = [0.8, 3.0];
config.obstacle.heightRangeM = [1.0, 6.0];
config.obstacle.trajectoryClearanceM = 1.0;
config.obstacle.avoidObstacleOverlap = true;
config.obstacle.materials = struct( ...
    'name', {"concrete", "brick", "generic_hard"}, ...
    'pressureReflectionCoefficient', {0.80, 0.70, 0.60});
config.obstacle.manualObstacles = struct([]);     % 空ならランダム生成
% 同じseedでも軌跡・寸法等を変えると配置が変わる場合がある。
% 配置を厳密に固定する比較では、保存済みMATのresults.obstaclesを使う:
% saved = load('保存済みのphysical_results.matへのパス', 'results');
% config.obstacle.manualObstacles = saved.results.obstacles;
% manualObstaclesが非空ならcount・seed・寸法範囲等の生成設定は使われない。
% 障害物ありでも遮蔽されるとは限らない。results.obstructionで確認する。

%% 4. 反射・回折の切り分け
config.reflection.enabled = true;               % false: 全反射を無効化
config.reflection.obstacleFacesEnabled = true;   % 障害物面からの反射
config.reflection.planes(1).pressureReflectionCoefficient = 0.60;
% 地面の圧力反射係数の比較例: 0, 0.3, 0.6, 0.9（実測値ではない）。
config.diffraction.enabled = true;              % falseでも障害物の遮蔽は残る
% 推奨する遮蔽比較（反射は全条件でfalseに固定）:
% A: obstacle.enabled=false, diffraction.enabled=true  : 障害物なし
% B: obstacle.enabled=true,  diffraction.enabled=false : 遮蔽のみ
% C: obstacle.enabled=true,  diffraction.enabled=true  : 遮蔽と回折
% BとCは同じ障害物配置を使う。Bは効果を切り分ける比較用条件。
% 地面反射だけを比較するときはobstacle.enabled=falseで反射を切り替える。

%% 5. 元音源・音圧・観測時間
% 別の未学習音源に変更する場合、以下を有効化する:
% config.audio.inputFile = fullfile(fileparts(mfilename('fullpath')), ...
%     'data', 'input', '別の音源.wav');
config.audio.referenceSPLdB = 136.0;              % 基準距離でのRMS SPLの仮定
config.audio.referenceDistanceM = 1.0;           % 校正基準距離。通常は固定
config.audio.loopInput = false;                  % 短い入力はゼロ埋め
config.simulation.durationSec = 6.0;
% 速度を下げる場合は、接近・通過・離反が観測時間に入るか確認する。
% 時間を延ばす場合は入力WAVの長さも確認する。
% loopInput=trueは繰り返し再生になるため、つなぎ目に注意する。

%% 6. 数値条件（AIの比較中は固定し、別途収束性を確認）
config.audio.sampleRateHz = 16000;               % AIの入力仕様に合わせる
config.audio.internalOversampleFactor = 2;       % 比較例: 1, 2, 4
config.simulation.geometryTimeStepSec = 0.01;    % 比較例: 0.02, 0.01, 0.005
config.fresnel.enabled = true;                   % false: 全障害物を回折候補に
config.fresnel.frequencyHz = 500.0;
config.fresnel.zoneNumber = 1;
config.diffraction.windowLengthSamples = 512;
config.diffraction.overlapSamples = 384;
config.diffraction.fftLength = 512;
% FFT条件は整合させて変更する。窓長・overlap・FFT長の比較例:
% (256,192,256), (512,384,512), (1024,768,1024)。
% 数値条件による音・指標の変化が十分小さいか確認する。
% 音速・最小距離・ソルバー許容誤差等はdefault_configの値を通常維持する。

%% 7. 保存・比較条件
config.simulation.id = "";                       % 設定から実行IDを自動生成
config.output.writeComponentWav = true;
config.output.writeMat = true;
config.output.writeExcel = true;
config.output.writeFigures = true;
config.output.fullScaleSPLdB = 154.0;             % 全実験で同じ換算スケール
config.output.wavClippingPolicy = "error";
config.output.overwrite = true;                  % 同じIDの結果を上書きする
% 比較中はファイルごとのピーク正規化をしない。
% 同じ入力ファイル名の中身だけを変えず、音源ごとに別ファイル名を使う。

%% AI評価時に別途行う項目（このスクリプトには雑音混合・AI推論は未実装）
% ・背景雑音の種類と強さ: 受音点の環境音を混合して比較する。
%   距離比較では背景雑音レベルを固定。SNR一定の比較とは分ける。
% ・救急車を含まない背景音のみの条件で誤検知を評価する。
% ・学習済みモデル、前処理、閾値、連続検知の成立条件を固定する。
% ・再現率、誤検知率、接近時の初回検知距離、遮蔽区間の再現率を記録する。
% ・複数の元録音・背景音・配置で反復し、条件間は同じ素材で比較する。
% ・同じ元録音から生成した派生音を学習用と評価用に分割しない。

results = acoustics.runSimulation(config);

fprintf('\nSimulation complete: %s\n', results.simulationId);
fprintf('Output directory: %s\n', results.output.directory);
fprintf('Final peak pressure: %.6g Pa\n', max(abs(results.signals.finalPa)));
fprintf('WAV scale: %.6g Pa per digital full scale\n', results.output.paPerFullScale);
