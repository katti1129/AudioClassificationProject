import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch, MagicMock

from mqtt_xreal_system.Jetson_Final.mqtt.mqtt_bridge import SirenMqttPublisher


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.factory = patch("mqtt_xreal_system.Jetson_Final.mqtt.mqtt_bridge.mqtt.Client")
        self.client = self.factory.start().return_value
        self.client.publish.return_value.rc = 0
        self.publisher = SirenMqttPublisher()
        self.data = dict(final_class="siren", confidence_pct=98.1, doa_deg=270, rms=.041, inference_ms=23.8)

    def tearDown(self):
        self.publisher.close()
        self.factory.stop()

    def connect(self):
        self.publisher._on_connect(None, None, None, SimpleNamespace(is_failure=False), None)

    def test_disconnected_does_not_queue_old_alert(self):
        self.assertFalse(self.publisher.publish_state(**self.data))
        self.client.publish.assert_not_called()

    def test_v1_schema_and_qos0_nonretained(self):
        self.connect()
        self.assertTrue(self.publisher.publish_state(**self.data, force=True))
        args, kwargs = self.client.publish.call_args
        payload = json.loads(args[1])
        self.assertEqual(set(payload), {"version", "detected", "class_name", "confidence_pct", "doa_deg", "rms", "inference_ms", "timestamp_ms"})
        self.assertTrue(payload["detected"])
        self.assertEqual(payload["confidence_pct"], 98.1)
        self.assertEqual(kwargs, {"qos": 0, "retain": False})

    def test_rate_limit_and_reconnect(self):
        self.connect()
        with patch("time.monotonic", return_value=100):
            self.assertTrue(self.publisher.publish_state(**self.data))
        with patch("time.monotonic", return_value=100.01):
            self.assertFalse(self.publisher.publish_state(**self.data))
        self.publisher._on_disconnect(None, None, None, None, None)
        self.assertFalse(self.publisher.connected)
        self.connect()
        with patch("time.monotonic", return_value=101):
            self.assertTrue(self.publisher.publish_state(**self.data))

    def test_unknown_and_nonfinite_direction(self):
        self.connect()
        for direction in [None, -1, float("nan")]:
            self.data["doa_deg"] = direction
            self.assertTrue(self.publisher.publish_state(**self.data, force=True))
            self.assertEqual(json.loads(self.client.publish.call_args.args[1])["doa_deg"], -1)

    def test_network_exception_does_not_escape(self):
        self.connect()
        self.client.publish.side_effect = OSError("connection lost")
        self.assertFalse(self.publisher.publish_state(**self.data, force=True))


if __name__ == "__main__": unittest.main()
