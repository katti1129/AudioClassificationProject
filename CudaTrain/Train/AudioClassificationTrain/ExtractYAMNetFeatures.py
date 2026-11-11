"""Cache frozen YAMNet embeddings for accepted fold1-fold4 audio windows."""

import argparse
import hashlib
from pathlib import Path

import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = (SCRIPT_DIR / "../../data/Mixed_US8K_ESC50_dataset/04_silence_filtered").resolve()
FEATURES_DIR = SCRIPT_DIR / "YAMNetFeatures"
MODEL_HANDLE = "https://tfhub.dev/google/yamnet/1"
SAMPLE_RATE = 16000
EMBEDDING_DIM = 1024
CACHE_VERSION = 1


def audio_digest(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def pack_embeddings(embeddings):
    if not embeddings:
        raise ValueError("No embeddings to save.")
    lengths = []
    for embedding in embeddings:
        if (
            embedding.ndim != 2
            or embedding.shape[1] != EMBEDDING_DIM
            or embedding.shape[0] < 1
            or not np.isfinite(embedding).all()
        ):
            raise ValueError("Expected finite embeddings shaped (frames, 1024).")
        lengths.append(len(embedding))
    features = np.zeros((len(embeddings), max(lengths), EMBEDDING_DIM), dtype=np.float32)
    for index, embedding in enumerate(embeddings):
        features[index, : lengths[index]] = embedding
    return features, np.asarray(lengths, dtype=np.int32)


def save_fold_features(cache_path, records, embeddings, data_dir=DATA_DIR):
    features, lengths = pack_embeddings(embeddings)
    if len(records) != len(features):
        raise ValueError("Record and embedding counts do not match.")
    relative_paths = [record["path"].relative_to(data_dir).as_posix() for record in records]
    if len(set(relative_paths)) != len(records):
        raise ValueError("Duplicate audio paths in feature cache.")
    cache_path = Path(cache_path)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = cache_path.with_suffix(".tmp.npz")
    np.savez_compressed(
        temporary_path,
        cache_version=np.asarray(CACHE_VERSION),
        model_handle=np.asarray(MODEL_HANDLE),
        sample_rate=np.asarray(SAMPLE_RATE),
        features=features,
        lengths=lengths,
        relative_paths=np.asarray(relative_paths),
        labels=np.asarray([record["label"] for record in records]),
        source_ids=np.asarray([record["source_id"] for record in records]),
        folds=np.asarray([record["fold"] for record in records]),
        audio_sha256=np.asarray([audio_digest(record["path"]) for record in records]),
    )
    temporary_path.replace(cache_path)


def load_fold_features(cache_path, records, data_dir=DATA_DIR):
    """Validate provenance and return features aligned with the supplied records."""
    cache_path = Path(cache_path)
    if not cache_path.is_file():
        raise FileNotFoundError(
            f"{cache_path} is missing. Run ExtractYAMNetFeatures.py first."
        )
    with np.load(cache_path, allow_pickle=False) as archive:
        if (
            int(archive["cache_version"].item()) != CACHE_VERSION
            or str(archive["model_handle"].item()) != MODEL_HANDLE
            or int(archive["sample_rate"].item()) != SAMPLE_RATE
        ):
            raise ValueError(f"Incompatible YAMNet cache: {cache_path}")
        features = archive["features"]
        lengths = archive["lengths"]
        columns = {
            key: archive[key]
            for key in ("relative_paths", "labels", "source_ids", "folds", "audio_sha256")
        }
    count = len(records)
    if (
        features.ndim != 3
        or features.shape[0] != count
        or features.shape[2] != EMBEDDING_DIM
        or features.dtype != np.float32
        or lengths.shape != (count,)
        or not np.issubdtype(lengths.dtype, np.integer)
        or np.any(lengths < 1)
        or np.any(lengths > features.shape[1])
        or not np.isfinite(features).all()
        or any(column.shape != (count,) for column in columns.values())
    ):
        raise ValueError(f"Invalid or outdated feature cache: {cache_path}")
    cached_paths = columns["relative_paths"].tolist()
    index_by_path = {path: index for index, path in enumerate(cached_paths)}
    expected_paths = [record["path"].relative_to(data_dir).as_posix() for record in records]
    if len(index_by_path) != count or len(set(expected_paths)) != count or set(cached_paths) != set(expected_paths):
        raise ValueError(f"Cached audio paths differ from the manifest: {cache_path}")
    indexes = []
    for record, relative_path in zip(records, expected_paths):
        index = index_by_path[relative_path]
        if (
            str(columns["labels"][index]) != record["label"]
            or str(columns["source_ids"][index]) != record["source_id"]
            or str(columns["folds"][index]) != record["fold"]
            or str(columns["audio_sha256"][index]) != audio_digest(record["path"])
        ):
            raise ValueError(
                f"Stale cache for {relative_path}. Re-extract using --overwrite."
            )
        if np.any(features[index, int(lengths[index]) :] != 0):
            raise ValueError(f"Invalid nonzero padding for {relative_path}.")
        indexes.append(index)
    return features[indexes], lengths[indexes]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwrite", action="store_true", help="Re-extract existing fold caches.")
    parser.add_argument("--check-only", action="store_true", help="Validate caches without loading YAMNet.")
    args = parser.parse_args()
    if args.overwrite and args.check_only:
        parser.error("--overwrite and --check-only cannot be combined.")

    from fold_training_utils import FOLD_NAMES, load_accepted_records, records_for_fold

    records = load_accepted_records(DATA_DIR)
    yamnet = None
    print(f"[Dataset] {DATA_DIR}")
    print(f"[Features] {FEATURES_DIR}")
    for fold_name in FOLD_NAMES:
        selected = records_for_fold(records, fold_name)
        if not selected:
            raise RuntimeError(f"No accepted audio in {fold_name}.")
        cache_path = FEATURES_DIR / f"{fold_name}.npz"
        if args.check_only or (cache_path.exists() and not args.overwrite):
            features, _ = load_fold_features(cache_path, selected)
            print(f"[Valid cache] {fold_name}: {features.shape}")
            continue
        if yamnet is None:
            import librosa
            import tensorflow as tf
            import tensorflow_hub as hub
            from tqdm import tqdm

            for gpu in tf.config.list_physical_devices("GPU"):
                tf.config.experimental.set_memory_growth(gpu, True)
            print(f"[YAMNet] Loading frozen model: {MODEL_HANDLE}")
            yamnet = hub.load(MODEL_HANDLE)
        embeddings = []
        for record in tqdm(selected, desc=f"Extract {fold_name}"):
            waveform, _ = librosa.load(record["path"], sr=SAMPLE_RATE, mono=True)
            if waveform.size == 0 or not np.isfinite(waveform).all():
                raise ValueError(f"Invalid waveform: {record['path']}")
            _, embedding, _ = yamnet(tf.convert_to_tensor(waveform, dtype=tf.float32))
            embeddings.append(embedding.numpy().astype(np.float32))
        save_fold_features(cache_path, selected, embeddings)
        print(f"[Saved] {cache_path} ({len(selected)} files)")
    print("[Done] Frozen YAMNet features are ready for 4-fold training.")


if __name__ == "__main__":
    main()
