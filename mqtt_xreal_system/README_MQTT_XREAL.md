# Jetson -> MQTT -> Beam Pro -> XREAL Air 2 Ultra

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
