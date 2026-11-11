# 固定YAMNet＋LSTM：交差検証なしの学習

新規の`TrainTransferLearning_Mix.py`で、1回のTrain / Validation / Test分割による学習を行います。既存の`TrainTransferLearning.py`と4-fold版、CRNNのコード・結果は変更しません。

## 対象と分割

- データは`CudaTrain/data/Mixed_US8K_ESC50_dataset/04_silence_filtered`のaccepted音声のうちfold1～4のみです。**Fold5・除外音声は使用しません。**
- CRNNの`runs_crnn_slidwindow_1p_holdout_2Class_mix/split_manifest.csv`があれば、音声パス・元音源ID・クラス・foldを検証し、所属をそのまま再利用します。元データと違う場合は停止し、黙って別分割へ切り替えません。
- 保存済みCRNN分割がない場合だけ、同じ共有関数を使い、seed=42・元音源単位・クラス層化でTest 20%、残りからValidation 10%に分けます。元音源数ベースで概ねTrain 72% / Validation 8% / Test 20%です。窓数の比率ではありません。
- 特定の分割を必須にする場合は`--split-manifest`でファイルを明示します。明示したファイルがなければ停止します。分割の生成はライブラリ版にも依存し得るため、厳密な比較には保存manifestの再利用を推奨します。
- 元音源の重複・音声の重複・欠落・各集合でのクラス欠落を検査します。

## 特徴量とモデル

親フォルダの`YAMNetFeatures/fold1.npz`～`fold4.npz`を再利用します。既存の4-fold版の読込処理で、音声内容のSHA-256や元音源IDとの対応を検証します。保存済み特徴量がない場合は、先に親フォルダの`ExtractYAMNetFeatures.py`を実行してください。

YAMNetは固定のまま、4-fold版と同じ2段BiLSTM（64、64）＋Dense 64＋Dropout 0.5＋2クラス出力を学習します。Adam 1e-4、batch=32、最大100epoch、EarlyStoppingはval_loss・patience=5です。クラス重みは4-fold版と同じく使いません。

Validation lossが最小の`best.keras`を読み直してからTestを評価し、その重みを`final.keras`に保存します。Testは学習・EarlyStoppingに使いません。保存モデルはLSTM分類器だけなので、新しい音声を推論する際は、固定YAMNetでの特徴抽出も必要です。

## 実行

Ubuntuの`CudaTrain/Train/AudioClassificationTrain`で、まず分割だけを確認できます。この確認は特徴量をロードせず、結果ファイルも作成しません。

```bash
python Without9Fold/TrainTransferLearning_Mix.py --check-only
```

特徴量が準備済みなら、そのまま学習します。

```bash
python Without9Fold/TrainTransferLearning_Mix.py
```

不足しているライブラリは、使用中の学習環境にインストールしてください。必要なのはNumPy、TensorFlow、scikit-learn、matplotlib、seabornです。特徴抽出の追加依存関係は親フォルダの`YAMNetFeatures/README.md`を参照してください。

## 出力

既定出力は`CudaTrain/Result/runs_transferlearning_holdout_2Class_mix`です。空でない既存フォルダには上書きせず停止します。再実行は新しい保存先を指定します。

```bash
python Without9Fold/TrainTransferLearning_Mix.py --result-dir ../../Result/runs_transferlearning_holdout_trial2
```

保存内容：分割manifest、クラス対応、学習設定（分割元・実際の窓数／元音源数を含む）、history.csv、学習曲線、採用epoch、best.keras、final.keras、Test指標、混同行列、音声ごとの予測CSV。

CRNNとはTestの音声をそろえられますが、前処理・クラス重み・モデル選択基準は異なります。また、このホールドアウト結果は4-fold平均とは別枠で報告してください。Fold5による最終評価はこのスクリプトでは実施しません。

## テスト

親フォルダで次を実行します。

```bash
python -m unittest discover -s Without9Fold -p test_transferlearning_holdout.py -v
```

通常テストは分割を確認するもので、実データの学習は開始しません。TensorFlow等がある環境で小さな合成特徴量による学習も確認する場合は、`YAMNET_HOLDOUT_SMOKE=1`を設定して実行します。

実装時はWindows CPU・TensorFlow 2.19.1の一時環境で、合成特徴量による1回の学習・評価・最良重みの保存復元を含む10件のテストが通過しました。実データのCRNN保存分割と全窓の所属が一致し、Train 6,761窓／435元音源、Validation 1,149窓／49元音源、Test 2,326窓／121元音源であることも確認しました。実データの学習は未実行です。
