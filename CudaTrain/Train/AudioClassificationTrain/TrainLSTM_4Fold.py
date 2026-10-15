import gc
from pathlib import Path

import librosa
import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
import tensorflow as tf
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)
from sklearn.utils.class_weight import compute_class_weight
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.layers import Bidirectional, Dense, Dropout, Input, LSTM, Masking
from tensorflow.keras.models import Sequential

from fold_training_utils import (
    FOLD_NAMES,
    build_label_map,
    load_accepted_records,
    print_split_summary,
    records_for_fold,
    split_train_validation,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = (
    SCRIPT_DIR / "../../../Mixed_US8K_ESC50_dataset/04_silence_filtered"
).resolve()
RESULT_DIR = (SCRIPT_DIR / "../../Result/runs_lstm_fold1to4").resolve()

SAMPLE_RATE = 16000
DURATION = 1.0
MAX_LEN_SAMPLES = int(SAMPLE_RATE * DURATION)
N_MFCC = 13
HOP_LENGTH = 512
MAX_LEN_FRAMES = int(np.ceil(MAX_LEN_SAMPLES / HOP_LENGTH))
EPOCHS = 100
BATCH_SIZE = 16
VAL_SIZE = 0.1
PATIENCE = 50
SEED = 42

np.random.seed(SEED)
tf.random.set_seed(SEED)


def configure_gpu():
    gpus = tf.config.list_physical_devices("GPU")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except RuntimeError:
            pass
    print(f"[Info] GPUs: {gpus}")


def wav_to_mfcc(path: Path):
    wav, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True)
    if len(wav) < MAX_LEN_SAMPLES:
        wav = np.pad(wav, (0, MAX_LEN_SAMPLES - len(wav)))
    else:
        wav = wav[:MAX_LEN_SAMPLES]

    mfcc = librosa.feature.mfcc(
        y=wav,
        sr=SAMPLE_RATE,
        n_mfcc=N_MFCC,
        hop_length=HOP_LENGTH,
    ).T
    if mfcc.shape[0] < MAX_LEN_FRAMES:
        mfcc = np.pad(
            mfcc,
            ((0, MAX_LEN_FRAMES - mfcc.shape[0]), (0, 0)),
            mode="constant",
        )
    else:
        mfcc = mfcc[:MAX_LEN_FRAMES]
    return mfcc.astype(np.float32)


def build_rnn_model(input_shape, num_classes):
    model = Sequential(
        [
            Input(shape=input_shape),
            Masking(mask_value=0.0),
            Bidirectional(LSTM(64, return_sequences=True)),
            Bidirectional(LSTM(64)),
            Dense(64, activation="relu"),
            Dropout(0.5),
            Dense(num_classes, activation="softmax"),
        ]
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-4),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def load_features(records, label_map):
    print("全音声からMFCCを抽出しています...")
    features = []
    labels = []
    index_by_path = {}
    for index, record in enumerate(records):
        features.append(wav_to_mfcc(record["path"]))
        labels.append(label_map[record["label"]])
        index_by_path[record["path"]] = index
    x = np.stack(features)
    y = np.asarray(labels, dtype=np.int64)
    print(f"読み込み完了: X={x.shape}, y={y.shape}")
    return x, y, index_by_path


def indexes_for(records, index_by_path):
    return np.asarray([index_by_path[record["path"]] for record in records])


def save_curves(history, out_dir):
    plt.figure(figsize=(8, 5))
    plt.plot(history.history["loss"], label="train_loss")
    plt.plot(history.history["val_loss"], label="val_loss")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(out_dir / "loss_curve.png")
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.plot(history.history["accuracy"], label="train_accuracy")
    plt.plot(history.history["val_accuracy"], label="val_accuracy")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(out_dir / "accuracy_curve.png")
    plt.close()


