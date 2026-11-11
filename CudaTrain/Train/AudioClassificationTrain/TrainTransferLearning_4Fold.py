"""Frozen YAMNet embeddings + BiLSTM, with source-disjoint 4-fold evaluation."""

import csv
import gc
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
from tensorflow.keras.callbacks import CSVLogger, EarlyStopping, ModelCheckpoint
from tensorflow.keras.layers import Bidirectional, Dense, Dropout, Input, LSTM, Masking
from tensorflow.keras.models import Sequential

from ExtractYAMNetFeatures import DATA_DIR, FEATURES_DIR, MODEL_HANDLE, load_fold_features
from fold_training_utils import (
    FOLD_NAMES,
    build_label_map,
    load_accepted_records,
    print_split_summary,
    records_for_fold,
    split_train_validation,
)


SCRIPT_DIR = Path(__file__).resolve().parent
RESULT_DIR = (SCRIPT_DIR / "../../Result/runs_transferlearning_fold1to4").resolve()
EPOCHS = 100
BATCH_SIZE = 32
LEARNING_RATE = 1e-4
PATIENCE = 5
VAL_SIZE = 0.1
SEED = 42


def build_rnn_model(input_shape, num_classes):
    # Preserve the original YAMNet classifier for the fixed-feature baseline.
    model = Sequential([
        Input(shape=input_shape),
        Masking(mask_value=0.0),
        Bidirectional(LSTM(64, return_sequences=True)),
        Bidirectional(LSTM(64)),
        Dense(64, activation="relu"),
        Dropout(0.5),
        Dense(num_classes, activation="softmax"),
    ])
    model.compile(
        optimizer=tf.keras.optimizers.Adam(LEARNING_RATE),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def load_features(records, label_map):
    """Reuse frozen features; never fit YAMNet on the downstream data."""
    batches = []
    ordered_records = []
    for fold_name in FOLD_NAMES:
        selected = records_for_fold(records, fold_name)
        if not selected:
            raise RuntimeError(f"No records in {fold_name}.")
        features, _ = load_fold_features(FEATURES_DIR / f"{fold_name}.npz", selected)
        batches.append(features)
        ordered_records.extend(selected)
        print(f"[Features] {fold_name}: {features.shape}")
    max_frames = max(batch.shape[1] for batch in batches)
    x = np.zeros((len(ordered_records), max_frames, batches[0].shape[2]), dtype=np.float32)
    start = 0
    for batch in batches:
        x[start : start + len(batch), : batch.shape[1]] = batch
        start += len(batch)
    y = np.asarray([label_map[record["label"]] for record in ordered_records], dtype=np.int64)
    index_by_path = {record["path"]: index for index, record in enumerate(ordered_records)}
    if len(index_by_path) != len(ordered_records):
        raise RuntimeError("Duplicate audio paths in the manifest.")
    return x, y, index_by_path


def indexes_for(records, index_by_path):
    return np.asarray([index_by_path[record["path"]] for record in records], dtype=np.int64)


def save_splits(out_dir, splits):
    seen = set()
    for name, selected in splits.items():
        sources = {record["source_id"] for record in selected}
        if not selected or seen & sources:
            raise RuntimeError(f"Empty or overlapping source split: {name}")
        seen.update(sources)
    with (out_dir / "split_manifest.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=["split", "fold", "source_id", "label", "relative_path"])
        writer.writeheader()
        for name, selected in splits.items():
            for record in selected:
                writer.writerow({
                    "split": name,
                    "fold": record["fold"],
                    "source_id": record["source_id"],
                    "label": record["label"],
                    "relative_path": record["path"].relative_to(DATA_DIR).as_posix(),
                })


def save_curves(history, out_dir):
    for metric, filename in (("loss", "loss_curve.png"), ("accuracy", "accuracy_curve.png")):
        epochs = range(1, len(history.history[metric]) + 1)
        plt.figure(figsize=(8, 5))
        plt.plot(epochs, history.history[metric], label=f"train_{metric}")
        plt.plot(epochs, history.history[f"val_{metric}"], label=f"val_{metric}")
        plt.xlabel("Epoch")
        plt.ylabel(metric)
        plt.legend()
        plt.grid(True)
        plt.tight_layout()
        plt.savefig(out_dir / filename)
        plt.close()


def save_confusion_matrix(cm, class_names, destination):
    plt.figure(figsize=(6, 5))
    sns.heatmap(cm, annot=True, fmt="d", cmap="Blues", xticklabels=class_names, yticklabels=class_names)
    plt.xlabel("Predicted")
    plt.ylabel("True")
    plt.tight_layout()
    plt.savefig(destination)
    plt.close()


def run_fold_training():
    for gpu in tf.config.list_physical_devices("GPU"):
        tf.config.experimental.set_memory_growth(gpu, True)
    records = load_accepted_records(DATA_DIR)
    label_map = build_label_map(records)
    class_names = sorted(label_map, key=label_map.get)
    x, y, index_by_path = load_features(records, label_map)
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    with (RESULT_DIR / "training_config.json").open("w", encoding="utf-8") as file:
        json.dump({
            "model": "frozen YAMNet + 2-layer BiLSTM",
            "yamnet_handle": MODEL_HANDLE,
            "features_dir": str(FEATURES_DIR),
            "data_dir": str(DATA_DIR),
            "fold_names": FOLD_NAMES,
            "label_map": label_map,
            "seed": SEED,
            "validation_source_fraction": VAL_SIZE,
            "epochs": EPOCHS,
            "batch_size": BATCH_SIZE,
            "learning_rate": LEARNING_RATE,
            "patience": PATIENCE,
            "monitor": "val_loss",
        }, file, ensure_ascii=False, indent=2)

    results = []
    all_true, all_pred = [], []
    for fold_name in FOLD_NAMES:
        tf.keras.backend.clear_session()
        tf.keras.utils.set_random_seed(SEED)
        print(f"\n========== Eval: {fold_name} ==========")
        test_records = records_for_fold(records, fold_name)
        candidates = [record for record in records if record["fold"] != fold_name]
        train_records, val_records = split_train_validation(candidates, val_size=VAL_SIZE, seed=SEED)
        print_split_summary(train_records, val_records, test_records)
        out_dir = RESULT_DIR / fold_name
        out_dir.mkdir(parents=True, exist_ok=True)
        save_splits(out_dir, {"train": train_records, "validation": val_records, "test": test_records})
        train_indexes = indexes_for(train_records, index_by_path)
        val_indexes = indexes_for(val_records, index_by_path)
        test_indexes = indexes_for(test_records, index_by_path)
        model = build_rnn_model(x.shape[1:], len(class_names))
        history = model.fit(
            x[train_indexes], y[train_indexes],
            validation_data=(x[val_indexes], y[val_indexes]),
            epochs=EPOCHS,
            batch_size=BATCH_SIZE,
            callbacks=[
                EarlyStopping(monitor="val_loss", mode="min", patience=PATIENCE, restore_best_weights=True, verbose=1),
                ModelCheckpoint(out_dir / "best.keras", monitor="val_loss", mode="min", save_best_only=True),
                CSVLogger(out_dir / "history.csv"),
            ],
            verbose=2,
        )
        model.load_weights(out_dir / "best.keras")
        save_curves(history, out_dir)
        test_y = y[test_indexes]
        predicted = np.argmax(model.predict(x[test_indexes], verbose=1), axis=1)
        report = classification_report(
            test_y, predicted, labels=list(range(len(class_names))),
            target_names=class_names, output_dict=True, zero_division=0,
        )
        metrics = {
            "fold": fold_name,
            "accuracy": float(accuracy_score(test_y, predicted)),
            "macro_f1": float(f1_score(test_y, predicted, average="macro")),
            "weighted_f1": float(f1_score(test_y, predicted, average="weighted")),
            "siren_recall": float(report["siren"]["recall"]),
            "best_epoch": int(np.argmin(history.history["val_loss"])) + 1,
            "best_val_loss": float(min(history.history["val_loss"])),
        }
        print(json.dumps(metrics, ensure_ascii=False, indent=2))
        with (out_dir / "test_metrics.json").open("w", encoding="utf-8") as file:
            json.dump({"metrics": metrics, "classification_report": report}, file, ensure_ascii=False, indent=2)
        cm = confusion_matrix(test_y, predicted, labels=list(range(len(class_names))))
        np.save(out_dir / "cm.npy", cm)
        save_confusion_matrix(cm, class_names, out_dir / "confusion_matrix.png")
        model.save(out_dir / "final.keras")
        results.append(metrics)
        all_true.append(test_y)
        all_pred.append(predicted)
        del model, history
        gc.collect()

    with (RESULT_DIR / "fold_metrics.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    summary = {}
    print("\n===== Frozen YAMNet + LSTM: 4-Fold Summary (std ddof=0) =====")
    for key in ("accuracy", "macro_f1", "weighted_f1", "siren_recall"):
        values = np.asarray([row[key] for row in results])
        summary[key] = {"mean": float(values.mean()), "std": float(values.std(ddof=0))}
        print(f"{key}: {values.mean():.4f} +/- {values.std(ddof=0):.4f}")
    with (RESULT_DIR / "summary.json").open("w", encoding="utf-8") as file:
        json.dump(summary, file, ensure_ascii=False, indent=2)
    overall_cm = confusion_matrix(np.concatenate(all_true), np.concatenate(all_pred), labels=list(range(len(class_names))))
    np.save(RESULT_DIR / "cm_overall.npy", overall_cm)
    save_confusion_matrix(overall_cm, class_names, RESULT_DIR / "confusion_matrix_overall.png")


if __name__ == "__main__":
    run_fold_training()
