# -*- coding: utf-8 -*-
# manifest.csvの元音源IDでTrain / Validation / Testを一度だけ分割する。
# fold1～fold4のaccepted音声を使用し、fold5と除外音声は使用しない。
# CRNN + Attentionのモデル構成・学習条件は維持する。

import csv
import json
import os
import sys
os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"

import numpy as np
import librosa
from pathlib import Path
import matplotlib.pyplot as plt

from sklearn.metrics import classification_report, confusion_matrix, precision_recall_fscore_support, accuracy_score
from sklearn.utils.class_weight import compute_class_weight

import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.callbacks import CSVLogger, EarlyStopping, ModelCheckpoint, ReduceLROnPlateau# type: ignore

import seaborn as sns
import random

SCRIPT_DIR = Path(__file__).resolve().parent
# Without9Foldから、4-fold版と共通のmanifest読込・元音源分割を利用する。
sys.path.insert(0, str(SCRIPT_DIR.parent))
from fold_training_utils import (
    FOLD_NAMES,
    build_label_map,
    load_accepted_records,
    split_train_validation,
    unpack_records,
)

# ============================================================
# 1) 設定
# ============================================================
DATA_DIR = (
    SCRIPT_DIR / "../../../data/Mixed_US8K_ESC50_dataset/04_silence_filtered"
).resolve()
OUT_DIR = (
    SCRIPT_DIR / "../../../Result/runs_crnn_slidwindow_1p_holdout_2Class_mix"
).resolve()

SAMPLE_RATE = 16000
DURATION = 1.0
WIN_SAMPLES = int(SAMPLE_RATE * DURATION)

N_MELS = 128
N_FFT = 1024
HOP_LENGTH = 512
FMIN, FMAX = 20, 8000

# 元音源数に対する割合。ValidationはTestを除いた残りの10%。
# 全体ではおおむねTrain 72% / Validation 8% / Test 20%。
TEST_SIZE = 0.2
VAL_SIZE = 0.1
EPOCHS = 50
BATCH_SIZE = 32
PATIENCE = 5
SEED = 42


# ============================================================
# 2) 下準備
# ============================================================
def set_seed(seed=42):
    np.random.seed(seed)
    random.seed(seed)
    tf.random.set_seed(seed)

set_seed(SEED)


def split_holdout_records(records, test_size=TEST_SIZE, val_size=VAL_SIZE, seed=SEED):
    """元音源のクラス比率を保ち、3集合に同じsource_idが入らないよう分割する。"""
    if not 0 < test_size < 1 or not 0 < val_size < 1:
        raise ValueError("TEST_SIZEとVAL_SIZEは0より大きく1未満にしてください。")

    train_val_records, test_records = split_train_validation(
        records, val_size=test_size, seed=seed
    )
    train_records, val_records = split_train_validation(
        train_val_records, val_size=val_size, seed=seed
    )
    splits = {"train": train_records, "validation": val_records, "test": test_records}
    seen_sources = set()
    expected_labels = {record["label"] for record in records}
    for split_name, selected in splits.items():
        if not selected:
            raise RuntimeError(f"{split_name}に音声がありません。")
        sources = {record["source_id"] for record in selected}
        if seen_sources & sources:
            raise RuntimeError(f"{split_name}と他の分割でsource_idが重複しています。")
        if {record["label"] for record in selected} != expected_labels:
            raise RuntimeError(f"{split_name}に全クラスが含まれていません。")
        seen_sources.update(sources)
    if sum(len(selected) for selected in splits.values()) != len(records):
        raise RuntimeError("分割前後で音声ファイル数が一致しません。")
    return splits


def save_split_info(splits, label_map):
    """使用した窓と元音源の所属を保存し、後から分割を確認できるようにする。"""
    with (OUT_DIR / "split_manifest.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=["split", "source_id", "fold", "label", "label_id", "relative_path"],
        )
        writer.writeheader()
        for split_name, selected in splits.items():
            source_count = len({record["source_id"] for record in selected})
            print(f"[Split] {split_name}: {len(selected)} files / {source_count} sources")
            for label in sorted(label_map):
                class_records = [record for record in selected if record["label"] == label]
                class_sources = len({record["source_id"] for record in class_records})
                print(f"  {label}: {len(class_records)} files / {class_sources} sources")
            for record in selected:
                writer.writerow({
                    "split": split_name,
                    "source_id": record["source_id"],
                    "fold": record["fold"],
                    "label": record["label"],
                    "label_id": label_map[record["label"]],
                    "relative_path": record["path"].relative_to(DATA_DIR).as_posix(),
                })
    with (OUT_DIR / "label_map.json").open("w", encoding="utf-8") as file:
        json.dump(label_map, file, ensure_ascii=False, indent=2)
    with (OUT_DIR / "split_config.json").open("w", encoding="utf-8") as file:
        json.dump({
            "data_dir": str(DATA_DIR),
            "fold_names": FOLD_NAMES,
            "seed": SEED,
            "test_source_fraction": TEST_SIZE,
            "validation_source_fraction_of_train_val": VAL_SIZE,
        }, file, ensure_ascii=False, indent=2)


