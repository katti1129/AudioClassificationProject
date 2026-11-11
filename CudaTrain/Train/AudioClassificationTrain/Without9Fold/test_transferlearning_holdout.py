"""Holdout split tests; optional synthetic-feature TensorFlow smoke test."""

import contextlib
import csv
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

import TrainTransferLearning_Mix as holdout


def synthetic_records(root):
    records = []
    for label in ("other", "siren"):
        for source in range(20):
            for window in range(1 + source % 3):
                records.append({
                    "path": root / f"fold{source % 4 + 1}" / label / f"{source}_{window}.wav",
                    "label": label, "source_id": f"{label}:{source}",
                    "fold": f"fold{source % 4 + 1}",
                })
    return records


def save_manifest(path, splits, root):
    rows = []
    for name, selected in splits.items():
        for record in selected:
            rows.append({
                "split": name, "relative_path": record["path"].relative_to(root).as_posix(),
                **{key: record[key] for key in ("source_id", "label", "fold")},
            })
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return rows


def write_rows(path, rows):
    with path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class SplitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.records = synthetic_records(self.root)
        self.label_map = {"other": 0, "siren": 1}
        self.splits = holdout.split_holdout_records(self.records)

    def test_reproducible_complete_source_disjoint_split(self):
        again = holdout.split_holdout_records(self.records)
        self.assertEqual(self.splits, again)
        holdout.validate_splits(self.records, self.splits)
        counts = holdout.split_counts(self.splits)
        self.assertEqual([counts[s]["sources"] for s in holdout.SPLIT_NAMES], [28, 4, 8])
        self.assertEqual(sum(c["windows"] for c in counts.values()), len(self.records))

    def test_rejects_duplicate_missing_or_overlapping_records(self):
        duplicates = {name: list(rows) for name, rows in self.splits.items()}
        duplicates["train"].append(duplicates["train"][0])
        with self.assertRaises(ValueError):
            holdout.validate_splits(self.records, duplicates)
        missing = {name: list(rows) for name, rows in self.splits.items()}
        missing["test"].pop()
        with self.assertRaises(ValueError):
            holdout.validate_splits(self.records, missing)
        overlap = {name: [dict(r) for r in rows] for name, rows in self.splits.items()}
        overlap["test"][0]["source_id"] = overlap["train"][0]["source_id"]
        with self.assertRaises(ValueError):
            holdout.validate_splits(self.records, overlap)

    def test_saved_split_roundtrip(self):
        path = self.root / "split.csv"
        rows = save_manifest(path, self.splits, self.root)
        # Windows-created manifests can be used after copying to Ubuntu.
        for row in rows:
            row["relative_path"] = row["relative_path"].replace("/", "\\")
        write_rows(path, rows)
        with patch.object(holdout, "DATA_DIR", self.root):
            actual = holdout.load_saved_splits(self.records, path, self.label_map)
        self.assertEqual(actual, self.splits)

    def test_rejects_stale_metadata_unknown_paths_and_splits(self):
        path = self.root / "split.csv"
        original = save_manifest(path, self.splits, self.root)
        for key, value in (
            ("label", "wrong"), ("source_id", "unknown"), ("fold", "fold5"),
            ("relative_path", "../unknown.wav"), ("split", "unknown"),
        ):
            with self.subTest(key=key):
                rows = [dict(r) for r in original]
                rows[0][key] = value
                write_rows(path, rows)
                with patch.object(holdout, "DATA_DIR", self.root), self.assertRaises(ValueError):
                    holdout.load_saved_splits(self.records, path, self.label_map)

    def test_rejects_incomplete_or_duplicated_saved_manifest(self):
        path = self.root / "split.csv"
        rows = save_manifest(path, self.splits, self.root)
        for invalid in (rows[:-1], rows + [rows[0]]):
            write_rows(path, invalid)
            with patch.object(holdout, "DATA_DIR", self.root), self.assertRaises(ValueError):
                holdout.load_saved_splits(self.records, path, self.label_map)

    def test_explicit_missing_manifest_does_not_fall_back(self):
        with self.assertRaises(FileNotFoundError):
            holdout.prepare_splits(self.records, self.label_map, self.root / "missing.csv")

    def test_invalid_default_manifest_does_not_fall_back(self):
        path = self.root / "split.csv"
        rows = save_manifest(path, self.splits, self.root)
        rows[0]["source_id"] = "wrong"
        write_rows(path, rows)
        with patch.object(holdout, "DATA_DIR", self.root), \
                patch.object(holdout, "CRNN_SPLIT_MANIFEST", path), self.assertRaises(ValueError):
            holdout.prepare_splits(self.records, self.label_map)

    def test_check_only_does_not_create_results(self):
        args = SimpleNamespace(check_only=True, split_manifest=None, result_dir=self.root / "results")
        with patch.object(holdout, "load_accepted_records", return_value=self.records), \
                patch.object(holdout, "CRNN_SPLIT_MANIFEST", self.root / "missing.csv"), \
                contextlib.redirect_stdout(io.StringIO()):
            holdout.run_training(args)
        self.assertFalse(args.result_dir.exists())

    def test_reuses_real_crnn_manifest_exactly_when_available(self):
        if not holdout.CRNN_SPLIT_MANIFEST.is_file() or not (holdout.DATA_DIR / "manifest.csv").is_file():
            self.skipTest("Real CRNN split or dataset manifest not present")
        records = holdout.load_accepted_records(holdout.DATA_DIR)
        splits, origin = holdout.prepare_splits(records, holdout.build_label_map(records))
        with holdout.CRNN_SPLIT_MANIFEST.open(encoding="utf-8-sig", newline="") as file:
            expected = {(row["split"], row["relative_path"]) for row in csv.DictReader(file)}
        actual = {(name, record["path"].relative_to(holdout.DATA_DIR).as_posix())
                  for name, selected in splits.items() for record in selected}
        self.assertEqual(actual, expected)
        self.assertEqual(origin["kind"], "saved_manifest")


