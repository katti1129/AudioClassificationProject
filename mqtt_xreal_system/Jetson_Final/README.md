# Jetson完成版

ReSpeaker音声・DOA、既存CRNN、PySide6 GUI、MQTT、非同期CSVログを1つのエントリーポイントへ統合しています。`System/` と既存 `Jetson/` は変更しません。

## 起動

Jetson上の**既存の推論が動作しているPython 3.10以降の環境**を有効化してください。TensorFlowはJetPack対応版をそのまま使用します。一般PC向けTensorFlow wheelへ置き換えないでください。

リポジトリルートで：

```bash
python -m pip install -r mqtt_xreal_system/Jetson_Final/requirements.txt
python -m mqtt_xreal_system.Jetson_Final.app.realtime_xreal_system \
  --model /absolute/path/to/best.keras \
  --broker 127.0.0.1 --port 1883 \
  --topic research/ambulance/v1/state \
  --interval 0.10 --log-dir ./experiment_logs
```

モデルパスは必須です。元コードのMac専用パスを引き継いで起動しません。`--log-dir` を省略するとCSVはOFF。`--result-ttl 1.0` がAI結果の再送可能な上限秒数です。GUIとCtrl+Cで停止でき、MQTTとログを終了処理します。

GUIではAI状態、Confidence、DOA、RMS、推論パイプライン時間に加え、MQTT接続、AI鮮度、CSV状態・ドロップ数を表示します。デスクトップセッションが必要です。

ReSpeaker USB IDは2886:0018、音声デバイス名にはReSpeakerを含むものを使用。16kHz / mono / 2048サンプルで録音します。PortAudio、libusb、USB権限、Qtの依存ライブラリは既存Jetson環境の設定を利用してください。DOAだけ取得できない場合は音声分類を継続し、−1を送ります。

## ファイル

- `app/realtime_xreal_system.py`：起動・既存GUIとの統合
- `app/legacy_gui.py`：既存GUI／前処理／推論の専用コピー（改善点は構成資料参照）
- `app/tuning.py`：既存USB制御の専用コピー
- `app/decision.py`：サイレンのヒステリシス
- `app/state_relay.py`：新鮮な音声・推論結果だけを渡す共有状態
- `mqtt/mqtt_bridge.py`：既存Paho Publisherを再利用・堅牢化
- `telemetry/experiment_logger.py`：非同期CSV。標準ライブラリloggingと衝突しない名称
- `telemetry/latency_probe.py`：任意の遅延計測。音声開始推定・推論・送信の照合情報と時計合わせ
- `config/config.py`：CLI設定
- `tests/`：単体テストと実通信用Publisher

## テスト

```bash
python -m unittest discover -s mqtt_xreal_system/Jetson_Final/tests -p 'test_*.py' -v
python -m mqtt_xreal_system.Jetson_Final.tests.mqtt_test_publisher --broker 127.0.0.1
```

前者はML・USB・GUIを起動しない単体テストで、Paho接続をモックしています。後者は実MQTT通信です。Unity側と合わせた使い方は [MQTT仕様](../docs/mqtt_protocol.md)、変更理由は [構成資料](../docs/system_architecture.md)、従来の検証状況は [検証報告](../docs/verification.md) を参照してください。

2026-09-26時点で既存10テストが成功。2026-10-15に計測モードを追加しました。ReSpeaker・CRNN・GUIの実機確認はJetson上で別途実施してください。

## 任意の遅延計測

起動時に `--measure-latency` を付けると、計測専用MQTT通信・時計合わせを開始します。既定OFF。
`--latency-onset-threshold 0.01` と `--latency-quiet-seconds 1.0` で音の立ち上がり検出を調整できます。
Unity側でもMeasure LatencyをONにして再ビルドが必要です。計測CSVはUnity側へ保存され、従来の `--log-dir` とは独立しています。
静かな環境でサイレンを単独提示する実験用です。[起動・測定・CSV回収手順](../docs/software_latency_measurement.md)を参照してください。
