"""Hardware-free v1 integration sender; each state repeats at 10 Hz (not stale)."""
import argparse
import math
import time
from ..mqtt.mqtt_bridge import SirenMqttPublisher


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--broker", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1883)
    parser.add_argument("--topic", default="research/ambulance/v1/state")
    parser.add_argument("--head-yaw", type=float, default=0, help="For a fixed World Front test: raw=normalize(270+yaw)")
    args = parser.parse_args()
    publisher = SirenMqttPublisher(broker_host=args.broker, broker_port=args.port, topic=args.topic, min_publish_interval=.09)
    cases = [("Front", 270), ("Right", 180), ("Back", 90), ("Left", 0), ("Unknown", -1), ("Off", 270)]
    print("Cases change every 3 s. Ctrl+C stops traffic to test 1.5 s stale timeout.")
    started = time.monotonic()
    try:
        while True:
            index = int((time.monotonic() - started) / 3) % len(cases)
            name, doa = cases[index]
            if doa >= 0: doa = (doa + args.head_yaw) % 360
            publisher.publish_state(final_class="other" if name == "Off" else "siren", confidence_pct=98.1,
                                    doa_deg=doa, rms=.041, inference_ms=23.8)
            time.sleep(.1)
    except KeyboardInterrupt: pass
    finally: publisher.close()


if __name__ == "__main__": main()
