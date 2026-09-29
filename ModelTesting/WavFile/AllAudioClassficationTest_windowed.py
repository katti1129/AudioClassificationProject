# -*- coding: utf-8 -*-
"""
シミュレーション音源に対するサイレン検出の時間・条件別分析用

指定フォルダ以下の全WAVファイルを対象に、
窓単位でサイレン分類を行い、結果をExcelとCSVへ保存する。

出力シート:
    Summary       : ファイル単位の評価結果
    WindowResults : 各時間窓の推論結果
    ConditionMean : ファイル名に記録された全条件の組み合わせ別の平均結果
    Errors        : 読み込みや推論に失敗したファイル
"""

import os

os.environ["TF_CPP_MIN_LOG_LEVEL"] = "2"

import re
from pathlib import Path
from typing import Any

import librosa
import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow.keras.models import load_model


@tf.keras.utils.register_keras_serializable()
class ReduceSumLayer(tf.keras.layers.Layer):
    def __init__(self, axis: int = 1, **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self.axis = axis

    def call(self, inputs):
        return tf.reduce_sum(inputs, axis=self.axis)

    def get_config(self) -> dict[str, Any]:
        config = super().get_config()
        config.update({"axis": self.axis})
        return config


# ============================================================
# Settings
# ============================================================

# distance、velocity、reflectionフォルダを含む親フォルダを指定
TARGET_DIR = Path(
    "/Users/katti/Desktop/Lab/AudioClassificationTesting/data/dataset"
)

MODEL_PATH = Path(
    "/Users/katti/Desktop/Lab/AudioClassificationTesting/code/best.keras"
)

OUTPUT_EXCEL = Path(
    "/Users/katti/Desktop/Lab/AudioClassificationTesting/results/"
    "simulation_evaluation_results_saisyuu.xlsx"
)

OUTPUT_CSV_DIR = Path(
    "/Users/katti/Desktop/Lab/AudioClassificationTesting/results/"
    "simulation_evaluation_results_saisyuu_csv"
)

CLASS_NAMES = ["other", "siren"]
SIREN_CLASS_NAME = "siren"

SAMPLE_RATE = 16000

# AIの推論条件
WINDOW_DURATION = 1.0
HOP_DURATION = 0.5

WIN_SAMPLES = int(SAMPLE_RATE * WINDOW_DURATION)
HOP_SAMPLES = int(SAMPLE_RATE * HOP_DURATION)

# メルスペクトログラム条件
N_MELS = 128
N_FFT = 1024
HOP_LENGTH = 512
FMIN = 20
FMAX = 8000

# siren確率がこの値以上なら検出成功
SIREN_THRESHOLD = 0.5

SUPPORTED_EXTENSIONS = {".wav"}

# ============================================================


def waveform_to_input(y: np.ndarray, sr: int) -> np.ndarray:
    """音声波形をモデル入力用のLog-Melスペクトログラムへ変換する。"""

    mel = librosa.feature.melspectrogram(
        y=y,
        sr=sr,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        n_mels=N_MELS,
        fmin=FMIN,
        fmax=FMAX,
        power=2.0,
    )

    logmel = librosa.power_to_db(mel, ref=np.max)

    # 学習時と同じ標準化処理を維持する
    std = float(logmel.std())
    logmel = (logmel - logmel.mean()) / (std + 1e-6)

    logmel = logmel.astype(np.float32)
    logmel = np.expand_dims(logmel, axis=-1)

    return logmel


def load_audio(path: Path) -> tuple[np.ndarray, int]:
    """音声を16 kHz・モノラルで読み込む。"""

    y, sr = librosa.load(
        path,
        sr=SAMPLE_RATE,
        mono=True,
    )

    if len(y) == 0:
        raise ValueError("音声データが空です。")

    # 1秒未満の場合はゼロ埋め
    if len(y) < WIN_SAMPLES:
        y = np.pad(
            y,
            (0, WIN_SAMPLES - len(y)),
            mode="constant",
        )

    return y, sr


def make_window_batch(
    y: np.ndarray,
    sr: int,
) -> tuple[np.ndarray, list[tuple[float, float]]]:
    """音声を重複窓へ分割して、モデル入力のバッチを作成する。"""

    windows: list[np.ndarray] = []
    time_ranges: list[tuple[float, float]] = []

    last_start = len(y) - WIN_SAMPLES

    for start in range(0, last_start + 1, HOP_SAMPLES):
        end = start + WIN_SAMPLES
        segment = y[start:end]

        if len(segment) < WIN_SAMPLES:
            segment = np.pad(
                segment,
                (0, WIN_SAMPLES - len(segment)),
                mode="constant",
            )

        windows.append(waveform_to_input(segment, sr))
        time_ranges.append((start / sr, end / sr))

    if not windows:
        raise ValueError("評価可能な時間窓を作成できませんでした。")

    input_data = np.stack(windows, axis=0)

    return input_data, time_ranges


# ファイル名の独立した「_タグ値」から条件を取得する。
# Vは従来の救急車速度、Rは百分率表記（R080=0.8）を維持する。
CONDITION_TAGS = {
    "CPA": ("CPA_m", "m", 1.0),
    "V": ("Velocity_kmh", "", 1.0),
    "PV": ("PedestrianVelocity_kmh", "", 1.0),
    "R": ("Reflection", "", 0.01),
    "OBS": ("ObstacleEnabled", "", 1.0),
    "N": ("ObstacleCount", "", 1.0),
    "SEED": ("ObstacleSeed", "", 1.0),
    "DIF": ("DiffractionEnabled", "", 1.0),
    "REF": ("ReflectionEnabled", "", 1.0),
    "OREF": ("ObstacleReflectionEnabled", "", 1.0),
    "SA": ("SourceAccelerationX_mps2", "", 1.0),
    "PA": ("PedestrianAccelerationX_mps2", "", 1.0),
    "SPL": ("ReferenceSPL_dB", "", 1.0),
    "SNR": ("SNR_dB", "", 1.0),
}
CONDITION_COLUMNS = [spec[0] for spec in CONDITION_TAGS.values()]


def parse_conditions(filename: str) -> dict[str, float | None]:
    """拡張条件タグを読む。省略した条件は不明(None)として保持する。

    例: ambulance_CPA20m_V060_PV-4_R080_OBS1_N24_SEED1_DIF1_REF1.wav
    符号・小数に対応。タグ間はアンダースコアで区切る。
    """
    tokens = Path(filename).stem.split("_")
    conditions = dict.fromkeys(CONDITION_COLUMNS)
    number = r"[+-]?(?:\d+(?:\.\d+)?|\.\d+)"
    flags = {"OBS", "DIF", "REF", "OREF"}
    for tag, (column, suffix, scale) in CONDITION_TAGS.items():
        matches = [re.fullmatch(tag + "(" + number + ")" + suffix,
                                token, re.IGNORECASE) for token in tokens]
        values = [float(match.group(1)) for match in matches if match]
        if len(values) > 1:
            raise ValueError(f"条件タグが重複しています: {tag}")
        if not values:
            continue
        value = values[0]
        if tag in flags and value not in (0, 1):
            raise ValueError(f"{tag}は0または1で指定してください")
        if tag in {"N", "SEED"} and (value < 0 or not value.is_integer()):
            raise ValueError(f"{tag}は0以上の整数で指定してください")
        if tag == "CPA" and value < 0:
            raise ValueError("CPAは0以上で指定してください")
        conditions[column] = value * scale
    return conditions


def get_experiment_type(path: Path) -> str:
    """親フォルダ名から実験種別を取得する。"""

    parent_name = path.parent.name.lower()

    mapping = {
        "distance": "CPA",
        "velocity": "Velocity",
        "reflection": "Reflection",
        "baseline": "Baseline",
    }

    return mapping.get(parent_name, path.parent.name)


def calculate_max_consecutive_misses(
    detected_flags: np.ndarray,
    hop_duration: float,
) -> tuple[int, float]:
    """
    最大連続未検出窓数と、未検出継続時間を求める。

    連続未検出時間は、連続窓がオーバーラップしていることを考慮して
    WINDOW_DURATION + (連続窓数 - 1) × HOP_DURATION
    とする。
    """

    max_count = 0
    current_count = 0

    for detected in detected_flags:
        if detected:
            current_count = 0
        else:
            current_count += 1
            max_count = max(max_count, current_count)

    if max_count == 0:
        max_duration = 0.0
    else:
        max_duration = (
            WINDOW_DURATION
            + (max_count - 1) * hop_duration
        )

    return max_count, max_duration


def evaluate_file(
    model: tf.keras.Model,
    audio_path: Path,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """1つの音声ファイルを評価する。"""

    y, sr = load_audio(audio_path)
    input_data, time_ranges = make_window_batch(y, sr)

    predictions = model.predict(
        input_data,
        verbose=0,
    )

    if predictions.ndim != 2:
        raise ValueError(
            f"予測値の次元が不正です: shape={predictions.shape}"
        )

    if predictions.shape[1] != len(CLASS_NAMES):
        raise ValueError(
            "モデル出力クラス数とCLASS_NAMESが一致しません。"
            f" model={predictions.shape[1]}, "
            f"CLASS_NAMES={len(CLASS_NAMES)}"
        )

    siren_index = CLASS_NAMES.index(SIREN_CLASS_NAME)

    siren_probs = predictions[:, siren_index]
    predicted_indices = np.argmax(predictions, axis=1)
    predicted_labels = [
        CLASS_NAMES[index]
        for index in predicted_indices
    ]

    # Recall算出用の検出結果
    # 全時間窓に救急車サイレンが含まれている前提
    detected_flags = siren_probs >= SIREN_THRESHOLD

    tp = int(np.sum(detected_flags))
    fn = int(len(detected_flags) - tp)
    recall = tp / (tp + fn) if (tp + fn) > 0 else np.nan

    mean_siren_prob = float(np.mean(siren_probs))
    min_siren_prob = float(np.min(siren_probs))
    max_siren_prob = float(np.max(siren_probs))
    std_siren_prob = float(np.std(siren_probs))

    max_prob_index = int(np.argmax(siren_probs))
    min_prob_index = int(np.argmin(siren_probs))

    # 初回検出
    detected_indices = np.flatnonzero(detected_flags)

    if len(detected_indices) > 0:
        first_detection_index = int(detected_indices[0])
        first_detection_time = time_ranges[first_detection_index][0]
    else:
        first_detection_time = np.nan

    max_miss_windows, max_miss_duration = (
        calculate_max_consecutive_misses(
            detected_flags,
            HOP_DURATION,
        )
    )

    conditions = parse_conditions(audio_path.name)
    experiment_type = get_experiment_type(audio_path)

    file_summary = {
        "ExperimentType": experiment_type,
        "FileName": audio_path.name,
        "RelativePath": str(audio_path.relative_to(TARGET_DIR)),
        **conditions,
        "AudioDuration_s": len(y) / sr,
        "WindowDuration_s": WINDOW_DURATION,
        "HopDuration_s": HOP_DURATION,
        "WindowCount": len(time_ranges),
        "TP": tp,
        "FN": fn,
        "Recall": recall,
        "Recall_percent": recall * 100,
        "MeanSirenProbability": mean_siren_prob,
        "MeanSirenProbability_percent": mean_siren_prob * 100,
        "MinSirenProbability": min_siren_prob,
        "MinSirenProbability_percent": min_siren_prob * 100,
        "MaxSirenProbability": max_siren_prob,
        "MaxSirenProbability_percent": max_siren_prob * 100,
        "StdSirenProbability": std_siren_prob,
        "FirstDetectionTime_s": first_detection_time,
        "MaxConsecutiveMissWindows": max_miss_windows,
        "MaxConsecutiveMissDuration_s": max_miss_duration,
        "MaxProbabilityWindowStart_s": time_ranges[max_prob_index][0],
        "MaxProbabilityWindowEnd_s": time_ranges[max_prob_index][1],
        "MinProbabilityWindowStart_s": time_ranges[min_prob_index][0],
        "MinProbabilityWindowEnd_s": time_ranges[min_prob_index][1],
        "FinalDecision": (
            SIREN_CLASS_NAME
            if mean_siren_prob >= SIREN_THRESHOLD
            else "other"
        ),
    }

    window_rows: list[dict[str, Any]] = []

    for window_number, (
        time_range,
        siren_probability,
        predicted_label,
        detected,
    ) in enumerate(
        zip(
            time_ranges,
            siren_probs,
            predicted_labels,
            detected_flags,
        ),
        start=1,
    ):
        start_time, end_time = time_range

        window_rows.append(
            {
                "ExperimentType": experiment_type,
                "FileName": audio_path.name,
                **conditions,
                "WindowNumber": window_number,
                "StartTime_s": start_time,
                "EndTime_s": end_time,
                "CenterTime_s": (start_time + end_time) / 2,
                "SirenProbability": float(siren_probability),
                "SirenProbability_percent": (
                    float(siren_probability) * 100
                ),
                "PredictedLabelByArgmax": predicted_label,
                "DetectedByThreshold": bool(detected),
                "Evaluation": "TP" if detected else "FN",
            }
        )

    return file_summary, window_rows


def make_condition_summary(
    summary_df: pd.DataFrame,
) -> pd.DataFrame:
    """実験条件ごとの平均値を作成する。"""

    result_frames: list[pd.DataFrame] = []

    # 全条件の組み合わせごとに集計し、異なる設定を混ぜない。
    for experiment_type in summary_df["ExperimentType"].unique():
        target = summary_df[
            summary_df["ExperimentType"] == experiment_type
        ].copy()

        if target.empty:
            continue

        grouped = (
            target.groupby(CONDITION_COLUMNS, dropna=False)
            .agg(
                FileCount=("FileName", "count"),
                TotalTP=("TP", "sum"),
                TotalFN=("FN", "sum"),
                MeanRecall_percent=("Recall_percent", "mean"),
                MeanSirenProbability_percent=(
                    "MeanSirenProbability_percent",
                    "mean",
                ),
                MeanMinSirenProbability_percent=(
                    "MinSirenProbability_percent",
                    "mean",
                ),
                MeanFirstDetectionTime_s=(
                    "FirstDetectionTime_s",
                    "mean",
                ),
                MaxMissDuration_s=(
                    "MaxConsecutiveMissDuration_s",
                    "max",
                ),
            )
            .reset_index()
        )

        # 全窓をまとめたMicro Recall
        grouped["MicroRecall_percent"] = (
            grouped["TotalTP"]
            / (grouped["TotalTP"] + grouped["TotalFN"])
            * 100
        )

        grouped.insert(0, "ExperimentType", experiment_type)

        result_frames.append(grouped)

    if not result_frames:
        return pd.DataFrame()

    return pd.concat(
        result_frames,
        ignore_index=True,
    )


def format_excel(
    writer: pd.ExcelWriter,
    dataframes: dict[str, pd.DataFrame],
) -> None:
    """Excelの列幅、フィルタ、固定行などを設定する。"""

    workbook = writer.book

    for sheet_name, dataframe in dataframes.items():
        worksheet = writer.sheets[sheet_name]

        worksheet.freeze_panes = "A2"
        worksheet.auto_filter.ref = worksheet.dimensions

        for column_cells in worksheet.columns:
            column_letter = column_cells[0].column_letter

            max_length = max(
                len(str(cell.value)) if cell.value is not None else 0
                for cell in column_cells
            )

            worksheet.column_dimensions[column_letter].width = min(
                max(max_length + 2, 10),
                40,
            )

        # 1行目を太字にする
        for cell in worksheet[1]:
            cell.font = cell.font.copy(bold=True)

    # Summaryの割合列を見やすくする
    if "Summary" in writer.sheets:
        worksheet = writer.sheets["Summary"]

        percent_columns = {
            "Recall_percent",
            "MeanSirenProbability_percent",
            "MinSirenProbability_percent",
            "MaxSirenProbability_percent",
        }

        for column_index, column_name in enumerate(
            dataframes["Summary"].columns,
            start=1,
        ):
            if column_name in percent_columns:
                for row_index in range(
                    2,
                    len(dataframes["Summary"]) + 2,
                ):
                    worksheet.cell(
                        row=row_index,
                        column=column_index,
                    ).number_format = "0.00"


def main() -> None:
    """全音源を評価し、ExcelとCSVへ保存する。"""

    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"モデルが見つかりません: {MODEL_PATH}"
        )

    if not TARGET_DIR.exists():
        raise FileNotFoundError(
            f"対象フォルダが見つかりません: {TARGET_DIR}"
        )

    audio_files = sorted(
        path
        for path in TARGET_DIR.rglob("*")
        if path.is_file()
        and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )

    if not audio_files:
        raise FileNotFoundError(
            f"WAVファイルが見つかりません: {TARGET_DIR}"
        )

    print(f"Loading model: {MODEL_PATH}")
    model = load_model(MODEL_PATH)
    print("Model loaded.")

    print(f"\nTarget directory : {TARGET_DIR}")
    print(f"Number of files  : {len(audio_files)}")
    print(f"Output Excel     : {OUTPUT_EXCEL}")
    print(f"Output CSV dir   : {OUTPUT_CSV_DIR}")

    summary_rows: list[dict[str, Any]] = []
    all_window_rows: list[dict[str, Any]] = []
    error_rows: list[dict[str, str]] = []

    for file_number, audio_path in enumerate(
        audio_files,
        start=1,
    ):
        print(
            f"\n[{file_number}/{len(audio_files)}] "
            f"{audio_path.relative_to(TARGET_DIR)}"
        )

        try:
            summary_row, window_rows = evaluate_file(
                model,
                audio_path,
            )

            summary_rows.append(summary_row)
            all_window_rows.extend(window_rows)

            print(
                f"  Recall: "
                f"{summary_row['Recall_percent']:.2f}%"
            )
            print(
                f"  Mean probability: "
                f"{summary_row['MeanSirenProbability_percent']:.2f}%"
            )
            print(
                f"  Max miss duration: "
                f"{summary_row['MaxConsecutiveMissDuration_s']:.2f} s"
            )

        except Exception as error:
            print(f"  Error: {error}")

            error_rows.append(
                {
                    "FileName": audio_path.name,
                    "FilePath": str(audio_path),
                    "Error": str(error),
                }
            )

    if not summary_rows:
        raise RuntimeError(
            "すべてのファイルで評価に失敗しました。"
        )

    summary_df = pd.DataFrame(summary_rows)
    window_df = pd.DataFrame(all_window_rows)
    errors_df = pd.DataFrame(error_rows)

    # 表示順を条件順に揃える
    summary_df = summary_df.sort_values(
        by=[
            "ExperimentType",
            "CPA_m",
            "Velocity_kmh",
            "Reflection",
            "FileName",
        ],
        na_position="last",
    ).reset_index(drop=True)

    window_df = window_df.sort_values(
        by=[
            "ExperimentType",
            "FileName",
            "WindowNumber",
        ]
    ).reset_index(drop=True)

    condition_df = make_condition_summary(summary_df)

    OUTPUT_EXCEL.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    excel_dataframes = {
        "Summary": summary_df,
        "WindowResults": window_df,
        "ConditionMean": condition_df,
        "Errors": errors_df,
    }

    with pd.ExcelWriter(
        OUTPUT_EXCEL,
        engine="openpyxl",
    ) as writer:
        for sheet_name, dataframe in excel_dataframes.items():
            dataframe.to_excel(
                writer,
                sheet_name=sheet_name,
                index=False,
            )

        format_excel(
            writer,
            excel_dataframes,
        )

    OUTPUT_CSV_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    for table_name, dataframe in excel_dataframes.items():
        csv_path = OUTPUT_CSV_DIR / f"{table_name}.csv"
        dataframe.to_csv(
            csv_path,
            index=False,
            encoding="utf-8-sig",
        )

    print("\n========================================")
    print("Evaluation completed.")
    print(f"Successful files: {len(summary_df)}")
    print(f"Failed files    : {len(errors_df)}")
    print(f"Excel saved to : {OUTPUT_EXCEL}")
    print(f"CSV saved to   : {OUTPUT_CSV_DIR}")
    print("========================================")


if __name__ == "__main__":
    main()
