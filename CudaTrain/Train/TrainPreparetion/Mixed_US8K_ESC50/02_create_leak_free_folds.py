"""元録音IDを分割単位として、抽出済み音声をリークなく5-foldへ分ける。"""

import argparse
import csv
import shutil
from collections import defaultdict
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
CUDA_TRAIN_DIR = SCRIPT_DIR.parents[2]
DATA_DIR = CUDA_TRAIN_DIR / "data"
OUTPUT_ROOT = DATA_DIR / "Mixed_US8K_ESC50_dataset"
INPUT_DIR = OUTPUT_ROOT / "01_extracted"
INPUT_MANIFEST = INPUT_DIR / "manifest.csv"
OUTPUT_DIR = OUTPUT_ROOT / "02_folds"
OUTPUT_MANIFEST = OUTPUT_DIR / "manifest.csv"

N_FOLDS = 5
WINDOW_SECONDS = 1.0
HOP_SECONDS = 0.5


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存の02_foldsを削除して作り直す",
    )
    return parser.parse_args()


def prepare_output(overwrite):
    if OUTPUT_DIR.exists() and any(OUTPUT_DIR.iterdir()):
        if not overwrite:
            raise FileExistsError(
                f"{OUTPUT_DIR} は空ではありません。作り直す場合は --overwrite を付けてください。"
            )
        if OUTPUT_DIR.resolve().parent != OUTPUT_ROOT.resolve():
            raise RuntimeError(f"安全でない削除対象です: {OUTPUT_DIR}")
        shutil.rmtree(OUTPUT_DIR)

    for fold in range(1, N_FOLDS + 1):
        for class_name in ("siren", "other"):
            (OUTPUT_DIR / f"fold{fold}" / class_name).mkdir(
                parents=True, exist_ok=True
            )


