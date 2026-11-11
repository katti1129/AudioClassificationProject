"""Small CPU tests; does not launch the real 4-fold training experiment."""

import csv
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np
import soundfile as sf
import tensorflow as tf
import tf_keras as keras

import yamnet_finetuning as support
import TrainTransferLearning_PartialFineTuning_4Fold as trainer


class ModelTests(unittest.TestCase):
    def setUp(self):
        keras.backend.clear_session()
        keras.utils.set_random_seed(42)

    def test_frontend_patch_count(self):
        self.assertEqual(support.waveform_layout(16000), (23280, 2))
        layer = support.YAMNetLogMel()
        result = layer(tf.zeros((2, 16000)))
        self.assertEqual(tuple(result.shape), (2, 2, 96, 64))
        np.testing.assert_allclose(result.numpy(), np.log(0.001), atol=1e-6)

    def test_gradients_freezing_and_serialization(self):
        model, backbone = support.build_model(2, load_pretrained=False)
        self.assertEqual(len(backbone.trainable_weights), 0)
        selected = support.enable_partial_fine_tuning(backbone)
        self.assertEqual(selected, [
            "layer13_depthwise_conv", "layer13_pointwise_conv",
            "layer14_depthwise_conv", "layer14_pointwise_conv",
        ])
        self.assertTrue(all(not layer.trainable for layer in backbone.layers
                            if isinstance(layer, keras.layers.BatchNormalization)))
        trainable_ids = {id(weight) for weight in model.trainable_weights}
        self.assertTrue(all(id(weight) in trainable_ids for weight in backbone.trainable_weights))
        frozen = [(weight, weight.numpy().copy()) for weight in backbone.non_trainable_weights]
        unfrozen = [(weight, weight.numpy().copy()) for weight in backbone.trainable_weights]
        waveform = tf.random.uniform((2, 16000), minval=-0.5, maxval=0.5)
        with tf.GradientTape() as tape:
            output = model(waveform, training=True)
            loss = tf.reduce_mean(keras.losses.sparse_categorical_crossentropy(tf.constant([0, 1]), output))
        gradients = tape.gradient(loss, model.trainable_weights)
        self.assertTrue(all(gradient is not None for gradient in gradients))
        pairs = list(zip(gradients, model.trainable_weights))
        for weight in backbone.trainable_weights:
            gradient = next(grad for grad, variable in pairs if variable is weight)
            self.assertTrue(np.isfinite(gradient.numpy()).all())
            self.assertGreater(float(tf.reduce_sum(tf.abs(gradient))), 0.0)
        # Tiny epsilon makes the random-weight structural test sensitive to
        # very small backbone gradients. Production uses the normal Adam epsilon.
        keras.optimizers.Adam(1e-3, epsilon=1e-20).apply_gradients(pairs)
        for weight, old in frozen:
            np.testing.assert_array_equal(weight.numpy(), old)
        self.assertTrue(any(np.any(weight.numpy() != old) for weight, old in unfrozen))
        expected = model(waveform, training=False).numpy()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.keras"
            model.save(str(path))
            restored = keras.models.load_model(str(path), compile=False)
            np.testing.assert_allclose(restored(waveform, training=False).numpy(), expected, atol=1e-7)
            weights = Path(directory) / "test.weights.h5"
            model.save_weights(str(weights))
            model.load_weights(str(weights))

    def test_fit_both_stages_on_small_batches(self):
        model, backbone = support.build_model(2, load_pretrained=False)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = []
            for index in range(4):
                path = root / f"clip{index}.wav"
                waveform = np.random.default_rng(index).uniform(-0.1, 0.1, 16000).astype(np.float32)
                sf.write(path, waveform, 16000, subtype="FLOAT")
                records.append({"path": path, "label": "siren" if index % 2 else "other"})
            data = trainer.AudioSequence(records, {"other": 0, "siren": 1}, 2)
            frozen = [(weight, weight.numpy().copy()) for layer in backbone.layers
                      if not layer.name.startswith(("layer13_", "layer14_")) for weight in layer.weights]
            rows, selection = trainer.train_two_stages(
                model, backbone, data, data, root,
                SimpleNamespace(head_epochs=1, fine_tune_epochs=1),
            )
            self.assertEqual([row["stage"] for row in rows], ["head", "fine_tune"])
            self.assertTrue(np.isfinite(selection["best_val_loss"]))
            for weight, old in frozen:
                np.testing.assert_array_equal(weight.numpy(), old)
            trainer.save_curves(rows, selection, root)
            result = model.predict(data, verbose=0)
            self.assertEqual(result.shape, (4, 2))

    @unittest.skipUnless(os.environ.get("YAMNET_TEST_PRETRAINED") == "1", "Optional Hub parity test")
    def test_official_hub_embedding_parity(self):
        import tensorflow_hub as hub

        # Check zero and nonzero signals. Also verifies strict official HDF5 load.
        waveform = np.stack([
            np.zeros(16000, np.float32),
            (0.25 * np.sin(2 * np.pi * 440 * np.arange(16000) / 16000)).astype(np.float32),
        ])
        model, _ = support.build_model(2)
        extractor = keras.Model(model.input, model.get_layer("yamnet_encoder").output)
        actual = extractor(waveform, training=False).numpy()
        official = hub.load("https://tfhub.dev/google/yamnet/1")
        expected = np.stack([official(tf.constant(clip))[1].numpy() for clip in waveform])
        np.testing.assert_allclose(actual, expected, rtol=2e-4, atol=2e-5)


