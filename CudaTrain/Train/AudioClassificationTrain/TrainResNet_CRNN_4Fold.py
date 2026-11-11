import csv
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
from tensorflow.keras.applications import ResNet50
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.layers import (
    BatchNormalization,
    Bidirectional,
    Dense,
    Dropout,
    Input,
    LSTM,
    Reshape,
)
from tensorflow.keras.models import Model

from fold_training_utils import (
    FOLD_NAMES,
    build_label_map,
    load_accepted_records,
    print_split_summary,
    records_for_fold,
    split_train_validation,
    unpack_records,
)


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = (
    SCRIPT_DIR / "../../data/Mixed_US8K_ESC50_dataset/04_silence_filtered"
).resolve()
RESULT_DIR = (SCRIPT_DIR / "../../Result/runs_resnet_crnn_fold1to4").resolve()

SAMPLE_RATE = 16000
DURATION = 1.0
MAX_LEN_SAMPLES = int(SAMPLE_RATE * DURATION)
N_MELS = 128
N_FFT = 2048
HOP_LENGTH = 512
EPOCHS = 50
HEAD_EPOCHS = 10
HEAD_LEARNING_RATE = 1e-4
FINE_TUNE_LEARNING_RATE = 1e-5
FINE_TUNE_LAYER_PREFIX = "conv5_"
BATCH_SIZE = 16
VAL_SIZE = 0.1
PATIENCE = 5
SEED = 42

tf.keras.utils.set_random_seed(SEED)


def configure_gpu():
    gpus = tf.config.list_physical_devices("GPU")
    for gpu in gpus:
        try:
            tf.config.experimental.set_memory_growth(gpu, True)
        except RuntimeError:
            pass
    print(f"[Info] GPUs: {gpus}")


def wav_to_logmel_3ch(path: Path):
    wav, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True)
    if len(wav) < MAX_LEN_SAMPLES:
        wav = np.pad(wav, (0, MAX_LEN_SAMPLES - len(wav)))
    else:
        wav = wav[:MAX_LEN_SAMPLES]

    mel = librosa.feature.melspectrogram(
        y=wav,
        sr=SAMPLE_RATE,
        n_mels=N_MELS,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
    )
    logmel = librosa.power_to_db(mel, ref=np.max).astype(np.float32)
    return np.repeat(logmel[..., np.newaxis], 3, axis=-1)


class ResNetSequence(tf.keras.utils.Sequence):
    def __init__(self, paths, labels, batch_size, training=False):
        super().__init__()
        self.paths = list(paths)
        self.labels = np.asarray(labels)
        self.batch_size = batch_size
        self.training = training
        self.indexes = np.arange(len(self.paths))
        self.on_epoch_end()

    def __len__(self):
        return int(np.ceil(len(self.paths) / self.batch_size))

    def __getitem__(self, index):
        indexes = self.indexes[index * self.batch_size : (index + 1) * self.batch_size]
        x = np.stack([wav_to_logmel_3ch(self.paths[i]) for i in indexes])
        y = self.labels[indexes]
        return x, y

    def on_epoch_end(self):
        if self.training:
            np.random.shuffle(self.indexes)


def build_resnet_crnn_model(input_shape, num_classes):
    inputs = Input(shape=input_shape)
    base_model = ResNet50(
        include_top=False,
        weights="imagenet",
        input_shape=input_shape,
    )
    base_model.trainable = False

    # Keep BatchNormalization statistics fixed during both training stages.
    x = base_model(inputs, training=False)
    reshape_dim = x.shape[1] * x.shape[2]
    feature_dim = x.shape[3]
    x = Reshape((reshape_dim, feature_dim))(x)
    x = Bidirectional(LSTM(64, return_sequences=True))(x)
    x = Bidirectional(LSTM(64))(x)
    x = Dense(64, activation="relu")(x)
    x = Dropout(0.6)(x)
    outputs = Dense(num_classes, activation="softmax")(x)

    model = Model(inputs, outputs)
    compile_model(model, HEAD_LEARNING_RATE)
    return model, base_model


def compile_model(model, learning_rate):
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )


def enable_fine_tuning(base_model):
    base_model.trainable = True
    for layer in base_model.layers:
        layer.trainable = (
            layer.name.startswith(FINE_TUNE_LAYER_PREFIX)
            and not isinstance(layer, BatchNormalization)
        )
    trainable_layers = [layer.name for layer in base_model.layers if layer.trainable]
    if not trainable_layers:
        raise RuntimeError("No ResNet layers were selected for fine-tuning.")
    print(f"[Fine-tuning] Trainable ResNet layers: {trainable_layers}")


def training_callbacks(out_dir, best_val_loss=None):
    return [
        EarlyStopping(
            monitor="val_loss",
            mode="min",
            patience=PATIENCE,
            restore_best_weights=True,
            verbose=1,
        ),
        ModelCheckpoint(
            out_dir / "best.keras",
            monitor="val_loss",
            mode="min",
            save_best_only=True,
            initial_value_threshold=best_val_loss,
            verbose=1,
        ),
    ]


