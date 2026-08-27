"""Send deterministic test states from Jetson to Beam Pro/XREAL.

With the current ReSpeaker direction mapping in the research GUI:
  270 deg -> screen up/front
  180 deg -> screen right
   90 deg -> screen down
    0 deg -> screen left
"""

import time

from mqtt_bridge import SirenMqttPublisher


def main() -> None:
    pub = SirenMqttPublisher(broker_host="127.0.0.1")

    print("Waiting briefly for the local MQTT broker...")
    deadline = time.time() + 5.0
    while not pub.connected and time.time() < deadline:
        time.sleep(0.1)

    if not pub.connected:
        print("[Error] Broker connection was not established.")
        pub.close()
        return

    tests = [
        (270, "front/up"),
        (180, "right"),
        (90, "down"),
        (0, "left"),
    ]

    try:
        while True:
            for doa, label in tests:
                print(f"Send: siren=True, DOA={doa} deg ({label})")
                pub.publish_state(
                    final_class="siren",
                    confidence_pct=95.0,
                    doa_deg=doa,
                    rms=0.050,
                    inference_ms=25.0,
                    force=True,
                )
                time.sleep(2.0)

            print("Send: detected=False")
            pub.publish_state(
                final_class="other",
                confidence_pct=90.0,
                doa_deg=-1,
                rms=0.020,
                inference_ms=25.0,
                force=True,
            )
            time.sleep(2.0)
    except KeyboardInterrupt:
        pub.publish_state(
            final_class="silence",
            confidence_pct=100.0,
            doa_deg=-1,
            force=True,
        )
    finally:
        pub.close()


if __name__ == "__main__":
    main()
