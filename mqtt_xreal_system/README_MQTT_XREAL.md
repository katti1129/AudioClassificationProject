# Jetson -> MQTT -> Beam Pro -> XREAL Air 2 Ultra

## 完成版システム（2026-09-26）

実機版は基準版から分離しています。最初にこちらを参照してください。

| 場所 | 役割 |
| --- | --- |
| [Jetson_Final](Jetson_Final/README.md) | ReSpeaker / CRNN / PySide6 / MQTT / CSVを統合した起動入口 |
| [BeamPro_Final](../unity/MQTT_BeamPro/BeamPro_Final/README.md) | Unity 6000.0.55f1、XREAL SDK、6DoF、World Space 3D矢印 |
| [Mosquitto](Mosquitto/xreal-local.conf) | 既存の実験LAN用Broker設定（変更なし） |
| [Web_AR_Mockup](Web_AR_Mockup/README.md) | デザイン参照元（今回変更なし） |
| [構成](docs/system_architecture.md) / [MQTT仕様](docs/mqtt_protocol.md) / [校正](docs/calibration.md) | 技術資料 |
| [検証報告](docs/verification.md) | 実行済みテスト・ビルド結果・残る実機確認 |

必要機材はJetson Orin Nano、ReSpeaker USB Mic Array v2.0、Beam Pro、XREAL Air 2 Ultra、固定用ヘルメットと同一Wi-Fi/LANです。

再開後の確認：Jetson既存10テスト成功、Unity21テスト成功（保存済みSceneのPlay Modeを含む）、Android ARM64 APK生成成功・エラー0。既存正常版185ファイルはSHA256一致。実機未接続のためReSpeaker推論／Beam Pro＋Air 2 Ultraの6DoF／Wi-Fi総合確認は未実施です。SDK由来の残る警告は[検証報告](docs/verification.md)に記載しています。

### 起動の順序

1. Jetsonの既存推論環境と学習済みモデルを用意し、ReSpeakerを接続。
2. 下記の既存Mosquitto起動手順を実施。`hostname -I` でLAN IPを確認。
3. リポジトリルートで `python -m mqtt_xreal_system.Jetson_Final.app.realtime_xreal_system --model /path/best.keras --broker 127.0.0.1 --log-dir ./experiment_logs` を実行。
4. Unity Hubで **`unity/MQTT_BeamPro/BeamPro_Final/`** を6000.0.55f1で開き、`Assets/AmbulanceAR/Scenes/AmbulanceARScene.unity` を選択。
5. `Ambulance System > AmbulanceMqttSubscriber > Broker Host` をJetsonのLAN IPへ変更してSceneを保存。
6. Editor PlayでSimulationを確認。Back→Head Yaw180°、検知OFF、Unknown、Stop packetsを試す。
7. `Ambulance AR > 3. Build Beam Pro APK`。生成先 `Builds/AmbulanceAR.apk`。
8. `adb devices` でBeam Proを確認し、`adb install -r <APKのパス>`。
9. Air 2 UltraをBeam Proへ接続し、MyGlassesからAmbulance ARを起動。頭部追跡・LAN通信を確認。
10. [校正手順](docs/calibration.md)に従い、正面・右・後・左と頭部回転を試す。

