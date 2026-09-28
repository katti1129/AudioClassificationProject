# MQTT v1

- Broker：Jetson Mosquitto。Jetsonの初期接続先127.0.0.1:1883。
- Beam Pro：InspectorのBroker Hostへ**JetsonのLAN IP**を設定。初期値192.168.1.50は例。
- Topic：`research/ambulance/v1/state`
- MQTT 3.1.1 / QoS 0 / retain false / clean session。
- Publish：約0.10秒。Unity stale timeout：受信単調時刻から1.5秒。

```json
{"version":1,"detected":true,"class_name":"siren","confidence_pct":98.1,"doa_deg":274.0,"rms":0.041,"inference_ms":23.8,"timestamp_ms":1787832000000}
```

| フィールド | 意味 |
| --- | --- |
| version | 1固定。他バージョンは拒否 |
| detected | Jetsonの最終サイレン検知bool。UnityはAI判定をやり直さない |
| class_name | siren / other / silence等、空でない文字列 |
| confidence_pct | 0〜100、分類モデルの出力。校正済み確率とは限らない |
| doa_deg | 生の頭部相対DOA。0以上360未満、−1はUnknown。受信側はすべての負値をUnknownとして扱う |
| rms | 音声RMS、非負 |
| inference_ms | 既存の推論パイプライン経過時間、非負 |
| timestamp_ms | Publish時Unixミリ秒。DOA個別の計測時刻ではない |

全フィールド必須。NaN/Infinity、型違い、範囲違い、同名キー重複、4KB超を拒否。既存基準版の簡易JSON `direction/confidence` とは異なり、自動で推測変換しない。基準版を試す時はその既存Publisherを使うこと。

MQTTコールバックは文字列・単調受信時刻をキューへ入れるだけ。JSONとUnityオブジェクトの処理はLateUpdate。最大16件で古いキューを捨てる。retainedメッセージは拒否。接続世代が変わると警告状態と方向を破棄し、再Subscribe後の新規データから再開する。

同一接続内でtimestampが前回以下の重複・逆順データを受け付けず、鮮度も更新しない。送信側時計が後退した場合は時刻が追いつくか再接続するまで拒否される。送受信の時計同期を前提にした絶対時刻期限判定は行わないため、LAN経由の初回遅延パケットは受信時起点となる。この制約も含めて実機で遅延を測定する。

| 状態 | HUD警告 | 3D矢印 |
| --- | --- | --- |
| 新鮮・detected true・既知DOA・有効追跡 | 表示 | 表示 |
| 新鮮・detected true・Unknown DOA | 表示＋Unknown | 非表示 |
| 新鮮・detected true・追跡無効 | 表示＋追跡状態 | 非表示 |
| detected false | 非表示 | 非表示 |
| 切断または1.5秒無更新 | 非表示 | 非表示 |

不正JSONは最後の正常データの受信時刻を更新しない。TCP切断を検出する前でも1.5秒の鮮度期限で消える。JetsonのAI/音声が停止した場合は最大1秒以内に送信停止、その最後の送信から1.5秒以内にUnity表示が消える。

## 通信試験

Jetsonで既存Mosquitto設定を使用（信頼できる実験LAN向け匿名設定）。

```bash
mosquitto_sub -h 127.0.0.1 -t 'research/ambulance/v1/state' -v
python -m mqtt_xreal_system.Jetson_Final.tests.mqtt_test_publisher --broker 127.0.0.1
```

Front / Right / Back / Left / Unknown / Offを3秒ごとに切替え、各状態は10Hzで再送する。Ctrl+Cで停止し、staleを確認。旧テストPublisherの2秒間隔だと1.5秒staleが先に発生する点に注意。ブローカー停止→再起動後に再接続・再Subscribeを確認する。

Unity自動テストにはMQTTnetの一時的なlocalhostブローカーを使うTCP疎通・再接続試験が含まれる。これはJetson Mosquitto、Wi-Fi、Beam Proの実機試験の代替ではない。

再開後の試験では不正JSONもTCPで送信し、受信後に拒否して接続を維持することを確認した。QoS 0 / retain falseはJetsonの既存Publisherテストで呼出し引数を検証し、UnityのSubscribeはQoS 0を明示している。
