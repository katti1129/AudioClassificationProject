# データセット生成GUIとバッチパイプライン

## 起動と使い方

MATLAB R2025bで Simulation フォルダを開き、次を実行する。

~~~matlab
dataset_generator
~~~

1. 「生成する音源数」を指定し、「設定行を生成」を押す。既存の表は新しい行に置き換わる。
2. 共通設定を入力し、「全行に適用」または「選択行に適用」を押す。表のセルも個別編集できる。
3. 「開始 Seed」と「Seed 自動割当」で連番にする。同じseedを意図的に使う場合は表を手動編集する。共通設定の適用は既存seedを保持する。
4. 保存先の親フォルダ・Dataset名・同名の処理を選ぶ。既定は Rename。
5. 必要に応じて図・物理量MATの保存を切り替える。障害物Excel、条件スナップショット、最終WAVは常に保存する。
6. 「データセット生成開始」で上から順に実行する。現在の実験名、完了数、進捗ゲージ、行ごとの状態が更新される。
7. 「現在の条件の後で停止」は実行中の1条件が終わった時点で停止する。残りは CANCELLED として記録する。

共通設定を変えただけでは表には反映されない。「全行に適用」等を押す。
Save Config / Load Config で、条件表だけでなく全base config・出力オプションもMATへ保存・復元する。
設定は各実行時にも自動保存する。

## 既存コードの調査と変更範囲

| 調査項目 | 既存実装と今回の対応 |
|---|---|
| 計算の入口 | main_simulation → acoustics.runSimulation。GUIも同じ関数を呼ぶ |
| config | Source/Receiverの位置・初速度・一定加速度、WAV、時間、反射、障害物、Fresnel、回折、校正音圧等 |
| WAV・音圧尺度 | acoustics.writeOutputs。既存の全成分ピーク確認・固定Pa/full-scale算出をそのまま通す |
| Excel | acoustics.writeMetadataExcel。結果の出力先だけ指定し直して再利用 |
| グラフ | acoustics.createFigures。既存4図を再利用 |
| 元の保存先 | config.output.rootDir / simulationId 配下 |
| 元のID | acoustics.createSimulationId。設定から生成するハッシュを条件名の末尾にも再利用 |
| バッチ化 | +pipeline のラッパーで条件変換、保存先、失敗分離、衝突管理、manifestを追加 |
| 追加 | dataset_generator.m、+pipeline/、専用tests、本文書 |
| 既存の変更 | READMEへの案内だけ。main_simulation、default_config、+acoustics、従来testsは変更しない |

開始時に default_config.m にユーザーによるコメント追記があった。その変更を保持した。
GUIの初期値は実行時の default_config() から読み取る。main_simulation 内の個別上書き値は読み取らない。
後者の設定を使いたい場合は同じ内容をconfig構造体へまとめて dataset_generator(config) へ渡す。

## パラメータの正確な対応

このGUIの条件表は、x方向の直線移動（一定加速度を含む）を設定するプリセットである。

| 表の列 | 意味・既存configへの対応 |
|---|---|
| InputWAV | audio.inputFile |
| CPA_m | receiver.initialPositionM(2) = source.initialPositionM(2) + CPA_m |
| SourceVelocityKmh | source.initialVelocityMps = [値/3.6, 0, 0] |
| ReceiverVelocityKmh | receiver.initialVelocityMps = [値/3.6, 0, 0] |
| Profile | constant_velocity / constant_acceleration。既存一定加速度モデルの設定プリセット |
| SourceAccelerationMps2 | source.accelerationMps2 = [値, 0, 0] |
| ReceiverAccelerationMps2 | receiver.accelerationMps2 = [値, 0, 0] |
| DurationSec | simulation.durationSec |
| GroundReflectionCoeff | IDが ground の reflection.planes の圧力反射係数 |
| Obstacle | obstacle.enabled |
| ObstacleCount | obstacle.count |
| Seed | obstacle.seed（0〜2^32−1） |
| Diffraction | diffraction.enabled |
| Reflection | reflection.enabled |

- 初期位置のSource xyzとReceiver x/zはbase configから引き継ぐ。観測時刻0での配置を速度に合わせて自動再配置しない。
- 速度・加速度のy/z成分はこのプリセットでは0に設定する。任意3D軌跡の研究は従来の acoustics.runSimulation(config) または pipeline.run_single を直接利用する。
- CPA_m は旧コード Doppler/norm_realaudio_direct_Greflction.m の cpa_horizontal に対応する横方向間隔。観測時間内にx方向の並びが一致しないと、実際の最接近距離はこの値より大きい。
- manifestに同時刻のSource/Receiver軌跡から求めた ObservedHorizontalCPAM、ObservedCPATimeSec、Observed3DMinimumM を保存する。これは受音時刻・放射時刻の違いを含む伝搬経路長とは別の幾何量である。
- PVという変数・速度プロファイル番号は既存全MATLABファイルに存在しなかった。PV4を推測せず、Receiver速度を明示する RV4 を使う。
- constant_velocity で加速度が0以外の行はFAILEDとする。加速度を使う場合は constant_acceleration を選ぶ。
- GroundReflectionCoeffは地面だけに適用する。障害物の材質係数や他の反射面はbase configの値を保持する。ground面が存在しないbase configではNaNとして面を追加しない。
- ランダム配置を制御する条件表なので、base configの manualObstacles が非空の場合は明示的なエラーにする。表の個数やseedが黙って無視されることを防ぐ。
- 障害物OFF時でも回折ONは許容する。既存計算が障害物なしとして処理する。
- サンプルレート、音速、入力校正SPL、Fresnel設定、障害物寸法・領域等はbase configを保持する。必要な場合はGUIを開く前にconfigを編集する。