def wav_to_logmelspec(path: Path):
    y, sr = librosa.load(path, sr=SAMPLE_RATE, mono=True)

    if len(y) < WIN_SAMPLES:
        y = np.pad(y, (0, WIN_SAMPLES - len(y)))
    else:
        y = y[:WIN_SAMPLES]

    mel = librosa.feature.melspectrogram(
        y=y, sr=sr, n_fft=N_FFT, hop_length=HOP_LENGTH,
        n_mels=N_MELS, fmin=FMIN, fmax=FMAX, power=2.0
    )
    logmel = librosa.power_to_db(mel, ref=np.max)
    logmel = (logmel - logmel.mean()) / (logmel.std() + 1e-6)
    return logmel.astype(np.float32)


def spec_augment(logmel, freq_mask_param=12, time_mask_param=8, p=0.5):
    if np.random.rand() > p:
        return logmel

    x = logmel.copy()

    # freq mask
    f = np.random.randint(0, freq_mask_param + 1)
    f0 = np.random.randint(0, max(1, N_MELS - f))
    x[f0:f0 + f, :] = 0

    # time mask
    t = np.random.randint(0, time_mask_param + 1)
    t0 = np.random.randint(0, max(1, x.shape[1] - t))
    x[:, t0:t0 + t] = 0

    return x


# === Attention Layer ===
@tf.keras.utils.register_keras_serializable()
class ReduceSumLayer(layers.Layer):
    def __init__(self, axis=1, **kwargs):
        super().__init__(**kwargs)
        self.axis = axis

    def call(self, inputs):
        return tf.reduce_sum(inputs, axis=self.axis)

    def get_config(self):
        config = super().get_config()
        config.update({"axis": self.axis})
        return config


def attention_pooling(inputs):
    score = layers.Dense(1, activation="tanh")(inputs)
    weights = layers.Softmax(axis=1)(score)
    weighted = layers.Multiply()([inputs, weights])
    output = ReduceSumLayer(axis=1)(weighted)
    return output


class MelSequence(tf.keras.utils.Sequence):
    def __init__(self, paths, labels, batch_size, n_classes, training=True):
        super().__init__()
        self.paths = np.array(paths)
        self.labels = np.array(labels)
        self.batch_size = batch_size
        self.n_classes = n_classes
        self.training = training
        self.indexes = np.arange(len(self.paths))
        self.on_epoch_end()

    def __len__(self):
        return int(np.ceil(len(self.paths) / self.batch_size))

    def on_epoch_end(self):
        if self.training:
            np.random.shuffle(self.indexes)

    def __getitem__(self, idx):
        idxs = self.indexes[idx * self.batch_size:(idx + 1) * self.batch_size]
        X, y = [], []
        for i in idxs:
            logmel = wav_to_logmelspec(self.paths[i])
            if self.training:
                logmel = spec_augment(logmel)
            X.append(np.expand_dims(logmel, -1))
            y.append(self.labels[i])
        X = np.stack(X)
        y = tf.keras.utils.to_categorical(y, num_classes=self.n_classes)
        return X, y


