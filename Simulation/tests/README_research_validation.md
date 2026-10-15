# 研究用の追加検証

## 実行

MATLABのCurrent FolderをSimulationにして実行します。

```matlab
addpath('tests');
report = run_research_validation();
```

既存の `run_all_tests` と `run_dataset_tests` は変更していません。本テストは別の入口です。Signal Processing Toolboxを含む、シミュレータと同じ実行環境が必要です。

設定は `research_validation_config.m` の構造体で管理します。既定の出力先は `data/output/research_validation/` 内の新規・一意な実行フォルダです。入力のWAV、Dataset_001、既存のシミュレーションコードは書き換えません。

```matlab
o = research_validation_config();
o.runSavedDataset = true;   % 保存済みSEED1～10の診断のみ。再生成しない
o.runPhysics = true;        % 人工信号と独立した解析式の比較
o.runAmbulance = true;      % 固定配置で実サイレンを新たにシミュレーション
report = run_research_validation(o);
```

特定の実サイレンケースだけ実行する場合：

```matlab
o = research_validation_config();
o.runSavedDataset = false;
o.runPhysics = false;
o.caseNames = ["finite_face_transition", "diffraction_switch"];
report = run_research_validation(o);
```

## 入力と長さ

- 人工信号：800 Hz正弦波3秒、3秒の収録区間に0.5秒時点の1サンプルパルス、500/1000/2000 Hz正弦波を各3秒。スイープは使わず、周波数別正弦波を選択しています。定常測定区間は0.7～2.5秒です。
- 実サイレン：`data/input/ambulance.wav` の全長を使用し、ループしません。受音時間は基本10秒です。観測した最長経路の遅延と0.25秒の余裕が入力末尾に対して確保されているかチェックし、不足時はFAILにします。異なる入力や大きい空間条件では `observationDurationSec` を延ばしてください。
- 人工信号はPa単位で既存の合成関数に渡します。実サイレンは本体の `loadSourceAudio` を通り、既定の基準SPLで校正されます。これはWAVから実際の収録音圧が分かるという意味ではありません。

## ファイル構成

|ファイル|役割|
|---|---|
|run_research_validation.m|全体実行、コードハッシュ記録、集計|
|research_validation_config.m|設定・数値許容差|
|analyze_saved_dataset.m|保存済みWAV/MAT/マニフェストの読み取り診断|
|test_rendered_signal_physics.m|実際の合成波形から減衰・遅延・周波数・回折損失を測定|
|test_ambulance_transitions.m|固定配置10ケース、実サイレンによる境界通過の検証|
|measure_signal_and_path_quality.m|経路・波形の共通測定|
|export_research_validation.m|CSV/MAT/Markdownレポート|
|+researchtest/|判定レコード、障害物フィクスチャ、ケース別保存の補助関数|

## 判定の意味

- PASS：記載された限定的な要件を満たした。
- FAIL：数値要件から外れた、予定したイベントが発生しなかった、またはテスト実行に例外があった。例外はDetail欄で物理的な不一致と区別できます。
- WARN：波形切替に関する診断指標が非ゼロ。可聴クリックの確定判定ではありません。
- NOT_EVALUATED：無効な機能、対象経路なし、情報不足など。合格には含めません。

マスク切替の振幅は、保存された入力と経路から出力サンプリング周波数で推定した診断値です。内部32 kHzの厳密なゲート項や、最終WAVの隣接サンプル差とは異なります。回折境界では、出力の隣接サンプル差を別種の指標として記録します。自然な高周波成分も差を生じるため、単独で音割れとは判定しません。

回折時間伸縮の検査は連続した有効フレームについて、移動速度から求めた滑らかな経路の周波数倍率範囲と比較します。範囲外は別経路をひとつの経路として補間している疑いです。障害物IDだけでは端部の切替まで識別できない制約があります。

回折の人工信号テストは、本体が採用する経路等価のナイフエッジ近似の実装確認です。厳密な直方体回折、UTDや実測値との一致を証明するものではありません。複数反射の存在自体を不合格にはしません。

## 生成物

- `summary.csv`, `report.md`, `report.mat`：全判定と根拠
- `validation_settings.mat`, `code_inventory.csv`：再実行用設定・コード指紋
- `synthetic_measurements.mat`：人工信号の測定用波形
- `saved_dataset/`：既存結果から取得したイベント表・診断値のみ
- `ambulance/AMB_*/`：新しい固定ケースの成分WAV、物理結果MAT、判定CSV、PNG
- `ambulance_progress.csv`：ケース単位の実行途中結果

各WAVは本体の共通固定Pa/full-scaleで保存し、ファイル別の最大値正規化はしません。PNGのスペクトログラムは窓利得未校正のSTFT振幅表示で、SPLやPSDとは異なります。

現状の不具合でFAIL/WARNが出ることは想定内です。本体は修正していません。本体修正後に同じテストを実行し、個々の指標を比較してください。Dataset_001の再生成や、修正前後の自動比較は今回のテストには含めていません。