def save_history(stage_histories, out_dir):
    metrics = ("loss", "accuracy", "val_loss", "val_accuracy")
    merged_history = {metric: [] for metric in metrics}
    with (out_dir / "history.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=["epoch", "stage", "stage_epoch", "learning_rate", *metrics],
        )
        writer.writeheader()
        epoch = 0
        for stage, learning_rate, history in stage_histories:
            for index in range(len(history.history["loss"])):
                epoch += 1
                row = {
                    "epoch": epoch,
                    "stage": stage,
                    "stage_epoch": index + 1,
                    "learning_rate": learning_rate,
                }
                for metric in metrics:
                    value = history.history[metric][index]
                    row[metric] = value
                    merged_history[metric].append(value)
                writer.writerow(row)
    return merged_history


def train_two_stage(model, base_model, train_sequence, val_sequence, class_weight, out_dir):
    if not 0 < HEAD_EPOCHS < EPOCHS:
        raise ValueError("HEAD_EPOCHS must be between 1 and EPOCHS - 1.")

    print(f"[Stage 1] Frozen ResNet, learning_rate={HEAD_LEARNING_RATE}")
    head_history = model.fit(
        train_sequence,
        validation_data=val_sequence,
        epochs=HEAD_EPOCHS,
        class_weight=class_weight,
        callbacks=training_callbacks(out_dir),
        verbose=2,
    )
    # Start fine-tuning from the best head-training checkpoint.
    model.load_weights(out_dir / "best.keras")
    head_best_loss = min(head_history.history["val_loss"])
    stage_histories = [("head", HEAD_LEARNING_RATE, head_history)]
    save_history(stage_histories, out_dir)

    enable_fine_tuning(base_model)
    # Recompile with a new optimizer after changing trainable layers.
    compile_model(model, FINE_TUNE_LEARNING_RATE)
    print(
        f"[Stage 2] Fine-tune {FINE_TUNE_LAYER_PREFIX} layers, "
        f"learning_rate={FINE_TUNE_LEARNING_RATE}"
    )
    fine_tune_history = model.fit(
        train_sequence,
        validation_data=val_sequence,
        epochs=EPOCHS - HEAD_EPOCHS,
        class_weight=class_weight,
        callbacks=training_callbacks(out_dir, best_val_loss=head_best_loss),
        verbose=2,
    )
    # Stage 2 only replaces best.keras if it improves on Stage 1.
    model.load_weights(out_dir / "best.keras")
    fine_tune_best_loss = min(fine_tune_history.history["val_loss"])
    best_stage = "fine_tune" if fine_tune_best_loss < head_best_loss else "head"
    print(
        f"[Best model] stage={best_stage}, "
        f"val_loss={min(head_best_loss, fine_tune_best_loss):.6f}"
    )
    stage_histories.append(("fine_tune", FINE_TUNE_LEARNING_RATE, fine_tune_history))
    history = save_history(stage_histories, out_dir)
    return history, len(head_history.history["loss"])


def save_curves(history, out_dir, head_epochs):
    epochs = range(1, len(history["loss"]) + 1)
    plt.figure(figsize=(8, 5))
    plt.plot(epochs, history["loss"], label="train_loss")
    plt.plot(epochs, history["val_loss"], label="val_loss")
    plt.axvline(head_epochs + 0.5, color="gray", linestyle="--", label="fine-tuning starts")
    plt.xlabel("Epoch")
    plt.ylabel("Loss")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(out_dir / "loss_curve.png")
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.plot(epochs, history["accuracy"], label="train_accuracy")
    plt.plot(epochs, history["val_accuracy"], label="val_accuracy")
    plt.axvline(head_epochs + 0.5, color="gray", linestyle="--", label="fine-tuning starts")
    plt.xlabel("Epoch")
    plt.ylabel("Accuracy")
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

    example = wav_to_logmel_3ch(records[0]["path"])
    input_shape = example.shape
    print(f"[Info] Input shape: {input_shape}")

    fold_results = []
    y_true_all = []
    y_pred_all = []

    for fold_number, eval_fold_name in enumerate(FOLD_NAMES, start=1):
        tf.keras.utils.set_random_seed(SEED)
        print(f"\n========== Fold {fold_number}/4: Eval={eval_fold_name} ==========")
        eval_records = records_for_fold(records, eval_fold_name)
        candidate_records = [
            record for record in records if record["fold"] != eval_fold_name
        ]
        train_records, val_records = split_train_validation(
            candidate_records, val_size=VAL_SIZE, seed=SEED
        )
        print_split_summary(train_records, val_records, eval_records)

        train_paths, y_train = unpack_records(train_records, label_map)
        val_paths, y_val = unpack_records(val_records, label_map)
        eval_paths, y_eval = unpack_records(eval_records, label_map)

        weights = compute_class_weight(
            class_weight="balanced",
            classes=np.arange(n_classes),
            y=y_train,
        )
        class_weight = {index: weight for index, weight in enumerate(weights)}

        train_sequence = ResNetSequence(train_paths, y_train, BATCH_SIZE, training=True)
        val_sequence = ResNetSequence(val_paths, y_val, BATCH_SIZE)
        eval_sequence = ResNetSequence(eval_paths, y_eval, BATCH_SIZE)

        out_dir = RESULT_DIR / eval_fold_name
        out_dir.mkdir(parents=True, exist_ok=True)
        model, base_model = build_resnet_crnn_model(input_shape, n_classes)
        history, head_epochs = train_two_stage(
            model,
            base_model,
            train_sequence,
            val_sequence,
            class_weight,
            out_dir,
        )
        save_curves(history, out_dir, head_epochs)

        y_pred = np.argmax(model.predict(eval_sequence, verbose=1), axis=1)
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
        del model, base_model, history, train_sequence, val_sequence, eval_sequence
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
