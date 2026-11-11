"""Source-disjoint 4-fold YAMNet partial fine-tuning + the baseline BiLSTM head.

Run from any directory. Fixed final-embedding .npz caches are NOT used.
Import yamnet_finetuning before tf_keras.models.load_model to reload final.keras.
"""

import argparse
import csv
import gc
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf
import tensorflow as tf
import tf_keras as keras
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score

from fold_training_utils import (
    FOLD_NAMES, build_label_map, load_accepted_records, print_split_summary,
    records_for_fold, split_train_validation,
)
from yamnet_finetuning import (
    NUM_SAMPLES, SAMPLE_RATE, WEIGHTS_URL, build_model, compile_model,
    enable_partial_fine_tuning, resolve_pretrained_weights,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = (SCRIPT_DIR / "../../data/Mixed_US8K_ESC50_dataset/04_silence_filtered").resolve()
RESULT_DIR = (SCRIPT_DIR / "../../Result/runs_transferlearning_partial_finetuning_fold1to4").resolve()
HEAD_EPOCHS = 100
FINE_TUNE_EPOCHS = 30
BATCH_SIZE = 32
HEAD_LEARNING_RATE = 1e-4
FINE_TUNE_LEARNING_RATE = 1e-5
PATIENCE = 5
FIRST_FINE_TUNE_BLOCK = 13
VAL_SIZE = 0.1
SEED = 42


def write_json(path, value):
    with Path(path).open("w", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False, indent=2, allow_nan=False)


def validate_audio_records(records):
    """Do not silently crop/resample and change the baseline's input clips."""
    seen = set()
    for index, record in enumerate(records, 1):
        path = record["path"]
        if path in seen:
            raise ValueError(f"Duplicate waveform: {path}")
        seen.add(path)
        info = sf.info(str(path))
        if info.samplerate != SAMPLE_RATE or info.frames != NUM_SAMPLES or info.channels != 1:
            raise ValueError(f"Expected 1-second, 16 kHz mono audio: {path} ({info})")
        if index % 1000 == 0 or index == len(records):
            print(f"[Audio check] {index}/{len(records)} files", flush=True)


class AudioSequence(keras.utils.Sequence):
    """Stream small waveform batches; labels/predictions retain manifest order."""

    def __init__(self, records, label_map, batch_size, shuffle=False, seed=SEED):
        super().__init__()
        self.records = records
        self.label_map = label_map
        self.batch_size = batch_size
        self.shuffle = shuffle
        self.rng = np.random.default_rng(seed)
        self.indexes = np.arange(len(records))
        self.on_epoch_end()

    def __len__(self):
        return (len(self.records) + self.batch_size - 1) // self.batch_size

    def __getitem__(self, index):
        indexes = self.indexes[index * self.batch_size : (index + 1) * self.batch_size]
        audio = np.empty((len(indexes), NUM_SAMPLES), dtype=np.float32)
        labels = np.empty(len(indexes), dtype=np.int64)
        for offset, record_index in enumerate(indexes):
            record = self.records[int(record_index)]
            waveform, rate = sf.read(str(record["path"]), dtype="float32")
            if rate != SAMPLE_RATE or waveform.shape != (NUM_SAMPLES,) or not np.isfinite(waveform).all():
                raise ValueError(f"Invalid waveform: {record['path']}")
            audio[offset] = waveform
            labels[offset] = self.label_map[record["label"]]
        return audio, labels

    def on_epoch_end(self):
        if self.shuffle:
            self.rng.shuffle(self.indexes)


def save_splits(out_dir, splits, label_map):
    seen_sources, seen_paths = set(), set()
    rows = []
    for split_name, selected in splits.items():
        sources = {record["source_id"] for record in selected}
        paths = {record["path"] for record in selected}
        if not selected or seen_sources & sources or seen_paths & paths or len(paths) != len(selected):
            raise RuntimeError(f"Empty or overlapping split: {split_name}")
        if {record["label"] for record in selected} != set(label_map):
            raise RuntimeError(f"A class is missing from {split_name}.")
        seen_sources.update(sources)
        seen_paths.update(paths)
        for record in selected:
            rows.append({
                "split": split_name, "fold": record["fold"],
                "source_id": record["source_id"], "label": record["label"],
                "relative_path": record["path"].relative_to(DATA_DIR).as_posix(),
            })
    with (out_dir / "split_manifest.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


class BestAcrossStages(keras.callbacks.Callback):
    """Keep one global val_loss best, including a stage-1 fallback."""

    def __init__(self, path):
        super().__init__()
        self.path = Path(path)
        self.best_loss = float("inf")
        self.best_stage = None
        self.best_stage_epoch = None
        self.best_epoch = None
        self.stage = None
        self.offset = 0

    def start_stage(self, stage, offset):
        self.stage, self.offset = stage, offset

    def on_epoch_end(self, epoch, logs=None):
        loss = float((logs or {}).get("val_loss", float("nan")))
        if not np.isfinite(loss):
            raise RuntimeError("Non-finite validation loss; refusing to select invalid weights.")
        if loss < self.best_loss:
            self.model.save_weights(str(self.path))
            self.best_loss = loss
            self.best_stage = self.stage
            self.best_stage_epoch = epoch + 1
            self.best_epoch = self.offset + epoch + 1


def train_two_stages(model, backbone, train_data, val_data, out_dir, args):
    best = BestAcrossStages(out_dir / "best.weights.h5")
    rows = []
    trainable_layers = []
    for stage, epochs, rate in (
        ("head", args.head_epochs, HEAD_LEARNING_RATE),
        ("fine_tune", args.fine_tune_epochs, FINE_TUNE_LEARNING_RATE),
    ):
        if stage == "fine_tune":
            # Head callback restores its own best; load explicitly as well.
            model.load_weights(str(best.path))
            trainable_layers = enable_partial_fine_tuning(backbone, FIRST_FINE_TUNE_BLOCK)
            print(f"[Fine-tune] Trainable YAMNet layers: {trainable_layers}")
            write_json(out_dir / "trainable_yamnet_layers.json", trainable_layers)
        compile_model(model, rate)
        best.start_stage(stage, len(rows))
        print(f"[Stage] {stage}: max_epochs={epochs}, lr={rate}")
        history = model.fit(
            train_data, validation_data=val_data, epochs=epochs, shuffle=False,
            workers=1, max_queue_size=2,
            callbacks=[
                best,
                keras.callbacks.EarlyStopping(
                    monitor="val_loss", mode="min", patience=PATIENCE,
                    restore_best_weights=True, verbose=1,
                ),
                keras.callbacks.CSVLogger(str(out_dir / f"history_{stage}.csv")),
            ],
            verbose=2,
        )
        for index in range(len(history.history["loss"])):
            rows.append({
                "epoch": len(rows) + 1, "stage": stage, "stage_epoch": index + 1,
                "learning_rate": rate,
                **{key: float(history.history[key][index]) for key in (
                    "loss", "accuracy", "val_loss", "val_accuracy",
                )},
            })
    # The best fine-tune epoch may still be WORSE than the head-only model.
    model.load_weights(str(best.path))
    with (out_dir / "history.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    selection = {
        "best_epoch": best.best_epoch, "best_stage": best.best_stage,
        "best_stage_epoch": best.best_stage_epoch, "best_val_loss": best.best_loss,
    }
    write_json(out_dir / "model_selection.json", selection)
    return rows, selection


def save_curves(rows, selection, out_dir):
    epochs = [row["epoch"] for row in rows]
    boundary = sum(row["stage"] == "head" for row in rows) + 0.5
    for metric in ("loss", "accuracy"):
        plt.figure(figsize=(8, 5))
        plt.plot(epochs, [row[metric] for row in rows], label=f"train_{metric}")
        plt.plot(epochs, [row[f"val_{metric}"] for row in rows], label=f"val_{metric}")
        plt.axvline(boundary, color="gray", linestyle="--", label="Fine-tuning starts")
        plt.axvline(selection["best_epoch"], color="green", linestyle=":", label="Selected model")
        plt.xlabel("Epoch")
        plt.ylabel(metric)
        plt.legend()
        plt.grid(True)
        plt.tight_layout()
        plt.savefig(out_dir / f"{metric}_curve.png")
        plt.close()


def save_confusion(cm, class_names, destination):
    fig, ax = plt.subplots(figsize=(6, 5))
    image = ax.imshow(cm, cmap="Blues")
    fig.colorbar(image, ax=ax)
    ax.set(xticks=range(len(class_names)), yticks=range(len(class_names)),
           xticklabels=class_names, yticklabels=class_names, xlabel="Predicted", ylabel="True")
    for row in range(len(class_names)):
        for column in range(len(class_names)):
            ax.text(column, row, str(cm[row, column]), ha="center", va="center",
                    color="white" if cm[row, column] > cm.max() / 2 else "black")
    fig.tight_layout()
    fig.savefig(destination)
    plt.close(fig)


def run_training(args):
    for gpu in tf.config.list_physical_devices("GPU"):
        tf.config.experimental.set_memory_growth(gpu, True)
    print(f"[GPU] {tf.config.list_physical_devices('GPU')}")
    result_dir = args.result_dir.resolve()
    print(f"[Dataset] {DATA_DIR}")
    print(f"[Results] {result_dir}")
    if result_dir.exists() and any(result_dir.iterdir()):
        raise FileExistsError(f"Results already exist: {result_dir}. Use --result-dir with a NEW directory.")
    records = load_accepted_records(DATA_DIR)
    label_map = build_label_map(records)
    if set(label_map) != {"other", "siren"}:
        raise ValueError(f"Expected other/siren classes, got {label_map}.")
    class_names = sorted(label_map, key=label_map.get)
    validate_audio_records(records)
    weights_path = resolve_pretrained_weights(args.weights)
    print(f"[Weights] {weights_path}")
    weights_hash = hashlib.sha256(weights_path.read_bytes()).hexdigest()
    result_dir.mkdir(parents=True, exist_ok=True)
    write_json(result_dir / "training_config.json", {
        "model": "YAMNet partial fine-tuning + 2-layer BiLSTM", "keras_api": "tf_keras",
        "tensorflow_version": tf.__version__, "tf_keras_version": keras.__version__,
        "data_dir": str(DATA_DIR), "fold_names": FOLD_NAMES, "label_map": label_map,
        "pretrained_weights_url": WEIGHTS_URL, "pretrained_weights_sha256": weights_hash,
        "seed": SEED, "validation_source_fraction": VAL_SIZE,
        "batch_size": args.batch_size, "head_epochs": args.head_epochs,
        "fine_tune_epochs": args.fine_tune_epochs, "head_learning_rate": HEAD_LEARNING_RATE,
        "fine_tune_learning_rate": FINE_TUNE_LEARNING_RATE, "patience": PATIENCE,
        "first_fine_tune_block": FIRST_FINE_TUNE_BLOCK, "batch_normalization_frozen": True,
        "monitor": "val_loss", "selection": "minimum across BOTH stages; no test-based selection",
        "sample_rate": SAMPLE_RATE, "num_samples": NUM_SAMPLES,
    })
    results, all_true, all_pred = [], [], []
    for fold_name in FOLD_NAMES:
        keras.backend.clear_session()
        keras.utils.set_random_seed(SEED)
        test_records = records_for_fold(records, fold_name)
        candidates = [record for record in records if record["fold"] != fold_name]
        train_records, val_records = split_train_validation(candidates, val_size=VAL_SIZE, seed=SEED)
        print(f"\n========== Eval: {fold_name} ========== ")
        print_split_summary(train_records, val_records, test_records)
        out_dir = result_dir / fold_name
        out_dir.mkdir()
        save_splits(out_dir, {"train": train_records, "validation": val_records, "test": test_records}, label_map)
        train_data = AudioSequence(train_records, label_map, args.batch_size, shuffle=True)
        val_data = AudioSequence(val_records, label_map, args.batch_size)
        test_data = AudioSequence(test_records, label_map, args.batch_size)
        # Build/load anew for EVERY fold; never carry adapted weights across folds.
        model, backbone = build_model(len(class_names), weights_path)
        rows, selection = train_two_stages(model, backbone, train_data, val_data, out_dir, args)
        save_curves(rows, selection, out_dir)
        test_y = np.asarray([label_map[record["label"]] for record in test_records])
        probabilities = model.predict(test_data, workers=1, max_queue_size=2, verbose=1)
        if probabilities.shape != (len(test_records), len(class_names)) or not np.isfinite(probabilities).all():
            raise RuntimeError("Invalid test predictions.")
        predicted = np.argmax(probabilities, axis=1)
        report = classification_report(
            test_y, predicted, labels=list(range(len(class_names))), target_names=class_names,
            output_dict=True, zero_division=0,
        )
        metrics = {
            "fold": fold_name, "accuracy": float(accuracy_score(test_y, predicted)),
            "macro_f1": float(f1_score(test_y, predicted, average="macro")),
            "weighted_f1": float(f1_score(test_y, predicted, average="weighted")),
            "siren_recall": float(report["siren"]["recall"]), **selection,
        }
        write_json(out_dir / "test_metrics.json", {"metrics": metrics, "classification_report": report})
        cm = confusion_matrix(test_y, predicted, labels=list(range(len(class_names))))
        np.save(out_dir / "cm.npy", cm)
        save_confusion(cm, class_names, out_dir / "confusion_matrix.png")
        # Includes the adapted YAMNet, frontend AND classifier, not just the head.
        model.save(str(out_dir / "final.keras"))
        print(json.dumps(metrics, ensure_ascii=False, indent=2))
        results.append(metrics)
        all_true.append(test_y)
        all_pred.append(predicted)
        del model, backbone, train_data, val_data, test_data
        keras.backend.clear_session()
        gc.collect()
    with (result_dir / "fold_metrics.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    summary = {}
    for key in ("accuracy", "macro_f1", "weighted_f1", "siren_recall"):
        values = np.asarray([row[key] for row in results])
        summary[key] = {"mean": float(values.mean()), "std": float(values.std(ddof=0))}
        print(f"{key}: {values.mean():.4f} +/- {values.std(ddof=0):.4f}")
    write_json(result_dir / "summary.json", summary)
    overall_cm = confusion_matrix(np.concatenate(all_true), np.concatenate(all_pred), labels=list(range(len(class_names))))
    np.save(result_dir / "cm_overall.npy", overall_cm)
    save_confusion(overall_cm, class_names, result_dir / "confusion_matrix_overall.png")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument("--head-epochs", type=int, default=HEAD_EPOCHS)
    parser.add_argument("--fine-tune-epochs", type=int, default=FINE_TUNE_EPOCHS)
    parser.add_argument("--weights", type=Path, help="Existing official yamnet.h5; otherwise download automatically.")
    parser.add_argument("--result-dir", type=Path, default=RESULT_DIR)
    args = parser.parse_args()
    if min(args.batch_size, args.head_epochs, args.fine_tune_epochs) < 1:
        parser.error("Batch size and both epoch limits must be positive.")
    return args


if __name__ == "__main__":
    run_training(parse_args())
