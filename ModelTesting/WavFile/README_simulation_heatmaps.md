# シミュレーションWAVのAI評価・ヒートマップ

`EvaluateSimulationHeatmaps.py` は同じフォルダの
`AllAudioClassficationTest_windowed.py` の音声読込・特徴量・推論を再利用します。
既存ファイル、学習モデル、シミュレーションは変更しません。

## 起動

PowerShellで実行:

```powershell
& "C:\Users\cpsla\AudioClassificationProject\.venv\Scripts\python.exe" "C:\Users\cpsla\AudioClassificationProject\ModelTesting\WavFile\EvaluateSimulationHeatmaps.py"
```

1. 評価するWAVフォルダを選択します（サブフォルダも検索）。
2. 学習済み `.keras` / `.h5` を選択します。
3. 全評価窓をサイレンありとする前提、および出力クラス順 `[other, siren]` を確認します。
4. CPA時刻は任意。全音声で最近接時刻が4秒なら `4`。空欄は録音開始基準です。
5. 評価区間は任意。例 `1,8`。空欄は全長です。

**背景のみ・伝搬前の無音・伝搬後の無音を正例として評価しないでください。**
共通の正例区間だけを指定するか、事前に評価対象を分けてください。
異なる音声ごとの正解区間ラベルには未対応です。弱くてもサイレンが存在する区間は正例です。

CLI例（パスは手元のフォルダ・モデルに置換）:

```powershell
& "C:\Users\cpsla\AudioClassificationProject\.venv\Scripts\python.exe" "C:\Users\cpsla\AudioClassificationProject\ModelTesting\WavFile\EvaluateSimulationHeatmaps.py" --input-dir "C:\evaluation_wavs" --model "C:\models\best.keras" --assume-positive --cpa-time 4 --eval-start 1 --eval-end 8
```

`--threshold 0.5` が既定。逆のクラス順は `--class-order siren,other`。
クラス順はモデルの出力次元から判定できないため、学習時のラベルを確認してください。
2クラスの確率出力（合計1）を前提とし、logitsや単一sigmoid出力はエラーにします。
入力特徴量も学習時と一致するモデルを使用してください。

## WAVの配置と条件名

```text
evaluation_wavs/
  engine_idle_80dB/
    ambulance_CPA5m_V020_PV5.04_R080_SEED1.wav
    ambulance_CPA20m_V020_PV5.04_R080_SEED1.wav
    ambulance_CPA5m_V060_PV5.04_R080_SEED1.wav
    ambulance_CPA20m_V060_PV5.04_R080_SEED1.wav
```

- CPA: 最近接距離[m]、V: Source速度[km/h]。この2つは必須です。
- PV: Receiver速度[km/h]。1.4 m/sなら5.04 km/h。`RV`タグは既存パーサーでは認識しません。
- R080: 反射係数0.80。SEEDは反復条件として平均します。
- 他の対応タグは `CONDITION_FILENAMES.md` と既存パーサー参照。
- **比較したい距離・速度のファイルを同じフォルダに入れてください。**
  親フォルダが違う場合は別グループになります。条件別サブフォルダをそのまま指定すると一枚に集まりません。
- 反射係数・Receiver速度など認識済みの他条件が違う場合も別図になります。
- 背景クラス・背景SPLなど未対応タグは自動判別しません。背景条件ごとにフォルダを分け、混在させないでください。
- `final.wav` のままでは条件を取得できず、Errors.csvに記録して除外します。
- 評価対象には最終合成音のみを入れてください。直接音・背景音などの成分WAVを混ぜないでください。
- CPAは名前を信頼します。音声から実距離・速度・最近接時刻を推定しません。

## 図と集計の意味

