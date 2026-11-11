"""Regression tests. Fixtures/models are synthetic, NOT AI performance evidence.

Run with the project .venv Python. Artifacts remain in heatmap_test_outputs.
"""
import json
import unittest
import wave
from pathlib import Path
from uuid import uuid4

import numpy as np
import pandas as pd

import EvaluateSimulationHeatmaps as app


class HeatmapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base = app.load_evaluator()
        cls.original_hash = app.file_hash(app.EVALUATOR_PATH)
        cls.root = Path(__file__).parent / "heatmap_test_outputs" / ("TEST_" + uuid4().hex[:8])
        cls.root.mkdir(parents=True)
        print(f"Synthetic test artifacts: {cls.root}", flush=True)

    def test_01_probability_validation(self):
        class Dummy:
            def __init__(self, result):
                self.result = result
            def predict(self, inputs, **kwargs):
                return self.result
        for bad in ([[0.2]], [[-1, 2]], [[.8, .8]], [[np.nan, .5]]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                app.ProbabilityModel(Dummy(bad)).predict([0])
        np.testing.assert_allclose(app.ProbabilityModel(Dummy([[.2, .8]])).predict([0]), [[.2, .8]])

    def test_02_macro_micro_and_time(self):
        summary = pd.DataFrame([
            dict(GroupID="G001", CPA_m=20, Velocity_kmh=60, RelativePath="a", TP=1, FN=0, Recall_percent=100, MeanSirenProbability_percent=80),
            dict(GroupID="G001", CPA_m=20, Velocity_kmh=60, RelativePath="b", TP=1, FN=3, Recall_percent=25, MeanSirenProbability_percent=40),
        ])
        windows = pd.DataFrame([
            dict(GroupID="G001", CPA_m=20, Velocity_kmh=60, RelativePath="a", HeatmapTime_s=0, DetectedByThreshold=True, SirenProbability=.8),
            dict(GroupID="G001", CPA_m=20, Velocity_kmh=60, RelativePath="b", HeatmapTime_s=0, DetectedByThreshold=False, SirenProbability=.2),
        ])
        cells, times = app.aggregate_results(summary, windows)
        self.assertEqual(cells.iloc[0].MacroRecall_percent, 62.5)
        self.assertEqual(cells.iloc[0].MicroRecall_percent, 40)
        self.assertEqual(times.iloc[0].DetectionRate_percent, 50)
        self.assertEqual(times.iloc[0].FileCount, 2)

    def test_03_interval_and_cpa(self):
        rows = [dict(StartTime_s=t, EndTime_s=t+1, CenterTime_s=t+.5,
                     DetectedByThreshold=True, SirenProbability=.75) for t in (0, .5, 1)]
        selected = app.select_windows(rows, 1, 2, 1.5)
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected.iloc[0].HeatmapTime_s, 0)
        summary = app.summarize_windows(selected, {})
        self.assertEqual(summary["FirstDetectionAvailableAt_s"], 2)
        with self.assertRaises(ValueError):
            app.select_windows(rows, .1, .9)

    def test_04_end_to_end_saved_keras_model(self):
        import tensorflow as tf
        inputs = self.root / "tagged_wavs"
        inputs.mkdir()
        names = ["siren_CPA5m_V020_R080_SEED1.wav", "siren_CPA5m_V020_R080_SEED2.wav",
                 "siren_CPA20m_V020_R080.wav", "siren_CPA5m_V060_R080.wav",
                 "siren_CPA5m_V020_R040.wav", "background_b/siren_CPA5m_V020_R080.wav", "final.wav"]
        signal = (.1 * np.sin(2*np.pi*800*np.arange(32000)/16000)*32767).astype("<i2")
        for name in names:
            path = inputs / name
            path.parent.mkdir(exist_ok=True)
            with wave.open(str(path), "wb") as handle:
                handle.setnchannels(1)
                handle.setsampwidth(2)
                handle.setframerate(16000)
                handle.writeframes(signal.tobytes())
        candidates, errors = app.scan_inputs(inputs, self.base)
        self.assertEqual(len(candidates), 6)
        self.assertEqual(len(errors), 1)
        self.assertEqual(len({c["group"] for c in candidates}), 3)
        feature_shape = self.base.waveform_to_input(np.zeros(16000), 16000).shape
        model = tf.keras.Sequential([
            tf.keras.layers.Input(shape=feature_shape),
            tf.keras.layers.GlobalAveragePooling2D(),
            tf.keras.layers.Dense(2, activation="softmax", kernel_initializer="zeros",
                                  bias_initializer=tf.keras.initializers.Constant([0, np.log(3)])),
        ])
        model_path = self.root / "TEST_ONLY_constant_model.keras"
        model.save(model_path)
        args = app.make_parser().parse_args([
            "--input-dir", str(inputs), "--model", str(model_path),
            "--output-dir", str(self.root / "results"), "--assume-positive", "--cpa-time", "1",
        ])
        output = app.run_evaluation(args, evaluator=self.base)
        summary = pd.read_csv(output / "Summary.csv")
        windows = pd.read_csv(output / "WindowResults.csv")
        self.assertEqual(len(summary), 6)
        self.assertEqual(len(windows), 18)
        np.testing.assert_allclose(summary.Recall_percent, 100)
        np.testing.assert_allclose(windows.SirenProbability, .75, atol=1e-6)
        self.assertEqual(len(pd.read_csv(output / "Errors.csv")), 1)
        completion = json.loads((output / "completion.json").read_text())
        self.assertTrue(completion["heatmaps_created"])
        self.assertEqual(completion["not_processed_candidates"], 0)
        main_group = next(c["group"] for c in candidates if c["relative"] == names[0])
        matrix = pd.read_csv(output / "heatmaps" / main_group / "distance_speed_macro_recall.csv", index_col=0)
        self.assertTrue(pd.isna(matrix.loc[60, "20.0"]))
        self.assertEqual(len(list(output.rglob("*.png"))), 14)
        self.assertEqual(app.file_hash(app.EVALUATOR_PATH), self.original_hash)
        loaded = self.base.load_model(model_path, compile=False)
        self.base.CLASS_NAMES = ["siren", "other"]
        reversed_summary, _ = self.base.evaluate_file(app.ProbabilityModel(loaded), inputs / names[0])
        self.assertEqual(reversed_summary["Recall_percent"], 0)
        self.base.CLASS_NAMES = ["other", "siren"]


if __name__ == "__main__":
    unittest.main(verbosity=2)