def build_crnn(n_classes, time_dim):
    inp = layers.Input(shape=(N_MELS, time_dim, 1))

    x = layers.Conv2D(32, (3,3), padding="same")(inp)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.MaxPool2D((2,2))(x)
    x = layers.Dropout(0.2)(x)

    x = layers.Conv2D(64, (3,3), padding="same")(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.MaxPool2D((2,2))(x)
    x = layers.Dropout(0.3)(x)

    x = layers.Conv2D(128, (3,3), padding="same")(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.MaxPool2D((2,1))(x)
    x = layers.Dropout(0.3)(x)

    x = layers.Permute((2,1,3))(x)
    x = layers.TimeDistributed(layers.Flatten())(x)

    x = layers.Bidirectional(layers.LSTM(128, return_sequences=True))(x)
    x = layers.Bidirectional(layers.LSTM(64, return_sequences=True))(x)

    x = attention_pooling(x)
    x = layers.Dropout(0.4)(x)

    out = layers.Dense(n_classes, activation="softmax")(x)

    model = models.Model(inp, out)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"]
    )
    return model


# ============================================================
# 3) 学習開始
# ============================================================
def main():
    print("[INFO] データ読込中...")
    print(f"[INFO] Dataset: {DATA_DIR}")
    print(f"[INFO] Output: {OUT_DIR}")

    records = load_accepted_records(DATA_DIR)
    label_map = build_label_map(records)
    id_to_label = {v: k for k, v in label_map.items()}
    splits = split_holdout_records(records)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    save_split_info(splits, label_map)

    tr_paths, tr_y = unpack_records(splits["train"], label_map)
    val_paths, val_y = unpack_records(splits["validation"], label_map)
    test_paths, test_y = unpack_records(splits["test"], label_map)

    # time_dim 確認
    time_dim = wav_to_logmelspec(tr_paths[0]).shape[1]

    n_classes = len(label_map)

    # === class_weight ===
    base_w = compute_class_weight(class_weight="balanced", classes=np.arange(n_classes), y=tr_y)
    class_weights = {i: w for i, w in enumerate(base_w)}

    # siren だけ補正：CVと全く同じ条件
    for lbl, idx in label_map.items():
        if lbl.lower() == "siren":
            class_weights[idx] = class_weights[idx] * 0.3

    # === Generators ===
    tr_gen = MelSequence(tr_paths, tr_y, BATCH_SIZE, n_classes, training=True)
    val_gen = MelSequence(val_paths, val_y, BATCH_SIZE, n_classes, training=False)
    test_gen = MelSequence(test_paths, test_y, BATCH_SIZE, n_classes, training=False)

    # === モデル構築 ===
    model = build_crnn(n_classes, time_dim)
    model.summary()

    callbacks = [
        EarlyStopping(monitor="val_accuracy", patience=PATIENCE, restore_best_weights=True),
        ModelCheckpoint(OUT_DIR / "best.keras", save_best_only=True, monitor="val_accuracy"),
        ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=8),
        CSVLogger(OUT_DIR / "history.csv"),
    ]

    history = model.fit(
        tr_gen,
        epochs=EPOCHS,
        validation_data=val_gen,
        class_weight=class_weights,
        callbacks=callbacks,
        verbose=1
    )

    # === 学習曲線 ===
    plt.figure()
    plt.plot(history.history["loss"], label="train_loss")
    plt.plot(history.history["val_loss"], label="val_loss")
    plt.legend(); plt.grid(True); plt.title("Loss"); plt.tight_layout()
    plt.savefig(OUT_DIR / "loss_curve.png")
    plt.close()

    plt.figure()
    plt.plot(history.history["accuracy"], label="train_acc")
    plt.plot(history.history["val_accuracy"], label="val_acc")
    plt.legend(); plt.grid(True); plt.title("Accuracy"); plt.tight_layout()
    plt.savefig(OUT_DIR / "acc_curve.png")
    plt.close()

    # === テスト評価 ===
    y_pred_prob = model.predict(test_gen)
    y_pred = np.argmax(y_pred_prob, axis=1)

    print("\n=== Test Classification Report ===")
    print(classification_report(test_y, y_pred, target_names=[id_to_label[i] for i in range(n_classes)], digits=4))
    report = classification_report(
        test_y, y_pred,
        labels=list(range(n_classes)),
        target_names=[id_to_label[i] for i in range(n_classes)],
        output_dict=True,
        zero_division=0,
    )
    with (OUT_DIR / "test_metrics.json").open("w", encoding="utf-8") as file:
        json.dump(report, file, ensure_ascii=False, indent=2)

    cm = confusion_matrix(test_y, y_pred)
    np.save(OUT_DIR / "cm.npy", cm)

    plt.figure(figsize=(6,5))
    sns.heatmap(cm, annot=True, fmt="d",
                xticklabels=list(id_to_label.values()),
                yticklabels=list(id_to_label.values()))
    plt.title("Confusion Matrix")
    plt.tight_layout()
    plt.savefig(OUT_DIR / "cm.png")
    plt.close()

    # === 最終保存 ===
    model.save(OUT_DIR / "final.keras")
    print(f"[DONE] Saved to {OUT_DIR}")


if __name__ == "__main__":
    main()
