"""Synthetic input for Unity's localhost integration test; no microphone/model.

python -m mqtt_xreal_system.Jetson_Final.tests.latency_loopback_sender PORT
"""
import sys
import time
from types import SimpleNamespace

import numpy as np

from ..mqtt.mqtt_bridge import SirenMqttPublisher
from ..telemetry.latency_probe import LatencyProbe


def main():
    port = int(sys.argv[1])
    publisher = SirenMqttPublisher("127.0.0.1", port, "test/latency/state", min_publish_interval=0)
    probe = LatencyProbe("127.0.0.1", port, "test/latency/state", .1, .2)
    try:
        deadline = time.monotonic() + 10
        while not (publisher.connected and probe.client.is_connected()):
            if time.monotonic() >= deadline:
                raise TimeoutError("local broker")
            time.sleep(.02)
        # Allow at least one clock exchange and then feed timestamped quiet blocks.
        time.sleep(2.5)
        meta = None
        for index in range(12):
            data = np.full(100, 0 if index < 4 else .5, dtype=np.float32)
            adc = 20 + index * .1
            meta = probe.audio(data, 1000, SimpleNamespace(inputBufferAdcTime=adc, currentTime=adc + .1), False)
            time.sleep(.1)
        if not meta or "trial_id" not in meta:
            raise RuntimeError("synthetic onset missing")
        for _ in range(45):
            result = probe.timing.result(meta, "siren")
            publisher.publish_state(final_class="siren", confidence_pct=99, doa_deg=270,
                on_published=lambda stamp, t2, m=result: probe.published(m, stamp, t2))
            time.sleep(.1)
    finally:
        publisher.close()
        probe.close()


if __name__ == "__main__": main()
