# YAMNet特徴量キャッシュ

`ExtractYAMNetFeatures.py`で、固定したYAMNetの1024次元埋め込みをこのフォルダへ保存します。

- 入力：`CudaTrain/data/Mixed_US8K_ESC50_dataset/04_silence_filtered/manifest.csv`
- 対象：fold1～fold4の`accepted`音声。fold5と`_excluded`は対象外です。
- 保存ファイル：`fold1.npz`、`fold2.npz`、`fold3.npz`、`fold4.npz`
- 内容：特徴量、実際のフレーム数、相対音声パス、クラス名、元音源ID、Fold、音声のSHA-256、モデルURL、サンプリング周波数。
- ゼロパディングしたfloat32配列として保存します。pickleは使用しません。

プロジェクトのルートから実行します。

```bash
python CudaTrain/Train/AudioClassificationTrain/ExtractYAMNetFeatures.py
python CudaTrain/Train/AudioClassificationTrain/TrainTransferLearning_4Fold.py
```

既存キャッシュはデータと対応することを検証して再利用します。音声・ラベル・元音源ID・Foldが変わった場合は停止します。

```bash
python CudaTrain/Train/AudioClassificationTrain/ExtractYAMNetFeatures.py --check-only
python CudaTrain/Train/AudioClassificationTrain/ExtractYAMNetFeatures.py --overwrite
```

`--overwrite`は各Foldのキャッシュを再抽出して置き換えます。キャッシュは相対音声パスと音声内容で検証するため、同じデータならWindowsとUbuntu間で移して使用できます。

必要なライブラリはNumPy、TensorFlow、tensorflow-hub、librosa、soundfile、scikit-learn、tqdmです。学習・グラフ保存にはmatplotlibとseabornも必要です。初回抽出時にはYAMNetのダウンロードが必要です。

4-fold版は既存Foldを評価に使用し、残り3Foldの元音源ID単位でTrain/Validationを分割します。元の2段BiLSTM分類器を維持し、`val_loss`最小の重みで独立したTest Foldを評価します。結果は`CudaTrain/Result/runs_transferlearning_fold1to4`へ保存します。

このキャッシュは固定YAMNet方式用です。YAMNet本体をファインチューニングする際は、固定した最終埋め込みだけでなく、音声などを本体へ入力して重みを更新する別の学習処理が必要です。