## ファイル名と保存構成

例（末尾ハッシュは設定によって変わる）:

~~~text
ambulance_CPA20m_V060_RV4_R080_OBS1_N24_SEED1_DIF1_REF1_HXXXXXXXX
~~~

V/RVは初期x速度[km/h]、Rは地面の圧力反射係数×100、OBSは障害物ON/OFF、Nは有効な障害物数、DIF/REFは回折/反射フラグ。
負数は m、小数点は p で表す。たとえば RVm4 は−4 km/h。
入力WAVのstemはファイル名に使える文字へ置き換え、24文字に制限する。

末尾Hは、出力先・出力スイッチを除いたconfigの既存32-bitハッシュ。
加速度、観測時間、高さ、校正SPLなど名前の先頭に列挙しない設定も識別に含む。
ハッシュには入力WAVのパスを含むが、WAVファイル内容の暗号学的ハッシュではない。
同じパスのWAV内容を置換する場合、Skipで以前の結果を再利用しないよう注意する。
厳密な識別と再現には保存したconfigと元WAVも保持する。

~~~text
datasets/Dataset_001/
  audio/
    <experiment_name>.wav
  simulation_results/
    <experiment_name>/
      excel/metadata.xlsx
      figures/
        geometry.png
        waveforms.png
        spectrograms.png
        diagnostics.png
      physical_results.mat       # 保存ONの場合
      config.mat
      requested_condition.mat
      run_info.txt
      matlab_log.txt
  dataset_manifest.xlsx
  dataset_manifest.csv
  dataset_manifest.mat
  dataset_config.mat
  _runs/<run_id>/dataset_config.mat
  _history/<unique_archive>/...   # Overwriteで以前の結果を退避
~~~

Windows上で長い実験名をフォルダ名とファイル名に二重に書くと、Excel等のパス制限に当たる。
このため実験名はWAV・結果フォルダ・Excel/MAT内のSimulationIDで統一し、診断ファイルのbasenameは短い役割名とした。
既存の図生成は短い一時パスで行い、最終フォルダへ移動する。最終MATのfigureFilesは移動後のパスである。
さらに深い親フォルダを使う場合は、親パスを短くする。

AIが読む audio/ には最終受音WAVだけを置く。成分別WAVは生成しない。
directPa / reflectedPa / diffractedPa / finalPa は物理量MATに残る。
従来の main_simulation の4成分WAV出力は従来通りである。

## 波形・振幅の保持

pipeline.run_single は、既存 acoustics.runSimulation を出力抑制設定で実行する。
既存 writeOutputs が算出・検証した results.output.paPerFullScale で最終信号をWAV化する。
振幅変換式は従来と同じ pressurePa / PaPerFullScale で、個別ピーク正規化を追加しない。

データセットでは wavClippingPolicy="error" を要求する。
許容範囲を超えた条件はFAILEDとなり、後続へ進む。
同じbase configの全行で固定fullScaleSPLdBを使い、実際のPaPerFullScaleもmanifestに保存する。
元WAVは音圧校正値を内包しないため、referenceSPLdBは既存モデルの校正仮定である。

各条件の音声は結果フォルダ内の pending_final.wav に一旦保存し、Excel・図・MATの保存が済んでからaudio/へ移動する。
途中失敗時のpending WAVは診断用フォルダに残る場合があるが、audio/には未完了音声を公開しない。

## 衝突、失敗、manifest

- Rename（既定）: 同名のWAVまたは結果フォルダがあれば _REP02、_REP03…を付ける。
- Skip: 元の成果物を保持し、その試行をSKIPPEDとして記録する。
- Overwrite: 既存WAVと結果フォルダを _history に退避してから実行する。GUIでは選択時の実行確認を表示する。スクリプトではこのpolicy指定が上書き意思表示になる。
- 行の計算・入出力エラーはFAILEDとし、MATLABのidentifierとmessage、詳しいスタックを保存して後続へ進む。
- 成功はSUCCESS。停止予約後の未実行行はCANCELLED。
- 同じDatasetへの同時書込みを .batch_lock で防ぐ。MATLAB強制終了後にlockが残った場合は、実行プロセスがないことを確認してそのlockフォルダだけを除去してから再開する。
- 通常のキャンセルは条件間で行う。単一シミュレーションの計算ループ内部にキャンセル処理は追加していない。

dataset_manifest.xlsx は2シート構成。

