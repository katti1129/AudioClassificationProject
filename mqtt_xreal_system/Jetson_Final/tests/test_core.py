import csv
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from mqtt_xreal_system.Jetson_Final.app.decision import SirenDecision
from mqtt_xreal_system.Jetson_Final.app.state_relay import StateRelay
from mqtt_xreal_system.Jetson_Final.telemetry.experiment_logger import ExperimentLogger


class CoreTests(unittest.TestCase):
    def test_hysteresis_does_not_leak_argmax_siren(self):
        decision = SirenDecision()
        self.assertEqual([decision.update(.99) for _ in range(3)], ["other", "other", "siren"])
        self.assertEqual([decision.update(.2) for _ in range(3)], ["siren", "siren", "other"])

    def test_silence_resets_history(self):
        decision = SirenDecision()
        for _ in range(3): decision.update(.99)
        decision.reset()
        self.assertEqual(decision.update(.99), "other")

    def test_no_republishing_stale_inference_or_disconnected_microphone(self):
        relay = StateRelay()
        with patch("time.monotonic", return_value=1):
            self.assertIsNone(relay.snapshot(1))
            relay.audio_received()
            relay.update("siren", 98, .04, .0238)
            self.assertAlmostEqual(relay.snapshot(1)["inference_ms"], 23.8)
        with patch("time.monotonic", return_value=1.6):
            self.assertIsNone(relay.snapshot(1))
            relay.audio_received()
            self.assertIsNotNone(relay.snapshot(1))
        with patch("time.monotonic", return_value=2.1):
            relay.audio_received()
            self.assertIsNone(relay.snapshot(1))

    def test_csv_drains_at_shutdown(self):
        with tempfile.TemporaryDirectory() as directory:
            logger = ExperimentLogger(directory)
            logger.submit(dict(timestamp="now", final_class="siren", confidence_pct=98, doa_deg=270,
                               rms=.04, inference_ms=20, mqtt_connected=True))
            logger.close()
            with logger.path.open(encoding="utf-8", newline="") as stream:
                rows = list(csv.DictReader(stream))
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["doa_deg"], "270")

    def test_logging_disabled_does_not_create_files(self):
        logger = ExperimentLogger()
        logger.submit({})
        logger.close()
        self.assertIsNone(logger.path)


if __name__ == "__main__": unittest.main()