class DataAndSelectionTests(unittest.TestCase):
    def test_existing_baseline_split_parity_when_available(self):
        baseline = (trainer.SCRIPT_DIR / "../../Result/runs_transferlearning_fold1to4").resolve()
        if not (trainer.DATA_DIR / "manifest.csv").is_file() or not (baseline / "fold1/split_manifest.csv").is_file():
            self.skipTest("Real manifest/baseline results not present")
        records = trainer.load_accepted_records(trainer.DATA_DIR)
        for fold in trainer.FOLD_NAMES:
            train, validation = trainer.split_train_validation(
                [record for record in records if record["fold"] != fold],
                val_size=trainer.VAL_SIZE, seed=trainer.SEED,
            )
            actual = {(split, record["path"].relative_to(trainer.DATA_DIR).as_posix())
                      for split, selected in (
                          ("train", train), ("validation", validation),
                          ("test", trainer.records_for_fold(records, fold)),
                      ) for record in selected}
            with (baseline / fold / "split_manifest.csv").open(encoding="utf-8-sig") as file:
                expected = {(row["split"], row["relative_path"]) for row in csv.DictReader(file)}
            self.assertEqual(actual, expected, fold)

    def test_waveform_order_and_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = []
            for index, label in enumerate(("other", "siren", "other")):
                path = root / f"{index}.wav"
                sf.write(path, np.full(16000, index / 10, dtype=np.float32), 16000, subtype="FLOAT")
                records.append({"path": path, "label": label, "source_id": str(index), "fold": "fold1"})
            trainer.validate_audio_records(records)
            data = trainer.AudioSequence(records, {"other": 0, "siren": 1}, 2)
            self.assertEqual(len(data), 2)
            first, labels = data[0]
            last, _ = data[1]
            np.testing.assert_array_equal(labels, [0, 1])
            np.testing.assert_allclose(first[:, 0], [0, 0.1])
            self.assertEqual(last.shape, (1, 16000))
            sf.write(records[0]["path"], np.zeros(100), 16000)
            with self.assertRaises(ValueError):
                trainer.validate_audio_records(records)

    def test_split_rejects_source_overlap(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            splits = {}
            for split in ("train", "validation", "test"):
                splits[split] = [
                    {"path": root / f"{split}_{label}.wav", "fold": "fold1", "label": label,
                     "source_id": f"{split}_{label}"} for label in ("other", "siren")
                ]
            with patch.object(trainer, "DATA_DIR", root):
                trainer.save_splits(root, splits, {"other": 0, "siren": 1})
                with (root / "split_manifest.csv").open(encoding="utf-8") as file:
                    rows = list(csv.DictReader(file))
                self.assertEqual(len(rows), 6)
                splits["test"][0]["source_id"] = splits["train"][0]["source_id"]
                with self.assertRaises(RuntimeError):
                    trainer.save_splits(root, splits, {"other": 0, "siren": 1})

    def test_two_stages_preserve_global_best(self):
        class FakeModel:
            def __init__(self, losses):
                self.losses = iter(losses)
                self.stage_index = 0
                self.value = None
                self.saved = {}
                self.loaded = []

            def save_weights(self, path):
                self.saved[path] = self.value

            def load_weights(self, path):
                self.value = self.saved[path]
                self.loaded.append(self.value)

            def fit(self, *args, callbacks, **kwargs):
                losses = next(self.losses)
                best = callbacks[0]
                best.set_model(self)
                for index, loss in enumerate(losses):
                    self.value = (self.stage_index, index)
                    best.on_epoch_end(index, {"val_loss": loss})
                self.stage_index += 1
                return SimpleNamespace(history={
                    "loss": [0.1] * len(losses), "accuracy": [0.9] * len(losses),
                    "val_loss": losses, "val_accuracy": [0.9] * len(losses),
                })

        for fine_losses, expected_stage, expected_epoch in (
            ([0.25, 0.22], "head", 2),
            ([0.19, 0.15], "fine_tune", 4),
            ([0.20, 0.20], "head", 2),
        ):
            with self.subTest(fine_losses=fine_losses), tempfile.TemporaryDirectory() as directory:
                model = FakeModel([[0.3, 0.2], fine_losses])
                with patch.object(trainer, "compile_model") as compile_mock, \
                        patch.object(trainer, "enable_partial_fine_tuning", return_value=["layer13_conv"]) as enable:
                    rows, selected = trainer.train_two_stages(
                        model, object(), None, None, Path(directory),
                        SimpleNamespace(head_epochs=2, fine_tune_epochs=2),
                    )
                self.assertEqual(selected["best_stage"], expected_stage)
                self.assertEqual(selected["best_epoch"], expected_epoch)
                self.assertEqual(model.loaded[0], (0, 1))
                self.assertEqual(model.loaded[-1], (0, 1) if expected_stage == "head" else (1, 1))
                self.assertEqual([row["epoch"] for row in rows], [1, 2, 3, 4])
                self.assertEqual(compile_mock.call_count, 2)
                enable.assert_called_once()


if __name__ == "__main__":
    unittest.main()
