"""One source-disjoint holdout run of frozen YAMNet embeddings + BiLSTM.

Fold5 is reserved and never used here. Reuses the existing CRNN holdout split
when available, and the same validated fold1-fold4 feature caches as 4-fold TL.
"""

import argparse
import csv
import json
from pathlib import Path
import sys

import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
TRAIN_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(TRAIN_DIR))

from ExtractYAMNetFeatures import DATA_DIR, FEATURES_DIR, MODEL_HANDLE
from fold_training_utils import (
    FOLD_NAMES, build_label_map, load_accepted_records,
    print_split_summary, split_train_validation,
)


RESULT_ROOT = (TRAIN_DIR / "../../Result").resolve()
RESULT_DIR = RESULT_ROOT / "runs_transferlearning_holdout_2Class_mix"
CRNN_SPLIT_MANIFEST = RESULT_ROOT / "runs_crnn_slidwindow_1p_holdout_2Class_mix/split_manifest.csv"
TEST_SIZE = 0.2
VAL_SIZE = 0.1
SEED = 42
EPOCHS = 100
BATCH_SIZE = 32
PATIENCE = 5
SPLIT_NAMES = ("train", "validation", "test")


def validate_splits(records, splits):
    """Require complete, unique, source-disjoint membership and both classes."""
    if set(splits) != set(SPLIT_NAMES):
        raise ValueError(f"Expected splits {SPLIT_NAMES}.")
    expected = {record["path"] for record in records}
    if len(expected) != len(records):
        raise ValueError("Duplicate audio paths in dataset records.")
    expected_labels = {record["label"] for record in records}
    seen_paths, seen_sources = set(), set()
    for name in SPLIT_NAMES:
        selected = splits[name]
        paths = {record["path"] for record in selected}
        sources = {record["source_id"] for record in selected}
        if not selected or len(paths) != len(selected) or seen_paths & paths:
            raise ValueError(f"Empty or duplicated audio in {name}.")
        if seen_sources & sources:
            raise ValueError(f"source_id overlap in {name}.")
        if {record["label"] for record in selected} != expected_labels:
            raise ValueError(f"Missing class in {name}.")
        if any(record["fold"] not in FOLD_NAMES for record in selected):
            raise ValueError("Fold5 and excluded audio must not be used.")
        seen_paths.update(paths)
        seen_sources.update(sources)
    if seen_paths != expected:
        raise ValueError("Split manifest does not cover the current accepted fold1-fold4 data exactly.")


def split_holdout_records(records):
    train_val, test = split_train_validation(records, val_size=TEST_SIZE, seed=SEED)
    train, validation = split_train_validation(train_val, val_size=VAL_SIZE, seed=SEED)
    splits = {"train": train, "validation": validation, "test": test}
    validate_splits(records, splits)
    return splits


def load_saved_splits(records, manifest_path, label_map):
    """Match portable relative paths and verify provenance against DATA_DIR."""
    by_path = {record["path"].relative_to(DATA_DIR).as_posix(): record for record in records}
    if len(by_path) != len(records):
        raise ValueError("Duplicate audio paths in dataset records.")
    splits = {name: [] for name in SPLIT_NAMES}
    with Path(manifest_path).open(encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)
        required = {"split", "relative_path", "source_id", "fold", "label"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"Missing split columns in {manifest_path}.")
        for row in reader:
            name = row["split"]
            relative_path = row["relative_path"].replace("\\", "/")
            if name not in splits or relative_path not in by_path:
                raise ValueError(f"Unknown split or audio: {name}, {relative_path}")
            record = by_path[relative_path]
            if any(row[key] != record[key] for key in ("source_id", "fold", "label")):
                raise ValueError(f"Split metadata differs from current dataset: {relative_path}")
            if "label_id" in row and row["label_id"] != str(label_map[record["label"]]):
                raise ValueError(f"Label ID differs from current label map: {relative_path}")
            splits[name].append(record)
    validate_splits(records, splits)
    return splits


