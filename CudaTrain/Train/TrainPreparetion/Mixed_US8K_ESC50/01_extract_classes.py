"""UrbanSound8K/ESC-50からsirenとotherを抽出して16 kHz monoへ統一する。"""

import argparse
import csv
import shutil
from pathlib import Path

import librosa
import soundfile as sf


SCRIPT_DIR = Path(__file__).resolve().parent
CUDA_TRAIN_DIR = SCRIPT_DIR.parents[2]
DATA_DIR = CUDA_TRAIN_DIR / "data"
US8K_DIR = DATA_DIR / "UrbanSound8K"
ESC50_DIR = DATA_DIR / "ESC-50"
OUTPUT_ROOT = DATA_DIR / "Mixed_US8K_ESC50_dataset"
OUTPUT_DIR = OUTPUT_ROOT / "01_extracted"
MANIFEST_PATH = OUTPUT_DIR / "manifest.csv"

TARGET_SAMPLE_RATE = 16_000

# 街中または室内で発生し得る音をotherとして使用する。
# 必要に応じて、この集合だけを編集する。
ESC50_OTHER_CATEGORIES = {
    "dog",
    "crow",
    "rain",
    "crackling_fire",
    "chirping_birds",
    "wind",
    "thunderstorm",
    "crying_baby",
    "clapping",
    "coughing",
    "footsteps",
    "laughing",
    "door_wood_knock",
    "washing_machine",
    "vacuum_cleaner",
    "clock_alarm",
    "glass_breaking",
    "helicopter",
    "car_horn",
    "engine",
    "train",
    "airplane",
}

MANIFEST_FIELDS = [
    "dataset",
    "class",
    "subcategory",
    "source_id",
    "original_fold",
    "original_filename",
    "relative_path",
    "duration_seconds",
    "sample_rate",
]


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="既存の01_extractedを削除して作り直す",
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

    (OUTPUT_DIR / "siren").mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "other").mkdir(parents=True, exist_ok=True)


def read_csv(path):
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def convert_and_save(source_path, destination_path):
    audio, _ = librosa.load(source_path, sr=TARGET_SAMPLE_RATE, mono=True)
    sf.write(destination_path, audio, TARGET_SAMPLE_RATE, subtype="PCM_16")
    return len(audio) / TARGET_SAMPLE_RATE


def extract_urbansound8k(rows):
    records = []
    for row in rows:
        if row["class"] != "siren":
            continue

        original_name = row["slice_file_name"]
        source_path = (
            US8K_DIR / "audio" / f"fold{row['fold']}" / original_name
        )
        source_id = f"us8k:{row['fsID']}"
        output_name = f"us8k_fs{row['fsID']}_{original_name}"
        relative_path = Path("siren") / output_name
        destination_path = OUTPUT_DIR / relative_path

        if not source_path.is_file():
            raise FileNotFoundError(source_path)

        duration = convert_and_save(source_path, destination_path)
        records.append(
            {
                "dataset": "UrbanSound8K",
                "class": "siren",
                "subcategory": "siren",
                "source_id": source_id,
                "original_fold": row["fold"],
                "original_filename": original_name,
                "relative_path": relative_path.as_posix(),
                "duration_seconds": f"{duration:.6f}",
                "sample_rate": TARGET_SAMPLE_RATE,
            }
        )
    return records


def extract_esc50(rows):
    records = []
    for row in rows:
        if row["category"] not in ESC50_OTHER_CATEGORIES:
            continue

        original_name = row["filename"]
        source_path = ESC50_DIR / "audio" / original_name
        # 同じFreesound音源の別takeも同一グループとして扱う。
        source_id = f"esc50:{row['src_file']}"
        output_name = f"esc50_src{row['src_file']}_{original_name}"
        relative_path = Path("other") / output_name
        destination_path = OUTPUT_DIR / relative_path

        if not source_path.is_file():
            raise FileNotFoundError(source_path)

        duration = convert_and_save(source_path, destination_path)
        records.append(
            {
                "dataset": "ESC-50",
                "class": "other",
                "subcategory": row["category"],
                "source_id": source_id,
                "original_fold": row["fold"],
                "original_filename": original_name,
                "relative_path": relative_path.as_posix(),
                "duration_seconds": f"{duration:.6f}",
                "sample_rate": TARGET_SAMPLE_RATE,
            }
        )
    return records


def write_manifest(records):
    with MANIFEST_PATH.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        writer.writerows(records)


def main():
    args = parse_args()
    prepare_output(args.overwrite)

    us8k_rows = read_csv(US8K_DIR / "metadata" / "UrbanSound8K.csv")
    esc50_rows = read_csv(ESC50_DIR / "meta" / "esc50.csv")

    records = extract_urbansound8k(us8k_rows)
    records.extend(extract_esc50(esc50_rows))
    records.sort(key=lambda row: (row["class"], row["relative_path"]))
    write_manifest(records)

    counts = {
        class_name: sum(row["class"] == class_name for row in records)
        for class_name in ("siren", "other")
    }
    print(f"完了: {OUTPUT_DIR}")
    print(f"siren: {counts['siren']} files")
    print(f"other: {counts['other']} files")
    print(f"manifest: {MANIFEST_PATH}")


if __name__ == "__main__":
    main()
