# YAMNet部分ファインチューニング（4-fold）

既存の`TrainTransferLearning_4Fold.py`（固定YAMNet特徴量＋LSTM）は変更せず、別の実験として実行します。

## 実行

Ubuntuで現在使っているTensorFlow環境を有効にして、`CudaTrain/Train/AudioClassificationTrain`で実行します。

```bash
python TrainTransferLearning_PartialFineTuning_4Fold.py
```

必要なライブラリはTensorFlow、**同じminorバージョンのtf-keras**、NumPy、soundfile、scikit-learn、matplotlibです。この版自体はtensorflow-hub・tqdmを必要としません。
TensorFlow 2.19を使う環境での例（違う版のTensorFlowにはそのまま適用しないでください）：

```bash
python -m pip install "tensorflow==2.19.*" "tf-keras==2.19.*" soundfile scikit-learn matplotlib
python -m pip check
```

公式YAMNetはKeras 2対応のため、コード全体で`tf_keras`を使用します。通常のKeras 3モデルと混ぜません。
GPUの対応状況は既存のTensorFlow環境に依存します。起動時に認識したGPUを表示し、認識されなければCPUで実行します。

## 学習条件

- 入力：`CudaTrain/data/Mixed_US8K_ESC50_dataset/04_silence_filtered`のmanifestにあるaccepted音声。fold1～4のみ使用し、fold5・除外音声は使いません。
- 各回のTestは1つのfold。残り3foldから、元音源ID単位・クラス層化・seed=42・Validation割合0.1で分割します。既存の特徴抽出型と同じ分割関数です。
- 分類器は既存と同じ2段BiLSTM（64、64）＋Dense 64＋Dropout 0.5＋2クラス出力です。クラス重みや追加のデータ拡張は加えません。
- 段階1：YAMNet全層固定。分類器をAdam、学習率1e-4、最大100epochで学習します。
- 段階2：段階1の最良重みから、YAMNetの**layer13、layer14の畳み込み層**と分類器をAdam、学習率1e-5、最大30epochで学習します。Batch Normalizationは全層固定・推論モードです。変更後は新しいoptimizerで再compileします。
- 両段階ともEarlyStoppingは`val_loss`、patience=5。段階ごとに待ち回数をリセットし、**両段階を通じた最小val_loss**の重みで一度だけTestを評価します。部分更新で悪化した場合は段階1のモデルを採用します。Testの成績ではモデルを選択しません。
- foldごとに公式の事前学習重みから作り直します。他foldで更新した重みを使い回しません。
- バッチサイズは32。メモリ不足時は`--batch-size 8`などで下げられますが、比較実験の学習条件の差として記録してください。

## 特徴量と重み

固定された最終埋め込み`YAMNetFeatures/fold*.npz`は**使いません・変更しません**。音声から公式と同じパディング・STFT・log-melパッチを計算し、更新可能なYAMNet本体を通します。1秒音声は公式の末尾パディングにより2パッチになります。入力は16kHz・モノラル・16000サンプルを検証し、不一致を黙って切り詰めません。

公式の`yamnet.h5`を初回だけ`YAMNetFeatures/pretrained/yamnet.h5`にダウンロードします。オフラインでは、あらかじめ用意した公式ファイルを指定できます。

```bash
python TrainTransferLearning_PartialFineTuning_4Fold.py --weights /path/to/yamnet.h5
```

部分ファインチューニングの成功は、固定特徴量版の結果を上回ることを保証しません。Keras実装・初期化・バッチ順等の差により、段階1だけでも以前の固定特徴量版と完全に同じスコアになるとは限りません。

## 出力と再実行

既定出力は`CudaTrain/Result/runs_transferlearning_partial_finetuning_fold1to4`です。既存の結果を上書きしないため、空でない出力先では停止します。再実行するときは新しい名前を指定してください。

```bash
python TrainTransferLearning_PartialFineTuning_4Fold.py --result-dir ../../Result/runs_yamnet_partial_trial2
```

各foldに`split_manifest.csv`、`history_head.csv`、`history_fine_tune.csv`、通算epoch（1始まり）の`history.csv`、学習曲線、`trainable_yamnet_layers.json`、`model_selection.json`、`test_metrics.json`、混同行列、`best.weights.h5`、`final.keras`を保存します。
`final.keras`は選択済みのYAMNet本体と分類器を含むモデルです。モデル選択で段階1が採用される場合もあります。ルートには設定・公式重みのSHA-256・各fold指標・平均と母標準偏差（ddof=0）を保存します。

モデル読み込みは、このディレクトリをPythonのimportパスに置いて実行します。

```python
import yamnet_finetuning  # custom frontendを登録
import tf_keras as keras

model = keras.models.load_model("/path/to/fold1/final.keras", compile=False)
# 入力: float32の(batch, 16000)波形。出力順はtraining_config.jsonのlabel_map。
```

## 動作確認テスト

```bash
python -m unittest test_yamnet_partial_finetuning -v
```

テストではランダム重みで構造・勾配・凍結・保存復元・2段階の最良モデル選択を確認します。公式重みとのHub出力比較を有効にする場合だけ、次も指定します（tensorflow-hubと初回ネットワーク接続が必要）。

```bash
YAMNET_TEST_PRETRAINED=1 python -m unittest test_yamnet_partial_finetuning -v
```

この追加テストでHub 0.16.1のimportが`No module named 'pkg_resources'`で止まる環境では、比較テスト用の環境で`python -m pip install "setuptools<81"`を実行してください。通常の部分ファインチューニング処理にはHubもpkg_resourcesも不要です。

実データ4-foldの学習をテストが代わりに実施することはありません。

実装時は、独立した一時環境のTensorFlow 2.19.1 / tf-keras 2.19.0（Windows CPU）で通常テスト7件と公式Hubとの特徴量同等性テスト1件が通過しました。既存の4-fold結果との分割一致も確認しています。実データでの学習やUbuntu/GPUでの実行を完了したという意味ではありません。

## 参考実装

- [TensorFlow公式YAMNet（モデル・前処理・重み）](https://github.com/tensorflow/models/tree/master/research/audioset/yamnet)
- [Keras公式Transfer learning / fine-tuningガイド](https://keras.io/guides/transfer_learning/)

`yamnet_finetuning.py`のYAMNet構造・前処理は上記公式実装（Apache-2.0）をバッチ入力向けに適応したものです。