def prepare_splits(records, label_map, manifest_path=None):
    # Explicitly requested manifests must exist; do not silently generate a
    # different test set when the user provided a misspelled path.
    if manifest_path is not None:
        selected_manifest = Path(manifest_path).resolve()
        if not selected_manifest.is_file():
            raise FileNotFoundError(selected_manifest)
    else:
        selected_manifest = CRNN_SPLIT_MANIFEST if CRNN_SPLIT_MANIFEST.is_file() else None
    if selected_manifest is not None:
        splits = load_saved_splits(records, selected_manifest, label_map)
        origin = {"kind": "saved_manifest", "path": str(selected_manifest)}
    else:
        splits = split_holdout_records(records)
        origin = {
            "kind": "generated_source_split", "seed": SEED,
            "test_source_fraction": TEST_SIZE,
            "validation_source_fraction_of_train_val": VAL_SIZE,
        }
    return splits, origin


def split_counts(splits):
    return {
        name: {
            "windows": len(selected),
            "sources": len({record["source_id"] for record in selected}),
            "classes": {
                label: {
                    "windows": sum(record["label"] == label for record in selected),
                    "sources": len({record["source_id"] for record in selected if record["label"] == label}),
                } for label in sorted({record["label"] for record in selected})
            },
        } for name, selected in splits.items()
    }


def write_json(path, value):
    with Path(path).open("w", encoding="utf-8") as file:
        json.dump(value, file, ensure_ascii=False, indent=2, allow_nan=False)