def run_fold_training():
    configure_gpu()
    records = load_accepted_records(DATA_DIR)
    label_map = build_label_map(records)
    class_names = [name for name, _ in sorted(label_map.items(), key=lambda item: item[1])]
    n_classes = len(class_names)
    x, y, index_by_path = load_features(records, label_map)

    fold_results = []
    y_true_all = []
    y_pred_all = []

    for fold_number, eval_fold_name in enumerate(FOLD_NAMES, start=1):
        print(f"\n========== Fold {fold_number}/4: Eval={eval_fold_name} ==========")
        eval_records = records_for_fold(records, eval_fold_name)
        candidate_records = [
            record for record in records if record["fold"] != eval_fold_name
        ]
        train_records, val_records = split_train_validation(
            candidate_records, val_size=VAL_SIZE, seed=SEED
        )
        print_split_summary(train_records, val_records, eval_records)

        train_indexes = indexes_for(train_records, index_by_path)
        val_indexes = indexes_for(val_records, index_by_path)
        eval_indexes = indexes_for(eval_records, index_by_path)

        x_train, y_train = x[train_indexes], y[train_indexes]
        x_val, y_val = x[val_indexes], y[val_indexes]
        x_eval, y_eval = x[eval_indexes], y[eval_indexes]

        weights = compute_class_weight(
            class_weight="balanced",
            classes=np.arange(n_classes),
            y=y_train,
        )
        class_weight = {index: weight for index, weight in enumerate(weights)}

        out_dir = RESULT_DIR / eval_fold_name
        out_dir.mkdir(parents=True, exist_ok=True)
        model = build_rnn_model(x.shape[1:], n_classes)
        callbacks = [
            EarlyStopping(
                monitor="val_loss",
                patience=PATIENCE,
                restore_best_weights=True,
            ),
            ModelCheckpoint(
                out_dir / "best.keras",
                monitor="val_loss",
                save_best_only=True,
            ),
        ]
        history = model.fit(
            x_train,
            y_train,
            validation_data=(x_val, y_val),
            epochs=EPOCHS,
            batch_size=BATCH_SIZE,
            class_weight=class_weight,
            callbacks=callbacks,
            verbose=2,
        )
        save_curves(history, out_dir)

        y_pred = np.argmax(model.predict(x_eval, verbose=1), axis=1)
        accuracy = accuracy_score(y_eval, y_pred)
        macro_f1 = f1_score(y_eval, y_pred, average="macro")
        weighted_f1 = f1_score(y_eval, y_pred, average="weighted")
        fold_results.append((accuracy, macro_f1, weighted_f1))
        y_true_all.append(y_eval)
        y_pred_all.append(y_pred)

        print(classification_report(y_eval, y_pred, target_names=class_names, digits=4))
        print(
            f"[Fold {fold_number}] Accuracy={accuracy:.4f}, "
            f"Macro-F1={macro_f1:.4f}, Weighted-F1={weighted_f1:.4f}"
        )
        np.save(out_dir / "cm.npy", confusion_matrix(y_eval, y_pred))
        model.save(out_dir / "final.keras")

        tf.keras.backend.clear_session()
        del model, history
        gc.collect()

    scores = np.asarray(fold_results)
    print("\n===== 4-Fold Summary =====")
    print(f"Accuracy    : {scores[:, 0].mean():.4f} ± {scores[:, 0].std():.4f}")
    print(f"Macro-F1    : {scores[:, 1].mean():.4f} ± {scores[:, 1].std():.4f}")
    print(f"Weighted-F1 : {scores[:, 2].mean():.4f} ± {scores[:, 2].std():.4f}")

    y_true_all = np.concatenate(y_true_all)
    y_pred_all = np.concatenate(y_pred_all)
    cm = confusion_matrix(y_true_all, y_pred_all)
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(7, 6))
    sns.heatmap(
        cm,
        annot=True,
        fmt="d",
        cmap="Blues",
        xticklabels=class_names,
        yticklabels=class_names,
    )
    plt.xlabel("Predicted")
    plt.ylabel("True")
    plt.title("Confusion Matrix (4-Fold Overall)")
    plt.tight_layout()
    plt.savefig(RESULT_DIR / "confusion_matrix_overall.png")
    plt.close()


if __name__ == "__main__":
    run_fold_training()
