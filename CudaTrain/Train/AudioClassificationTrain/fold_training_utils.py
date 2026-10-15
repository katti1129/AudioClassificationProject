"""Shared, leak-free data splitting helpers for 4-fold audio training.
学習を始める前に実行する必要なし．
CRNN・AST・LSTM・ResNetで共通利用する、リーク防止付きデータ分割用の補助ファイル
"""

import csv
from pathlib import Path

import numpy as np
from sklearn.model_selection import train_test_split


FOLD_NAMES = tuple(f"fold{i}" for i in range(1, 5))


def load_accepted_records(data_dir: Path):
    """Load accepted fold1-fold4 windows from the dataset manifest."""
    manifest_path = data_dir / "manifest.csv"
    if not manifest_path.is_file():
        raise FileNotFoundError(
            f"manifest.csv が見つかりません: {manifest_path}\n"
            "元音源単位で分割するため、manifest.csv が必要です。"
        )

    records = []
    with manifest_path.open("r", encoding="utf-8-sig", newline="") as file:
        for row in csv.DictReader(file):
            fold_name = f"fold{row['fold']}"
            if fold_name not in FOLD_NAMES:
                continue
            if row["silence_status"] != "accepted":
                continue

            relative_path = Path(row["filtered_relative_path"])
            audio_path = data_dir / relative_path
            if relative_path.parts[0] == "_excluded":
                continue
            if not audio_path.is_file():
                raise FileNotFoundError(audio_path)

            records.append(
                {
                    "path": audio_path,
                    "label": row["class"],
                    "source_id": row["source_id"],
                    "fold": fold_name,
                }
            )

    if not records:
        raise RuntimeError(f"学習対象の音声がありません: {data_dir}")

    source_folds = {}
    for record in records:
        source_folds.setdefault(record["source_id"], set()).add(record["fold"])
    leaked_sources = {
        source_id: folds
        for source_id, folds in source_folds.items()
        if len(folds) != 1
    }
    if leaked_sources:
        sample = next(iter(leaked_sources.items()))
        raise RuntimeError(
            "同じsource_idが複数foldに含まれています: "
            f"{sample[0]} -> {sorted(sample[1])}"
        )

    return records


def build_label_map(records):
    classes = sorted({record["label"] for record in records})
    return {class_name: index for index, class_name in enumerate(classes)}


def records_for_fold(records, fold_name):
    return [record for record in records if record["fold"] == fold_name]


def split_train_validation(records, val_size=0.1, seed=42):
    """Split records by source_id while preserving source-level class ratios."""
    source_labels = {}
    for record in records:
        source_id = record["source_id"]
        label = record["label"]
        previous = source_labels.setdefault(source_id, label)
        if previous != label:
            raise RuntimeError(
                f"同じsource_idに複数クラスがあります: {source_id}"
            )

    source_ids = np.array(sorted(source_labels))
    labels = np.array([source_labels[source_id] for source_id in source_ids])
    train_sources, val_sources = train_test_split(
        source_ids,
        test_size=val_size,
        random_state=seed,
        stratify=labels,
    )
    train_source_set = set(train_sources)
    val_source_set = set(val_sources)

    if train_source_set & val_source_set:
        raise RuntimeError("TrainとValidationでsource_idが重複しています。")

    train_records = [
        record for record in records if record["source_id"] in train_source_set
    ]
    val_records = [
        record for record in records if record["source_id"] in val_source_set
    ]

    return train_records, val_records


def unpack_records(records, label_map):
    paths = [record["path"] for record in records]
    labels = np.array([label_map[record["label"]] for record in records])
    return paths, labels


def print_split_summary(train_records, val_records, eval_records):
    def source_count(selected):
        return len({record["source_id"] for record in selected})

    print(
        "[Split] "
        f"Train={len(train_records)} files/{source_count(train_records)} sources, "
        f"Val={len(val_records)} files/{source_count(val_records)} sources, "
        f"Eval={len(eval_records)} files/{source_count(eval_records)} sources"
    )