| 図 | 横軸 | 縦軸 | 色 |
| --- | --- | --- | --- |
| distance_speed_macro_recall.png | 最近接距離[m] | Source速度[km/h] | ファイルごとのRecallの平均[%] |
| distance_speed_micro_recall.png | 最近接距離[m] | Source速度[km/h] | 全窓のTP / (TP+FN)[%] |
| CPA20m_time_detection_rate.png等 | 窓中心時刻[s] | Source速度[km/h] | その時刻の検出ファイル割合[%] |
| CPA20m_time_mean_probability.png等 | 窓中心時刻[s] | Source速度[km/h] | sirenモデル出力の平均[%] |

Recall = TP/(TP+FN)。全窓が正例という条件付き評価で、Precision・誤警報率・Accuracyは求めません。
同じ条件が1ファイルなら、時間別検出率は0%か100%です。
モデル出力値は検出率とは別の指標で、校正済みの確率とは限りません。
時間別は同じ窓中心時刻の反復ファイルを平均し、長さの足りないファイルはその時刻の分母に入れません。
複数ファイルで長さが違うとmacroとmicroは異なります。主図はmacroです。
色尺度は全図0–100で共通、未生成条件は灰色(N/A)、nはファイル数です。
軸は離散条件の等間隔配置で、距離・時刻の間隔を画像上の物理長さとして解釈しないでください。

時間窓は既存実装どおり1秒、ホップ0.5秒です。「瞬間」の判定ではありません。
CPA基準を選ぶ場合は全ファイル共通の幾何学的CPA時刻を引くだけで、音響伝搬遅延を補正しません。
各音声でCPA時刻が異なる場合は共通CPA指定をせず、別に評価してください。
最初の検出時刻には窓開始と、判定可能になる窓終了の両方を保存します。

## 出力

既定: 選択フォルダの隣の `AI_heatmap_results/evaluation_日時_ID/`。
`--output-dir` で出力親フォルダを変更できます。既存結果は上書きしません。

- Summary.csv: 各音声のRecall、TP/FN、平均出力、条件、入力SHA256。
- WindowResults.csv: 全評価窓の時刻、出力値、検出判定、条件。
- DistanceSpeedResults.csv / TimeResults.csv: 図の元の集計表。
- heatmaps/Gxxx/: PNG、行列CSV、ファイル数CSV。
- settings.json: グループの条件、モデル・コードSHA256、前処理・評価設定。
- Errors.csv: 名前の不備や推論失敗（空ならエラーなし）。
- completion.json: 成功件数、未処理件数、中断の有無、図作成の完了状態。

1ファイルの失敗で他を止めません。全件成功の判定にはErrors.csvとcompletion.jsonを確認してください。
Ctrl+Cでは完了したファイルを保存しますが、強制終了・OS停止には保存を保証しません。

## 前処理と制限

既存の16kHzモノラル、128 mel、FFT1024、STFTホップ512、20–8000Hz、
各窓の最大値基準dB化・平均標準偏差による正規化をそのまま使用します。
従ってWAVの物理SPLを直接入力する方式ではありません。背景とのSNRは残りますが、
一様な音量差は前処理で概ね除かれます。これは学習側との整合を優先した仕様です。
1秒未満はゼロ埋め、最後の不完全窓は除外という既存仕様も継承します。
LoadedDuration_sはゼロ埋め後の長さです。短すぎる音源は事前に除外することを推奨します。

## 回帰テスト

```powershell
& "C:\Users\cpsla\AudioClassificationProject\.venv\Scripts\python.exe" "C:\Users\cpsla\AudioClassificationProject\ModelTesting\WavFile\test_simulation_heatmaps.py"
```

確率検証、macro/micro集計、評価区間・CPA時刻、既存前処理、Keras保存読込、
WAV一括推論、条件分離、欠損セル、CSV/PNG出力、クラス順を検証します。
`heatmap_test_outputs/TEST_*` 内のモデルは一定値を返す**動作確認用**で、研究評価には使えません。
テスト音声は2秒の合成正弦波であり、実際の救急車分類精度を検証するものではありません。