XREAL SDKは作業PCにあった3.0.0-pre.4を完成版へ埋込済み。Unity 6000.0.xが[公式対応範囲](https://docs.xreal.com/Getting%20Started%20with%20XREAL%20SDK)であることを確認し、MODE_6DOF / REALITY / OpenGL ES3 / IL2CPP / ARM64 / INTERNETを構成しています。公開版3.1.0との差と確認できた範囲は検証報告に記載しています。

### トラブルシューティング

- MQTT接続不能：同じLAN、Broker起動、IP・1883、APの端末間通信制限を確認。Beam Proの127.0.0.1はJetsonではありません。
- 接続済みでもstale：v1形式・0.1秒周期を確認。既存簡易JSONは完成版では拒否します。[完成版テストPublisher](Jetson_Final/tests/mqtt_test_publisher.py)を使用。
- 警告だけで矢印なし：DOA −1、USB権限、6DoF追跡、XREAL Loaderを確認。後方音源は振り返るまで見えません。
- 左右逆／正面が違う：初期Invert=true / Offset=270°を基準に実機校正。
- 頭を回すと方向が揺れる：DOAと姿勢の時間差、LAN遅延、反射音、Pose Lookbackと平滑化を確認。
- モデルが読めない：`--model`、JetPack対応TensorFlow、既存モデルの前処理・クラス順を確認。
- Editorでは見えるが実機で表示されない：6DoF/REALITY、MyGlassesからの起動、権限、追跡状態を確認。SimulationはAPKでは無効です。

以下は**既存MQTTプロトタイプの資料**です。基準版の起動・経緯を保存するため残しています。完成版では上記のSceneとエントリーポイントを使用してください。

---

## Target message

Topic:

```text
research/ambulance/v1/state
```

Payload example:

```json
{"version":1,"detected":true,"class_name":"siren","confidence_pct":98.1,"doa_deg":274.0,"rms":0.041,"inference_ms":23.8,"timestamp_ms":1787832000000}
```

`doa_deg = -1` means unknown.

---

## 1. Jetson: Mosquitto broker

```bash
sudo apt update
sudo apt install -y mosquitto mosquitto-clients
sudo cp Mosquitto/xreal-local.conf /etc/mosquitto/conf.d/xreal-local.conf
sudo systemctl restart mosquitto
sudo systemctl enable mosquitto
sudo systemctl status mosquitto
```

This sample config uses `allow_anonymous true`. Use it only on a private/trusted experimental LAN. Add authentication before using an untrusted network.

Find the Jetson IP that Beam Pro will use:

```bash
hostname -I
```

Example: `192.168.1.50`.

Test the broker on Jetson:

Terminal A:

```bash
mosquitto_sub -h 127.0.0.1 -t 'research/ambulance/v1/state' -v
```

Terminal B:

```bash
cd Jetson
python -m pip install paho-mqtt
python mqtt_test_publisher.py
```

You should see a JSON message every 2 seconds.

---

## 2. Beam Pro / Unity: install MQTTnet

The existing project is Unity 6000.0.55f1.

### Install NuGetForUnity

Unity -> Window -> Package Manager -> `+` -> `Add package from git URL...`

```text
https://github.com/GlitchEnzo/NuGetForUnity.git?path=/src/NuGetForUnity
```

Then open:

```text
NuGet -> Manage NuGet Packages
```

Install exactly:

```text
MQTTnet 4.3.7.1207
```

Do not automatically switch this prototype to MQTTnet 5.x: 5.2 targets .NET 8+, while MQTTnet 4.3.7 provides .NET Standard targets suitable for Unity's compatibility profile.

Copy:

```text
Unity/Assets/Scripts/SirenMqttSubscriber.cs
```

into the existing Unity project's:

```text
Assets/Scripts/
```

---

## 3. Unity HUD setup

Create a head-locked HUD first. A simple hierarchy is:

```text
XR Origin / Main Camera
└── AmbulanceHud   (World Space Canvas; place in front of the camera)
    ├── AlertRoot
    │   ├── Arrow  (Image; the source sprite points UP)
    │   ├── StatusText
    │   ├── ConfidenceText
    │   └── DirectionText
    └── ConnectionText
```

Add an empty GameObject named `MqttManager` and attach `SirenMqttSubscriber`.

Inspector:

```text
Broker Host = Jetson's IP (example: 192.168.1.50)
Broker Port = 1883
Topic       = research/ambulance/v1/state
DOA To UI Offset Deg = 90
Invert DOA = false
```

Assign AlertRoot, Arrow and the TMP text objects to the script.

The `90°` offset matches the current Python GUI mapping:

```text
ReSpeaker 270° -> ↑ front
ReSpeaker 180° -> → right
ReSpeaker  90° -> ↓
ReSpeaker   0° -> ← left
```

If the physical mounting direction of ReSpeaker changes, calibrate this offset experimentally.

For Android/Beam Pro, ensure the app has Internet/network permission. In Unity Player Settings, `Internet Access = Require` is the simplest way to force the Android INTERNET permission for this prototype.

---

## 4. Test before connecting the AI

1. Put Jetson and Beam Pro on the same local Wi-Fi/LAN.
2. Start Mosquitto on Jetson.
3. In Unity Inspector, enter the Jetson IP.
4. Build/install the XREAL app on Beam Pro and run it with Air 2 Ultra.
5. Run:

```bash
cd Jetson
python mqtt_test_publisher.py
```

Expected display cycle:

```text
DOA 270 -> ↑
DOA 180 -> →
DOA  90 -> ↓
DOA   0 -> ←
detected false -> AlertRoot hidden
```

Only after this works, connect the existing CRNN/DOA code.

---

## 5. Integrate with RealtimeAudioClassificationSystem_GUI.py

Install on the Jetson virtual environment:

```bash
python -m pip install paho-mqtt
```

Place `mqtt_bridge.py` next to `RealtimeAudioClassificationSystem_GUI.py`.

### A. Add import

```python
from mqtt_bridge import SirenMqttPublisher
```

### B. Add a global

Near the existing globals:

```python
mqtt_publisher = None
```

### C. Initialize in `main()`

Add `mqtt_publisher` to the `global` declaration:

```python
def main():
    global model, is_running, mic, mqtt_publisher
```

Then, before starting the inference thread:

```python
mqtt_publisher = SirenMqttPublisher(
    broker_host="127.0.0.1",  # broker runs on the same Jetson
    broker_port=1883,
    topic="research/ambulance/v1/state",
    min_publish_interval=0.10,
)
```

### D. Publish in the existing `update_gui_state()`

Replace the existing function with:

```python
def update_gui_state(final_class, confidence, rms, latency):
    global gui_final_class, gui_confidence, gui_rms, gui_latency, mqtt_publisher

    with gui_lock:
        gui_final_class = final_class
        gui_confidence = float(confidence)
        gui_rms = float(rms)
        gui_latency = float(latency)

    if mqtt_publisher is not None:
        mqtt_publisher.publish_state(
            final_class=final_class,
            confidence_pct=float(confidence),
            doa_deg=get_current_direction_value(),
            rms=float(rms),
            inference_ms=float(latency) * 1000.0,
        )
```

This uses the same `final_class`, confidence percentage, RMS, inference latency and `current_direction` that the current GUI already uses.

### E. Close MQTT on shutdown

Update the existing `shutdown()`:

```python
def shutdown(app=None):
    global is_running, mqtt_publisher
    print("\n停止します...")
    is_running = False

    if mqtt_publisher is not None:
        mqtt_publisher.close()
        mqtt_publisher = None

    if app is not None:
        app.quit()
```

---

## 6. Why QoS 0 / retain false in this prototype

The HUD wants the newest state, not an old alarm. Therefore the prototype sends frequent small state messages with QoS 0 and `retain=False`, and the Unity side hides an alert when no fresh state arrives for 1.5 seconds.

For later field evaluation, authentication/TLS and QoS choice should be decided from the required reliability and network conditions.

---

## 7. After the MQTT prototype works

Keep the first version head-locked. Then add Air 2 Ultra 6DoF so the AR indication can remain aligned to a real-world direction while the user turns their head. That step requires defining the coordinate relationship between the ReSpeaker mounting direction and the Air 2 Ultra tracking frame; MQTT itself does not solve that coordinate transform.
