import json
import time
import paho.mqtt.client as mqtt

# MqttReceiver.cs と同じ設定
BROKER_ADDRESS = "133.49.27.137"
BROKER_PORT = 1883
TOPIC = "research/ambulance/v1/state"

# MQTTクライアント作成
client = mqtt.Client(client_id="JetsonPublisher")

try:
    # MQTTブローカーへ接続
    client.connect(BROKER_ADDRESS, BROKER_PORT, 60)
    client.loop_start()

    print(f"Connected to MQTT broker: {BROKER_ADDRESS}:{BROKER_PORT}")

    while True:
        # テストデータ
        data = {
            "detected": True,
            "direction": 45.0,
            "confidence": 0.92
        }

        payload = json.dumps(data)

        result = client.publish(
            TOPIC,
            payload,
            qos=0
        )

        result.wait_for_publish()

        print(f"Published: {payload}")

        time.sleep(1)

except KeyboardInterrupt:
    print("\nStopping MQTT publisher...")

except Exception as e:
    print(f"MQTT error: {e}")

finally:
    client.loop_stop()
    client.disconnect()
    print("Disconnected")