def read_manifest():
    if not INPUT_MANIFEST.is_file():
        raise FileNotFoundError(
            f"{INPUT_MANIFEST} がありません。先に01_extract_classes.pyを実行してください。"
        )
    with INPUT_MANIFEST.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def estimated_window_count(duration):
    duration = float(duration)
    if duration < WINDOW_SECONDS:
        return 0
    return int((duration - WINDOW_SECONDS) // HOP_SECONDS) + 1


def group_records(records):
    groups = defaultdict(list)
    for record in records:
        groups[record["source_id"]].append(record)

    for source_id, group in groups.items():
        datasets = {record["dataset"] for record in group}
        classes = {record["class"] for record in group}
        if len(datasets) != 1 or len(classes) != 1:
            raise ValueError(
                f"source_id={source_id} が複数dataset/classにまたがっています。"
            )
    return groups


def assign_folds(groups):
    assignments = {}

    # ESC-50はsrc_file単位でまとめ、otherのサブカテゴリ別窓数を均等化する。
    # 一部のsrc_fileは公式foldをまたぐため、リーク防止を優先して再割り当てする。
    esc_groups = []
    for source_id, group in groups.items():
        if group[0]["dataset"] != "ESC-50":
            continue

        category_windows = defaultdict(int)
        total_duration = 0.0
        for record in group:
            category_windows[record["subcategory"]] += estimated_window_count(
                record["duration_seconds"]
            )
            total_duration += float(record["duration_seconds"])

        official_folds = {int(record["original_fold"]) for record in group}
        preferred_fold = official_folds.pop() if len(official_folds) == 1 else None
        esc_groups.append(
            (
                source_id,
                dict(category_windows),
                sum(category_windows.values()),
                total_duration,
                preferred_fold,
            )
        )

    esc_groups.sort(key=lambda item: (-item[2], -item[3], item[0]))
    fold_category_windows = defaultdict(int)
    fold_other_windows = {fold: 0 for fold in range(1, N_FOLDS + 1)}
    fold_other_sources = {fold: 0 for fold in range(1, N_FOLDS + 1)}

    for (
        source_id,
        category_windows,
        total_windows,
        _,
        preferred_fold,
    ) in esc_groups:
        fold = min(
            range(1, N_FOLDS + 1),
            key=lambda candidate: (
                sum(
                    fold_category_windows[(candidate, category)]
                    for category in category_windows
                ),
                fold_other_windows[candidate],
                fold_other_sources[candidate],
                0 if candidate == preferred_fold else 1,
                candidate,
            ),
        )
        assignments[source_id] = fold
        for category, windows in category_windows.items():
            fold_category_windows[(fold, category)] += windows
        fold_other_windows[fold] += total_windows
        fold_other_sources[fold] += 1

    # UrbanSound8KはfsID単位の推定窓数が均等になるよう貪欲割り当てする。
    siren_groups = []
    for source_id, group in groups.items():
        if group[0]["dataset"] != "UrbanSound8K":
            continue
        window_count = sum(
            estimated_window_count(record["duration_seconds"])
            for record in group
        )
        duration = sum(float(record["duration_seconds"]) for record in group)
        siren_groups.append((source_id, window_count, duration, len(group)))

    siren_groups.sort(key=lambda item: (-item[1], -item[2], item[0]))
    fold_windows = {fold: 0 for fold in range(1, N_FOLDS + 1)}
    fold_durations = {fold: 0.0 for fold in range(1, N_FOLDS + 1)}
    fold_sources = {fold: 0 for fold in range(1, N_FOLDS + 1)}

    for source_id, window_count, duration, _ in siren_groups:
        fold = min(
            range(1, N_FOLDS + 1),
            key=lambda candidate: (
                fold_windows[candidate],
                fold_durations[candidate],
                fold_sources[candidate],
                candidate,
            ),
        )
        assignments[source_id] = fold
        fold_windows[fold] += window_count
        fold_durations[fold] += duration
        fold_sources[fold] += 1

    return assignments


def copy_to_folds(records, assignments):
    output_records = []
    seen_source_folds = defaultdict(set)

    for record in records:
        fold = assignments[record["source_id"]]
        source_path = INPUT_DIR / record["relative_path"]
        output_name = source_path.name
        relative_path = Path(f"fold{fold}") / record["class"] / output_name
        destination_path = OUTPUT_DIR / relative_path

        if not source_path.is_file():
            raise FileNotFoundError(source_path)
        if destination_path.exists():
            raise FileExistsError(f"出力ファイル名が重複しています: {destination_path}")

        shutil.copy2(source_path, destination_path)
        output_record = dict(record)
        output_record["fold"] = str(fold)
        output_record["fold_relative_path"] = relative_path.as_posix()
        output_records.append(output_record)
        seen_source_folds[record["source_id"]].add(fold)

    leaked = {
        source_id: folds
        for source_id, folds in seen_source_folds.items()
        if len(folds) != 1
    }
    if leaked:
        raise RuntimeError(f"複数foldへ入ったsource_idがあります: {leaked}")

    return output_records


def write_manifest(records):
    fieldnames = list(records[0].keys())
    with OUTPUT_MANIFEST.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    print("fold,class,files,source_ids,estimated_windows")
    for fold in range(1, N_FOLDS + 1):
        for class_name in ("siren", "other"):
            selected = [
                record
                for record in records
                if int(record["fold"]) == fold
                and record["class"] == class_name
            ]
            source_count = len({record["source_id"] for record in selected})
            windows = sum(
                estimated_window_count(record["duration_seconds"])
                for record in selected
            )
            print(f"{fold},{class_name},{len(selected)},{source_count},{windows}")


def main():
    args = parse_args()
    records = read_manifest()
    prepare_output(args.overwrite)

    groups = group_records(records)
    assignments = assign_folds(groups)
    output_records = copy_to_folds(records, assignments)
    output_records.sort(
        key=lambda row: (int(row["fold"]), row["class"], row["fold_relative_path"])
    )
    write_manifest(output_records)

    print(f"完了: {OUTPUT_DIR}")
    print_summary(output_records)
    print(f"manifest: {OUTPUT_MANIFEST}")


if __name__ == "__main__":
    main()
