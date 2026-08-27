"""1秒窓の音量を測定し、無音に近い窓を_excludedへ分ける。"""

import argparse
import csv
import shutil
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import soundfile as sf


SCRIPT_DIR = Path(__file__).resolve().parent
CUDA_TRAIN_DIR = SCRIPT_DIR.parents[2]
DATA_DIR = CUDA_TRAIN_DIR / "data"
OUTPUT_ROOT = DATA_DIR / "Mixed_US8K_ESC50_dataset"
INPUT_DIR = OUTPUT_ROOT / "03_windows_1s"
INPUT_MANIFEST = INPUT_DIR / "manifest.csv"
OUTPUT_DIR = OUTPUT_ROOT / "04_silence_filtered"
OUTPUT_MANIFEST = OUTPUT_DIR / "manifest.csv"

MIN_DBFS = -100.0
DEFAULT_RMS_THRESHOLD_DBFS = -50.0
DEFAULT_PEAK_THRESHOLD_DBFS = -35.0


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rms-threshold-dbfs",
        type=float,
        default=DEFAULT_RMS_THRESHOLD_DBFS,
        help="無音候補とする全体RMSの上限（既定: -50 dBFS）",
    )
    parser.add_argument(
        "--peak-threshold-dbfs",
        type=float,
        default=DEFAULT_PEAK_THRESHOLD_DBFS,
        help="無音候補とするピークの上限（既定: -35 dBFS）",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存の04_silence_filteredを削除して作り直す",
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
            (OUTPUT_DIR / "_excluded" / f"fold{fold}" / class_name).mkdir(
                parents=True, exist_ok=True
            )


def read_manifest():
    if not INPUT_MANIFEST.is_file():
        raise FileNotFoundError(
            f"{INPUT_MANIFEST} がありません。"
            "先に03_apply_sliding_window_1s.pyを実行してください。"
        )
    with INPUT_MANIFEST.open("r", encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def amplitude_to_dbfs(amplitude):
    if amplitude <= 0:
        return MIN_DBFS
    return max(MIN_DBFS, 20.0 * np.log10(amplitude))


def measure_levels(audio):
    samples = np.nan_to_num(np.asarray(audio, dtype=np.float64))
    if samples.size == 0:
        return MIN_DBFS, MIN_DBFS
    rms = np.sqrt(np.mean(np.square(samples)))
    peak = np.max(np.abs(samples))
    return amplitude_to_dbfs(rms), amplitude_to_dbfs(peak)


def separate_windows(records, rms_threshold, peak_threshold):
    output_records = []
    source_folds = defaultdict(set)

    for record in records:
        source_path = INPUT_DIR / record["window_relative_path"]
        if not source_path.is_file():
            raise FileNotFoundError(source_path)

        audio, _ = sf.read(source_path, dtype="float32", always_2d=False)
        rms_dbfs, peak_dbfs = measure_levels(audio)

        # 短い衝撃音を誤除外しにくくするため、RMSとPeakの両方が低い窓だけを除外する。
        is_silent = (
            rms_dbfs <= rms_threshold and peak_dbfs <= peak_threshold
        )
        fold = int(record["fold"])
        class_name = record["class"]
        source_folds[record["source_id"]].add(fold)

        if is_silent:
            relative_path = (
                Path("_excluded") / f"fold{fold}" / class_name / source_path.name
            )
            status = "excluded_silence"
        else:
            relative_path = Path(f"fold{fold}") / class_name / source_path.name
            status = "accepted"

        destination_path = OUTPUT_DIR / relative_path
        if destination_path.exists():
            raise FileExistsError(f"出力ファイル名が重複しています: {destination_path}")
        shutil.copy2(source_path, destination_path)

        output_record = dict(record)
        output_record["rms_dbfs"] = f"{rms_dbfs:.3f}"
        output_record["peak_dbfs"] = f"{peak_dbfs:.3f}"
        output_record["silence_status"] = status
        output_record["filtered_relative_path"] = relative_path.as_posix()
        output_records.append(output_record)

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
        raise RuntimeError("判定対象の窓がありません。")
    fieldnames = list(records[0].keys())
    with OUTPUT_MANIFEST.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(records)


def print_summary(records):
    counts = Counter(
        (int(row["fold"]), row["class"], row["silence_status"])
        for row in records
    )
    print("fold,class,accepted,excluded_silence")
    for fold in range(1, 6):
        for class_name in ("siren", "other"):
            print(
                f"{fold},{class_name},"
                f"{counts[(fold, class_name, 'accepted')]},"
                f"{counts[(fold, class_name, 'excluded_silence')]}"
            )


def main():
    args = parse_args()
    if args.rms_threshold_dbfs > 0 or args.peak_threshold_dbfs > 0:
        raise ValueError("dBFS閾値は0以下にしてください。")

    records = read_manifest()
    prepare_output(args.overwrite)
    output_records = separate_windows(
        records,
        rms_threshold=args.rms_threshold_dbfs,
        peak_threshold=args.peak_threshold_dbfs,
    )
    output_records.sort(
        key=lambda row: (
            int(row["fold"]),
            row["class"],
            row["filtered_relative_path"],
        )
    )
    write_manifest(output_records)

    print(f"完了: {OUTPUT_DIR}")
    print(
        f"判定条件: RMS <= {args.rms_threshold_dbfs:.1f} dBFS かつ "
        f"Peak <= {args.peak_threshold_dbfs:.1f} dBFS"
    )
    print_summary(output_records)
    print(f"manifest: {OUTPUT_MANIFEST}")


if __name__ == "__main__":
    main()
