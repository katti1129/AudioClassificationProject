import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

from mqtt_xreal_system.Jetson_Final.telemetry.latency_probe import AudioTiming, LatencyProbe
from mqtt_xreal_system.Jetson_Final.app.state_relay import StateRelay
from mqtt_xreal_system.Jetson_Final.mqtt.mqtt_bridge import SirenMqttPublisher


class LatencyTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.adc = 20.0
        self.timing = AudioTiming(.1, .2, clock=lambda: self.now)

    def block(self, value=0, status=False):
        data = np.full(100, value, dtype=np.float32)
        meta = self.timing.audio(data, 1000,
                                 SimpleNamespace(inputBufferAdcTime=self.adc, currentTime=self.adc + .1), status)
        self.now += .1
        self.adc += .1
        return meta

    def armed_onset(self):
        for _ in range(4): self.block()
        return self.block(.5)

    def test_no_trial_until_quiet_and_sample_timing(self):
        self.assertNotIn("trial_id", self.block(.5))
        for _ in range(4): self.block()
        data = np.r_[np.zeros(25), np.full(75, .5)]
        onset = self.timing.audio(data, 1000,
                                  SimpleNamespace(inputBufferAdcTime=self.adc, currentTime=self.adc + .1))
        self.assertAlmostEqual(onset["t0"], self.now - .1 + .025)
        self.assertEqual(onset["onset_method"], "adc_mapped")

    def test_first_detection_survives_repeated_inferences(self):
        meta = self.armed_onset()
        first = self.timing.result(meta, "siren")
        self.now += .4
        second = self.timing.result(meta, "siren")
        self.assertEqual(first["t1"], second["t1"])
        self.assertNotEqual(first["inference_id"], second["inference_id"])

    def test_queue_gap_stays_invalid_for_trial(self):
        first = self.armed_onset()
        self.timing.buffered(first)
        self.block(.5)
        self.assertEqual(self.timing.buffered(self.block(.5))["invalid"], "audio_queue_gap")
        self.assertEqual(self.timing.buffered(self.block(.5))["invalid"], "audio_queue_gap")

    def test_adc_discontinuity_invalidates_trial(self):
        self.armed_onset()
        self.adc += 1
        self.assertEqual(self.block(.5)["invalid"], "audio_gap_or_overflow")

    def test_callback_fallback_is_labeled(self):
        for _ in range(4): self.block()
        meta = self.timing.audio(np.full(100, .5), 1000, None)
        self.assertEqual(meta["onset_method"], "callback_estimate")

    def test_quiet_rearms_new_trial(self):
        a = self.armed_onset()
        b = self.armed_onset()
        self.assertNotEqual(a["trial_id"], b["trial_id"])

    def test_relay_timing_is_atomic_and_optional(self):
        relay = StateRelay()
        relay.audio_received()
        relay.update("siren", 99, .3, .02, {"trial_id": "7"})
        self.assertNotIn("measurement", relay.snapshot(1))
        self.assertEqual(relay.snapshot(1, with_measurement=True)["measurement"]["trial_id"], "7")
        relay.update("other", 80, .1, .01)
        self.assertIsNone(relay.snapshot(1, with_measurement=True)["measurement"])

    def test_publish_observer_exact_stamp_and_unchanged_schema(self):
        with patch("mqtt_xreal_system.Jetson_Final.mqtt.mqtt_bridge.mqtt.Client") as factory:
            client = factory.return_value
            client.publish.return_value.rc = 0
            publisher = SirenMqttPublisher()
            publisher._on_connect(None, None, None, SimpleNamespace(is_failure=False), None)
            seen = []
            publisher.publish_state(final_class="siren", confidence_pct=99, doa_deg=270,
                                    on_published=lambda stamp, sent: seen.append((stamp, sent)))
            payload = json.loads(client.publish.call_args.args[1])
            self.assertEqual(payload["timestamp_ms"], seen[0][0])
            self.assertNotIn("t0", payload)
            self.assertEqual(client.publish.call_args.kwargs, {"qos": 0, "retain": False})
            client.publish.return_value.rc = 4
            publisher.publish_state(final_class="siren", confidence_pct=99, doa_deg=270, force=True,
                                    on_published=lambda *args: seen.append(args))
            self.assertEqual(len(seen), 1)
            publisher.close()

    def test_sync_rejects_malformed_and_retained_messages(self):
        with patch("paho.mqtt.client.Client") as factory:
            probe = LatencyProbe("127.0.0.1", 1883, "test")
            for payload, retain in [(b"{bad", False), (b'{}', False), (b'{"id":"x"}', True)]:
                probe._message(None, None, SimpleNamespace(payload=payload, retain=retain))
            factory.return_value.publish.assert_not_called()
            probe._message(None, None, SimpleNamespace(payload=b'{"id":"x"}', retain=False))
            response = json.loads(factory.return_value.publish.call_args.args[1])
            self.assertGreaterEqual(response["s3"], response["s2"])
            self.assertEqual(response["id"], "x")
            probe.close()


if __name__ == "__main__": unittest.main()