def run_training(args):
    records = load_accepted_records(DATA_DIR)
    label_map = build_label_map(records)
    if set(label_map) != {"other", "siren"}:
        raise ValueError(f"Expected other/siren labels, got {label_map}.")
    splits, origin = prepare_splits(records, label_map, args.split_manifest)
    print(f"[Dataset] {DATA_DIR}")
    print(f"[Features] {FEATURES_DIR}")
    print(f"[Split origin] {origin}")
    print_split_summary(splits["train"], splits["validation"], splits["test"])
    counts = split_counts(splits)
    if args.check_only:
        print(json.dumps(counts, ensure_ascii=False, indent=2))
        print("[Check only] Split is valid. Features were not loaded; training and test inference were NOT run.")
        return

    out_dir = args.result_dir.resolve()
    if out_dir.exists() and any(out_dir.iterdir()):
        raise FileExistsError(f"Results already exist: {out_dir}. Use --result-dir with a new directory.")

    # Import only for real training, so --check-only needs no TensorFlow or plots.
    import tensorflow as tf
    from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, f1_score
    from tensorflow.keras.callbacks import CSVLogger, EarlyStopping, ModelCheckpoint, TerminateOnNaN
    from TrainTransferLearning_4Fold import (
        LEARNING_RATE, build_rnn_model, indexes_for, load_features,
        save_confusion_matrix, save_curves, save_splits,
    )

    for gpu in tf.config.list_physical_devices("GPU"):
        tf.config.experimental.set_memory_growth(gpu, True)
    tf.keras.backend.clear_session()
    tf.keras.utils.set_random_seed(SEED)
    print(f"[GPU] {tf.config.list_physical_devices('GPU')}")
    print("[Features] Validating/reusing frozen fold1-fold4 caches; no YAMNet weights are updated.")
    x, y, index_by_path = load_features(records, label_map)
    indexes = {name: indexes_for(selected, index_by_path) for name, selected in splits.items()}
    class_names = sorted(label_map, key=label_map.get)

    # Cache errors above do not leave an output directory that blocks a retry.
    out_dir.mkdir(parents=True, exist_ok=True)
    save_splits(out_dir, splits)
    write_json(out_dir / "label_map.json", label_map)
    write_json(out_dir / "training_config.json", {
        "model": "frozen YAMNet + 2-layer BiLSTM (single holdout)",
        "tensorflow_version": tf.__version__, "yamnet_handle": MODEL_HANDLE,
        "data_dir": str(DATA_DIR), "features_dir": str(FEATURES_DIR),
        "fold_names": FOLD_NAMES, "fold5_used": False,
        "split_origin": origin, "split_counts": counts,
        "label_map": label_map, "training_seed": SEED,
        "epochs": args.epochs, "batch_size": args.batch_size,
        "learning_rate": LEARNING_RATE, "class_weight": None,
        "monitor": "val_loss", "patience": PATIENCE,
        "input_shape": list(x.shape[1:]),
        "saved_model_contents": "LSTM classifier only; use frozen YAMNet embeddings at inference",
    })
    model = build_rnn_model(x.shape[1:], len(class_names))
    model.summary()
    history = model.fit(
        x[indexes["train"]], y[indexes["train"]],
        validation_data=(x[indexes["validation"]], y[indexes["validation"]]),
        epochs=args.epochs, batch_size=args.batch_size,
        callbacks=[
            EarlyStopping(monitor="val_loss", mode="min", patience=PATIENCE, restore_best_weights=True, verbose=1),
            ModelCheckpoint(out_dir / "best.keras", monitor="val_loss", mode="min", save_best_only=True),
            CSVLogger(out_dir / "history.csv"), TerminateOnNaN(),
        ], verbose=2,
    )
    val_losses = np.asarray(history.history["val_loss"])
    if not np.isfinite(val_losses).all() or not (out_dir / "best.keras").is_file():
        raise RuntimeError("No valid best checkpoint; test evaluation was not performed.")
    model.load_weights(out_dir / "best.keras")
    save_curves(history, out_dir)
    best_index = int(np.argmin(val_losses))
    selection = {
        "best_epoch": best_index + 1, "stopped_epoch": len(val_losses),
        "best_val_loss": float(val_losses[best_index]),
        "best_val_accuracy": float(history.history["val_accuracy"][best_index]),
    }
    write_json(out_dir / "model_selection.json", selection)

    # Test never participates in fitting, early stopping or checkpoint selection.
    test_y = y[indexes["test"]]
    probabilities = model.predict(x[indexes["test"]], batch_size=args.batch_size, verbose=1)
    if probabilities.shape != (len(test_y), len(class_names)) or not np.isfinite(probabilities).all():
        raise RuntimeError("Invalid test probabilities.")
    predicted = np.argmax(probabilities, axis=1)
    report = classification_report(
        test_y, predicted, labels=list(range(len(class_names))), target_names=class_names,
        output_dict=True, zero_division=0,
    )
    metrics = {
        "accuracy": float(accuracy_score(test_y, predicted)),
        "macro_f1": float(f1_score(test_y, predicted, average="macro")),
        "weighted_f1": float(f1_score(test_y, predicted, average="weighted")),
        "siren_precision": float(report["siren"]["precision"]),
        "siren_recall": float(report["siren"]["recall"]),
        "test_loss": float(np.mean(tf.keras.losses.sparse_categorical_crossentropy(test_y, probabilities))),
        **selection,
    }
    write_json(out_dir / "test_metrics.json", {"metrics": metrics, "classification_report": report})
    cm = confusion_matrix(test_y, predicted, labels=list(range(len(class_names))))
    np.save(out_dir / "cm.npy", cm)
    save_confusion_matrix(cm, class_names, out_dir / "confusion_matrix.png")
    with (out_dir / "test_predictions.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["relative_path", "source_id", "true_label", "predicted_label", "siren_probability"])
        for record, prediction, probability in zip(splits["test"], predicted, probabilities):
            writer.writerow([
                record["path"].relative_to(DATA_DIR).as_posix(), record["source_id"],
                record["label"], class_names[int(prediction)], float(probability[label_map["siren"]]),
            ])
    model.save(out_dir / "final.keras")
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    print(f"[Saved] {out_dir}")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-only", action="store_true", help="Validate only dataset/splits; do not load features or train.")
    parser.add_argument("--split-manifest", type=Path, help="Exact saved split; default: reuse CRNN manifest if present, otherwise generate.")
    parser.add_argument("--result-dir", type=Path, default=RESULT_DIR)
    parser.add_argument("--epochs", type=int, default=EPOCHS)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    args = parser.parse_args()
    if min(args.epochs, args.batch_size) < 1:
        parser.error("Epochs and batch size must be positive.")
    return args


if __name__ == "__main__":
    run_training(parse_args())
