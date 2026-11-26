import csv
import json
import queue
import sys
import tempfile
import time
import unittest
import socket
import threading
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import common
import controller
from audio import Recorder, Player
from network import Client, receive, send
import numpy as np
import soundfile as sf


class ScoringTests(unittest.TestCase):
    def test_all_outcomes(self):
        self.assertEqual(common.score("siren", "north", "north"), "correct_direction")
        self.assertEqual(common.score("siren", "north", "east"), "wrong_direction")
        self.assertEqual(common.score("siren", "north", None), "miss")
        self.assertEqual(common.score("other", "north", "north"), "false_alarm")
        self.assertEqual(common.score("other", "north", None), "correct_rejection")

    def test_traversal_rejected(self):
        with self.assertRaises(ValueError):
            common.sound_path("../config.json")


class AudioTests(unittest.TestCase):
    def test_background_below_threshold_does_not_trigger(self):
        rec = Recorder(common.config(), Path("unused.wav"))
        rec.armed_at = 0
        with patch("audio.time.perf_counter", return_value=100):
            rec._callback(np.full((256, 1), .001, dtype="float32"), 256,
                          SimpleNamespace(inputBufferAdcTime=10, currentTime=10), False)
        self.assertIsNone(rec.onset)

    def test_onset_across_buffers_and_sine_zero_crossings(self):
        cfg = common.config()
        rec = Recorder(cfg, Path("unused.wav"))
        rec.armed_at = 99
        # Three 2ms blocks of a 1kHz sine: sample-amplitude-only detection would fail.
        for j in range(3):
            x = .2 * np.sin(2 * np.pi * 1000 * (np.arange(96) + j * 96) / 48000)
            with patch("audio.time.perf_counter", return_value=100 + j * .002):
                rec._callback(x.astype("float32")[:, None], 96,
                              SimpleNamespace(inputBufferAdcTime=10, currentTime=10), False)
        self.assertIsNotNone(rec.onset)
        self.assertLess(rec.onset, 100.002)
        self.assertIsNotNone(rec.onset_sample)

    def test_playback_only_selected_channel(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "tone.wav"
            sf.write(path, np.full(200, .5), 48000)
            player = Player(common.config())
            player.prepare(path, 1)
            self.assertTrue(np.all(player.data[:, 0] == 0))
            self.assertTrue(np.all(player.data[:, 1] > 0))


class FakePlayer:
    error = None
    def __init__(self, cfg): pass
    def prepare(self, path, channel): pass
    def play(self): pass
    def stop(self): pass


class FakeRecorder:
    error = None
    peak_dbfs = -20
    onset_sample = 0
    detect = True
    def __init__(self, cfg, path): self.onset = None
    def start(self): pass
    def arm(self):
        stamp = time.perf_counter()
        if self.detect: self.onset = stamp
        return stamp
    def close(self): pass


class ControllerTests(unittest.TestCase):
    def run_session(self, detect=True, response=None):
        with tempfile.TemporaryDirectory() as d:
            cfg = common.config()
            cfg.update(settle_s=.01, onset_timeout_s=.03, response_timeout_s=.03, silence_s=.01)
            trials = [{"trial_id": "1", "file": "fake.wav", "direction": "west", "class": "other"}]
            with patch.object(controller, "ROOT", Path(d)), patch.object(controller, "Player", FakePlayer), \
                 patch.object(controller, "Recorder", FakeRecorder), patch.object(controller, "sound_path", return_value=Path(d)), \
                 patch.object(controller, "digest", return_value="fake"), patch.object(FakeRecorder, "detect", detect):
                c = controller.Controller(cfg, trials, "P001", "support_on", "main", queue.Queue())
                if response:
                    original = FakePlayer.play
                    def answer(_): c.key(response, time.perf_counter())
                    with patch.object(FakePlayer, "play", answer): c.run()
                else:
                    c.run()
                with open(c.folder / "trials.csv", encoding="utf-8-sig") as f:
                    rows = list(csv.DictReader(f))
                self.assertTrue((c.folder / "events.jsonl").is_file())
                self.assertNotIn("token", json.loads((c.folder / "session.json").read_text())["config"])
                return rows[0]

    def test_other_timeout_is_correct_rejection_with_missing_rt(self):
        row = self.run_session()
        self.assertEqual(row["outcome"], "correct_rejection")
        self.assertEqual(row["rt_s"], "")

    def test_missing_onset_is_invalid_not_miss(self):
        row = self.run_session(detect=False)
        self.assertEqual(row["valid"], "False")
        self.assertEqual(row["outcome"], "invalid")

    def test_other_response_is_false_alarm(self):
        row = self.run_session(response="north")
        self.assertEqual(row["outcome"], "false_alarm")
        self.assertGreaterEqual(float(row["rt_s"]), 0)

    def test_stop_interrupts_wait(self):
        with patch.object(controller, "Player", FakePlayer):
            c = controller.Controller(common.config(), [], "P", "support_on", "main", queue.Queue())
            c.stop_event.set()
            with self.assertRaises(InterruptedError):
                c.wait(10)


class NetworkTests(unittest.TestCase):
    def test_real_tcp_round_trip_and_reject_mismatched_reply(self):
        errors = []
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            def peer():
                try:
                    conn, _ = server.accept()
                    with conn, conn.makefile("rb") as reader:
                        m = receive(reader)
                        self.assertEqual(m["token"], "test-token")
                        self.assertEqual(m["command"], "status")
                        send(conn, dict(ok=True, request_id=m["request_id"], audio_error=None))
                        receive(reader)
                        send(conn, dict(ok=True, request_id="wrong-id"))
                except Exception as e:
                    errors.append(e)
            thread = threading.Thread(target=peer, daemon=True)
            thread.start()
            cfg = common.config()
            cfg.update(host="127.0.0.1", port=server.getsockname()[1], token="test-token")
            client = Client(cfg)
            try:
                self.assertIsNone(client.call("status")["audio_error"])
                with self.assertRaises(RuntimeError):
                    client.call("stop")
            finally:
                client.close()
            thread.join(3)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
