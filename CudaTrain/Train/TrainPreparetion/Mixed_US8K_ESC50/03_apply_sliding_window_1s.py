"""5-fold音声へ窓幅1.0秒・移動幅0.5秒のスライディングウィンドウを適用する。"""

import argparse
import csv
import shutil
from collections import Counter, defaultdict
from pathlib import Path

import soundfile as sf


SCRIPT_DIR = Path(__file__).resolve().parent
CUDA_TRAIN_DIR = SCRIPT_DIR.parents[2]
DATA_DIR = CUDA_TRAIN_DIR / "data"
OUTPUT_ROOT = DATA_DIR / "Mixed_US8K_ESC50_dataset"
INPUT_DIR = OUTPUT_ROOT / "02_folds"
INPUT_MANIFEST = INPUT_DIR / "manifest.csv"
OUTPUT_DIR = OUTPUT_ROOT / "03_windows_1s"
OUTPUT_MANIFEST = OUTPUT_DIR / "manifest.csv"

SAMPLE_RATE = 16_000
WINDOW_SECONDS = 1.0
HOP_SECONDS = 0.5
WINDOW_SAMPLES = int(SAMPLE_RATE * WINDOW_SECONDS)
HOP_SAMPLES = int(SAMPLE_RATE * HOP_SECONDS)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存の03_windows_1sを削除して作り直す",
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

    for fold in range(1, 6):
        for class_name in ("siren", "other"):
            (OUTPUT_DIR / f"fold{fold}" / class_name).mkdir(
                parents=True, exist_ok=True
            )


def read_manifest():
    if not INPUT_MANIFEST.is_file():
        raise FileNotFoundError(
            f"{INPUT_MANIFEST} がありません。"
            "先に02_create_leak_free_folds.pyを実行してください。"
        )
    with INPUT_MANIFEST.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def create_windows(records):
    output_records = []
    source_folds = defaultdict(set)

    for record in records:
        source_path = INPUT_DIR / record["fold_relative_path"]
        if not source_path.is_file():
            raise FileNotFoundError(source_path)

        audio, sample_rate = sf.read(source_path, dtype="float32", always_2d=False)
        if sample_rate != SAMPLE_RATE:
            raise ValueError(
                f"想定外のサンプリングレートです: {source_path} ({sample_rate} Hz)"
            )
        if getattr(audio, "ndim", 1) != 1:
            raise ValueError(f"モノラルではありません: {source_path}")

        fold = int(record["fold"])
        source_folds[record["source_id"]].add(fold)
        start = 0
        window_index = 0

        while start + WINDOW_SAMPLES <= len(audio):
            window = audio[start : start + WINDOW_SAMPLES]
            output_name = f"{source_path.stem}__win{window_index:04d}.wav"
            relative_path = Path(f"fold{fold}") / record["class"] / output_name
            destination_path = OUTPUT_DIR / relative_path

            if destination_path.exists():
                raise FileExistsError(
                    f"出力ファイル名が重複しています: {destination_path}"
                )

            sf.write(destination_path, window, SAMPLE_RATE, subtype="PCM_16")

            output_record = dict(record)
            output_record["parent_fold_relative_path"] = record[
                "fold_relative_path"
            ]
            output_record["window_index"] = str(window_index)
            output_record["window_start_seconds"] = f"{start / SAMPLE_RATE:.3f}"
            output_record["window_end_seconds"] = (
                f"{(start + WINDOW_SAMPLES) / SAMPLE_RATE:.3f}"
            )
            output_record["window_relative_path"] = relative_path.as_posix()
            output_records.append(output_record)

            start += HOP_SAMPLES
            window_index += 1

    leaked = {
        source_id: folds
        for source_id, folds in source_folds.items()
        if len(folds) != 1
    }
    if leaked:
        raise RuntimeError(f"複数foldへ入ったsource_idがあります: {leaked}")

    return output_records


def write_manifest(records):
    if not records:
        raise RuntimeError("生成された窓がありません。")
    fieldnames = list(records[0].keys())
    with OUTPUT_MANIFEST.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter((int(row["fold"]), row["class"]) for row in records)
    print("fold,class,windows")
    for fold in range(1, 6):
        for class_name in ("siren", "other"):
            print(f"{fold},{class_name},{counts[(fold, class_name)]}")


def main():
    args = parse_args()
    records = read_manifest()
    prepare_output(args.overwrite)

    output_records = create_windows(records)
    output_records.sort(
        key=lambda row: (
            int(row["fold"]),
            row["class"],
            row["window_relative_path"],
        )
    )
    write_manifest(output_records)

    print(f"完了: {OUTPUT_DIR}")
    print_summary(output_records)
    print(f"manifest: {OUTPUT_MANIFEST}")


if __name__ == "__main__":
    main()