@unittest.skipUnless(os.environ.get("YAMNET_HOLDOUT_SMOKE") == "1", "Optional TensorFlow smoke test")
class TrainingSmokeTests(unittest.TestCase):
    def test_single_fit_and_best_checkpoint_with_synthetic_features(self):
        import tensorflow as tf
        import TrainTransferLearning_4Fold as baseline

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = synthetic_records(root)
            rng = np.random.default_rng(42)
            x = rng.normal(size=(len(records), 2, 1024)).astype(np.float32)
            y = np.asarray([int(r["label"] == "siren") for r in records])
            lookup = {record["path"]: index for index, record in enumerate(records)}
            args = SimpleNamespace(
                check_only=False, split_manifest=None, result_dir=root / "results",
                epochs=1, batch_size=16,
            )
            with patch.object(holdout, "DATA_DIR", root), \
                    patch.object(holdout, "load_accepted_records", return_value=records), \
                    patch.object(holdout, "CRNN_SPLIT_MANIFEST", root / "missing.csv"), \
                    patch.object(baseline, "DATA_DIR", root), \
                    patch.object(baseline, "load_features", return_value=(x, y, lookup)) as load:
                holdout.run_training(args)
            load.assert_called_once()
            report = json.loads((args.result_dir / "test_metrics.json").read_text())
            self.assertEqual(report["metrics"]["best_epoch"], 1)
            self.assertEqual(report["metrics"]["stopped_epoch"], 1)
            self.assertTrue(np.isfinite(report["metrics"]["test_loss"]))
            for filename in (
                "split_manifest.csv", "training_config.json", "history.csv", "model_selection.json",
                "best.keras", "final.keras", "cm.npy", "test_predictions.csv",
                "loss_curve.png", "accuracy_curve.png", "confusion_matrix.png",
            ):
                self.assertTrue((args.result_dir / filename).is_file(), filename)
            best = tf.keras.models.load_model(args.result_dir / "best.keras", compile=False)
            final = tf.keras.models.load_model(args.result_dir / "final.keras", compile=False)
            self.assertEqual(final.count_params(), 664770)
            for expected, actual in zip(best.get_weights(), final.get_weights()):
                np.testing.assert_array_equal(expected, actual)
            with (args.result_dir / "history.csv").open() as file:
                self.assertEqual(len(list(csv.DictReader(file))), 1)


if __name__ == "__main__":
    unittest.main()