| シート | 意味 |
|---|---|
| Manifest | experiment nameごとに1行。現在の成果物/失敗状態。SUCCESS行のWAVPathがAI入力 |
| Attempts | 全実行の全要求行。Skip、Overwrite、FAILED、CANCELLEDを含む履歴 |

同じ名前をSkipしても、既存のSUCCESSをSKIPPEDに書き換えない。
上書き後の履歴はAttemptsと_historyで追跡する。
失敗・キャンセル行にはWAVが存在しないことがあるため、AI読込みではStatus=="SUCCESS"で絞り込む。

1条件が終了するたびにMAT/CSVを更新し、Excelを一時ファイル経由で更新する。
Excelを開いたまま等で更新できない場合は警告し、MAT/CSVの新しい記録を保持して続行する。
Excelを閉じた後、以下で再生成できる。

~~~matlab
datasetDir = fullfile(pwd,'datasets','Dataset_001');
saved = load(fullfile(datasetDir,'dataset_manifest.mat'));
pipeline.write_manifest(datasetDir,saved.manifest,saved.attempts);
~~~

manifestの主な列:
ID、Filename、InputWAV、Source、CPA_m、SourceVelocityKmh、ReceiverVelocityKmh、
Profile、加速度、GroundReflectionCoeff、Obstacle/ObstacleCount、Seed、
Diffraction/Reflection、DurationSec、Status、ErrorIdentifier、ErrorMessage、
WAVPath、ResultFolder、CreatedAt、RunID、RowNumber、ElapsedSec、
SampleRateHz、PaPerFullScale、AdaptiveScaleUsed、観測CPA、回折近似フレーム数、WarningText、ArchiveFolder。

RequestedObstacleCountは指定個数、ObstacleCountは有効個数（障害物OFFでは0）。

## スクリプトからの利用

~~~matlab
base = default_config();
rows = pipeline.default_conditions(3,base);
rows.CPA_m = [10;20;50];
rows.SourceVelocityKmh(:) = 60;
rows.ReceiverVelocityKmh(:) = 4;
rows = pipeline.assign_seeds(rows,101);

options = pipeline.default_options();
options.datasetName = 'Dataset_001';
options.collisionPolicy = 'Rename';
[manifest,attempts] = pipeline.run_batch(rows,base,options);
~~~

GUI用の共通base configを変える例:

~~~matlab
base = default_config();
base.audio.referenceSPLdB = 130;
base.simulation.durationSec = 8;
base.obstacle.boundsMaxM = [60,60,0];
dataset_generator(base);
~~~

PythonでAI評価用ファイルを列挙する例:

~~~python
import pandas as pd
from pathlib import Path

root = Path(r"C:\Users\cpsla\AudioClassificationProject\Simulation\datasets\Dataset_001")
manifest = pd.read_excel(root / "dataset_manifest.xlsx", sheet_name="Manifest")
wav_paths = manifest.loc[manifest["Status"].eq("SUCCESS"), "WAVPath"].tolist()
~~~

別のPCへ移す場合はFilenameを使って root / "audio" / filename と再構築する。
絶対パスのInputWAVを移動した場合はGUIから追加・再選択する。

## ファイルの役割と検証

| ファイル | 役割 |
|---|---|
| dataset_generator.m | GUI、入力、共通適用、進捗、保存/読込 |
| condition_schema / default_conditions | 単位つき列定義、初期行 |
| row_to_config / ground_plane_index | 既存configへの対応 |
| assign_seeds / apply_common | seed割当、選択行/全行の更新 |
| default_options / validate_config | 出力先・バッチ構造検証 |
| build_experiment_name | 条件名の唯一の生成箇所 |
| create_output_paths / resolve_collision | 保存先、衝突と退避 |
| run_batch | 順次実行、例外分離、進捗、キャンセル、履歴 |
| run_single | 既存シミュレーション呼出しと出力ラッパー |
| manifest_record / write_manifest | 管理表、MAT/CSV/XLSX更新 |
| save_dataset_config / load_dataset_config | 再現可能な設定の保存と復元 |

~~~matlab
addpath('tests');
datasetTests = run_dataset_tests(); % 新規GUI/パイプライン検証
legacyReports = run_all_tests();    % 既存音響検証
~~~

GUI検証では実際のuifigure/uitableを生成し、行生成、共通適用、選択行、seed、設定保存・読込、開始ボタンと同じコールバックを実行する。
バッチ検証では実ambulance.wavを使用し、意図的な入力欠落を挟んだ連続実行、出力再読込、既存runSimulationとの信号一致、衝突3種、キャンセル、lockを確認する。

GUI APIの参照:
- https://www.mathworks.com/help/matlab/ref/uitable.html
- https://www.mathworks.com/help/matlab/creating_guis/app-or-gui-with-graphical-table.html

音響モデルと近似の適用範囲はREADME、SYSTEM_DESIGNの説明を引き継ぐ。

2026-09-30の検証では、新規13テストと従来46項目が通過し、追加23本の静的解析は指摘0件。
実行記録と検証用Datasetの場所は DATASET_PIPELINE_VALIDATION.md を参照。
