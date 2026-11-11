# -*- coding: utf-8 -*-
"""Evaluate tagged positive WAVs and plot distance/speed/time heatmaps.

Reuses AllAudioClassficationTest_windowed.py for all audio preprocessing and
window inference. No training or simulation files are modified. See README.
No arguments: choose input folder and model with dialogs. CLI: --help.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from datetime import datetime
from pathlib import Path
from uuid import uuid4

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


EVALUATOR_PATH = Path(__file__).with_name("AllAudioClassficationTest_windowed.py")


def load_evaluator():
    """Load the existing evaluator without running its main() or Mac paths."""
    spec = importlib.util.spec_from_file_location("heatmap_window_evaluator", EVALUATOR_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProbabilityModel:
    """Validate the existing evaluator's two-class probability assumption."""

    def __init__(self, model):
        self.model = model

    def predict(self, inputs, **kwargs):
        p = np.asarray(self.model.predict(inputs, **kwargs))
        if p.shape != (len(inputs), 2):
            raise ValueError(f"Expected (windows, 2) probabilities; got {p.shape}")
        if not np.all(np.isfinite(p)) or np.any(p < 0) or np.any(p > 1):
            raise ValueError("Model outputs must be finite probabilities in [0,1], not logits.")
        if not np.allclose(p.sum(axis=1), 1, atol=1e-4, rtol=0):
            raise ValueError("The two model probabilities must sum to 1. Check model/output semantics.")
        return p


def scan_inputs(root, evaluator):
    """Read filename tags; require CPA/V. Group by parent + other tags, except seed.

    Seeds are retained in rows but pooled as replicate files, not separate plots.
    Different immediate directory paths are never silently pooled.
    """
    candidates, errors, groups = [], [], {}
    other_columns = [c for c in evaluator.CONDITION_COLUMNS
                     if c not in {"CPA_m", "Velocity_kmh", "ObstacleSeed"}]
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() != ".wav":
            continue
        relative = path.relative_to(root).as_posix()
        try:
            conditions = evaluator.parse_conditions(path.name)
            if conditions["CPA_m"] is None or conditions["Velocity_kmh"] is None:
                raise ValueError("Missing CPA/V tags, e.g. ambulance_CPA20m_V060_R080.wav")
            if any(v is not None and not np.isfinite(v) for v in conditions.values()):
                raise ValueError("Nonfinite filename condition")
            group_conditions = {c: conditions[c] for c in other_columns}
            group_conditions["RelativeParent"] = path.parent.relative_to(root).as_posix()
            key = json.dumps(group_conditions, sort_keys=True, ensure_ascii=False)
            if key not in groups:
                groups[key] = f"G{len(groups) + 1:03d}"
            candidates.append({"path": path, "relative": relative, "conditions": conditions,
                               "group": groups[key], "group_conditions": group_conditions})
        except Exception as exc:
            errors.append({"RelativePath": relative, "Stage": "filename", "Error": str(exc)})
    return candidates, errors


def select_windows(window_rows, eval_start=None, eval_end=None, cpa_time=None):
    """Select complete windows within reception-time bounds [s], no relabeling.

    CPA-relative x uses window center minus the user-supplied geometric CPA time.
    Unobserved tail fragments and per-window features remain as in the evaluator.
    """
    frame = pd.DataFrame(window_rows)
    if eval_start is not None:
        frame = frame[frame.StartTime_s >= eval_start - 1e-9]
    if eval_end is not None:
        frame = frame[frame.EndTime_s <= eval_end + 1e-9]
    if frame.empty:
        raise ValueError("No complete inference windows inside the selected evaluation interval")
    frame = frame.copy()
    frame["HeatmapTime_s"] = (frame.CenterTime_s - (cpa_time or 0.0)).round(9)
    return frame


def summarize_windows(frame, metadata):
    """Recalculate file recall ONLY over selected all-positive windows."""
    flags = frame.DetectedByThreshold.to_numpy(dtype=bool)
    probabilities = frame.SirenProbability.to_numpy(dtype=float)
    tp = int(flags.sum())
    return {**metadata, "WindowCount": len(frame), "TP": tp, "FN": len(frame) - tp,
            "Recall_percent": 100 * tp / len(frame),
            "MeanSirenProbability_percent": float(probabilities.mean() * 100),
            "EvaluatedFirstWindowStart_s": float(frame.StartTime_s.min()),
            "EvaluatedLastWindowEnd_s": float(frame.EndTime_s.max()),
            "FirstDetectionWindowStart_s": float(frame.loc[flags, "StartTime_s"].iloc[0]) if flags.any() else np.nan,
            "FirstDetectionAvailableAt_s": float(frame.loc[flags, "EndTime_s"].iloc[0]) if flags.any() else np.nan}


def aggregate_results(summary, windows):
    """Return distance-speed macro/micro recall and distance-fixed time tables.

    Macro: mean file recall. Micro: pooled TP/(TP+FN). Time detection rate:
    fraction of positive files detected at each aligned window center; n=1
    produces 0/100, not an independently estimated detection probability.
    """
    by = ["GroupID", "CPA_m", "Velocity_kmh"]
    cells = summary.groupby(by, dropna=False, sort=True).agg(
        FileCount=("RelativePath", "nunique"), TotalTP=("TP", "sum"), TotalFN=("FN", "sum"),
        MacroRecall_percent=("Recall_percent", "mean"),
        MeanSirenProbability_percent=("MeanSirenProbability_percent", "mean"),
    ).reset_index()
    cells["MicroRecall_percent"] = 100 * cells.TotalTP / (cells.TotalTP + cells.TotalFN)
    time = windows.groupby(by + ["HeatmapTime_s"], dropna=False, sort=True).agg(
        FileCount=("RelativePath", "nunique"),
        DetectionRate=("DetectedByThreshold", "mean"),
        MeanSirenProbability=("SirenProbability", "mean"),
    ).reset_index()
    time["DetectionRate_percent"] = time.pop("DetectionRate") * 100
    time["MeanSirenProbability_percent"] = time.pop("MeanSirenProbability") * 100
    return cells, time


def draw_heatmap(values, counts, filename, title, xlabel, color_label):
    """Save a categorical-grid heatmap with a common 0..100 scale; NaN is gray."""
    nrows, ncols = values.shape
    width = min(24, max(7, .55 * ncols + 3))
    height = min(20, max(4, .55 * nrows + 2))
    fig, ax = plt.subplots(figsize=(width, height), layout="constrained")
    cmap = plt.get_cmap("viridis").copy()
    cmap.set_bad("#dddddd")
    im = ax.imshow(np.ma.masked_invalid(values.to_numpy(dtype=float)), aspect="auto",
                   interpolation="nearest", vmin=0, vmax=100, cmap=cmap, origin="lower")
    stride = max(1, int(np.ceil(ncols / 24)))
    xticks = np.arange(0, ncols, stride)
    ax.set_xticks(xticks, [f"{float(values.columns[i]):g}" for i in xticks], rotation=45, ha="right")
    ystride = max(1, int(np.ceil(nrows / 30)))
    yticks = np.arange(0, nrows, ystride)
    ax.set_yticks(yticks, [f"{float(values.index[i]):g}" for i in yticks])
    ax.set(xlabel=xlabel, ylabel="Source velocity [km/h]", title=title)
    fig.colorbar(im, ax=ax, label=color_label)
    if nrows <= 20 and ncols <= 24:
        for row in range(nrows):
            for col in range(ncols):
                value = values.iloc[row, col]
                label = "N/A" if pd.isna(value) else f"{value:.1f}\nn={int(counts.iloc[row, col])}"
                ax.text(col, row, label, ha="center", va="center", fontsize=8,
                        color="black" if pd.isna(value) or value >= 55 else "white")
    fig.savefig(filename, dpi=160)
    plt.close(fig)


def save_heatmaps(summary, windows, output, cpa_time=None):
    """Export all matrix CSVs and PNGs, splitting non-axis conditions into groups."""
    cells, time = aggregate_results(summary, windows)
    cells.to_csv(output / "DistanceSpeedResults.csv", index=False, encoding="utf-8-sig")
    time.to_csv(output / "TimeResults.csv", index=False, encoding="utf-8-sig")
    for group_id, group_cells in cells.groupby("GroupID", sort=True):
        directory = output / "heatmaps" / group_id
        directory.mkdir(parents=True, exist_ok=True)
        distances = sorted(group_cells.CPA_m.unique())
        speeds = sorted(group_cells.Velocity_kmh.unique())
        count = group_cells.pivot(index="Velocity_kmh", columns="CPA_m", values="FileCount").reindex(index=speeds, columns=distances)
        count.to_csv(directory / "distance_speed_file_counts.csv", encoding="utf-8-sig")
        for metric, name in [("MacroRecall_percent", "macro_recall"), ("MicroRecall_percent", "micro_recall")]:
            matrix = group_cells.pivot(index="Velocity_kmh", columns="CPA_m", values=metric).reindex(index=speeds, columns=distances)
            stem = directory / f"distance_speed_{name}"
            matrix.to_csv(stem.with_suffix(".csv"), encoding="utf-8-sig")
            draw_heatmap(matrix, count, stem.with_suffix(".png"),
                         f"{group_id}: {name.replace('_', ' ')} (all evaluated windows positive)",
                         "CPA distance [m] (filename tag)", "Recall [%]")
        group_time = time[time.GroupID == group_id]
        for distance, subset in group_time.groupby("CPA_m", sort=True):
            times = sorted(subset.HeatmapTime_s.unique())
            count = subset.pivot(index="Velocity_kmh", columns="HeatmapTime_s", values="FileCount").reindex(index=speeds, columns=times)
            prefix = f"CPA{distance:g}m".replace(".", "p")
            count.to_csv(directory / f"{prefix}_time_file_counts.csv", encoding="utf-8-sig")
            for metric, name, color in [
                ("DetectionRate_percent", "detection_rate", "Detection rate [%]"),
                ("MeanSirenProbability_percent", "mean_probability", "Mean siren output [%]"),
            ]:
                matrix = subset.pivot(index="Velocity_kmh", columns="HeatmapTime_s", values=metric).reindex(index=speeds, columns=times)
                stem = directory / f"{prefix}_time_{name}"
                matrix.to_csv(stem.with_suffix(".csv"), encoding="utf-8-sig")
                xlabel = "Reception window center [s]" if cpa_time is None else f"Window center minus geometric CPA ({cpa_time:g} s) [s]"
                draw_heatmap(matrix, count, stem.with_suffix(".png"),
                             f"{group_id}: CPA {distance:g} m / {name.replace('_', ' ')}", xlabel, color)
    return cells, time


def file_hash(path):
    """Stream SHA256 for reproducible model/code identification."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_evaluation(args, model=None, evaluator=None):
    """Evaluate tagged files; save successful rows, failures, settings and plots.

    Optional model/evaluator injection is for tests, not a replacement inference
    implementation. Output directory is always unique; existing runs stay intact.
    """
    root = Path(args.input_dir).expanduser().resolve()
    if not root.is_dir():
        raise ValueError(f"Input folder not found: {root}")
    if not args.assume_positive:
        raise ValueError("Confirm positive-only evaluation using --assume-positive. Negative files are not supported.")
    if not np.isfinite(args.threshold) or not 0 <= args.threshold <= 1:
        raise ValueError("threshold must be in [0,1]")
    for value in (args.eval_start, args.eval_end, args.cpa_time):
        if value is not None and (not np.isfinite(value) or value < 0):
            raise ValueError("Time settings must be finite, nonnegative reception times [s]")
    if args.eval_start is not None and args.eval_end is not None and args.eval_end <= args.eval_start:
        raise ValueError("eval-end must exceed eval-start")
    base = evaluator if evaluator is not None else load_evaluator()
    base.TARGET_DIR = root
    base.SIREN_THRESHOLD = args.threshold
    base.CLASS_NAMES = args.class_order.split(",")
    candidates, errors = scan_inputs(root, base)
    parent = Path(args.output_dir).expanduser().resolve() if args.output_dir else root.parent / "AI_heatmap_results"
    output = parent / (datetime.now().strftime("evaluation_%Y%m%d_%H%M%S_") + uuid4().hex[:8])
    output.mkdir(parents=True, exist_ok=False)
    errors_frame = lambda: pd.DataFrame(errors, columns=["RelativePath", "Stage", "Error"])
    errors_frame().to_csv(output / "Errors.csv", index=False, encoding="utf-8-sig")
    if not candidates:
        raise ValueError(f"No WAV with valid CPA/V tags. See {output / 'Errors.csv'}")
    model_path = Path(args.model).expanduser().resolve() if args.model else None
    if model is None:
        if model_path is None or not model_path.is_file():
            raise ValueError(f"Select an existing Keras model file: {model_path}")
        model = base.load_model(model_path, compile=False)
    model = ProbabilityModel(model)
    groups = {item["group"]: item["group_conditions"] for item in candidates}
    settings = {"input_dir": str(root), "model": str(model_path),
                "model_sha256": file_hash(model_path) if model_path and model_path.is_file() else None,
                "injected_test_model": model_path is None,
                "evaluator_sha256": file_hash(EVALUATOR_PATH), "script_sha256": file_hash(Path(__file__)),
                "threshold": args.threshold, "class_order": base.CLASS_NAMES,
                "sample_rate": base.SAMPLE_RATE, "window_sec": base.WINDOW_DURATION,
                "hop_sec": base.HOP_DURATION, "n_mels": base.N_MELS, "n_fft": base.N_FFT,
                "stft_hop": base.HOP_LENGTH, "fmin": base.FMIN, "fmax": base.FMAX,
                "preprocessing": "existing per-window max-reference log-mel and mean/std normalization",
                "eval_start_sec": args.eval_start, "eval_end_sec": args.eval_end,
                "geometric_cpa_time_sec": args.cpa_time, "all_evaluated_windows_assumed_positive": True,
                "grouping": "relative parent + other condition tags; obstacle seeds pooled as replicates",
                "groups": groups}
    (output / "settings.json").write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    summaries, window_frames, aborted = [], [], False
    try:
        for number, item in enumerate(candidates, 1):
            print(f"[{number}/{len(candidates)}] {item['relative']}", flush=True)
            try:
                original, rows = base.evaluate_file(model, item["path"])
                frame = select_windows(rows, args.eval_start, args.eval_end, args.cpa_time)
                frame["RelativePath"] = item["relative"]
                frame["GroupID"] = item["group"]
                metadata = {"GroupID": item["group"], "RelativePath": item["relative"],
                            "FileName": item["path"].name, **item["conditions"],
                            "WindowDuration_s": base.WINDOW_DURATION, "HopDuration_s": base.HOP_DURATION,
                            "LoadedDuration_s": original["AudioDuration_s"],
                            "SourceWavSHA256": file_hash(item["path"])}
                summaries.append(summarize_windows(frame, metadata))
                window_frames.append(frame)
            except Exception as exc:
                errors.append({"RelativePath": item["relative"], "Stage": "inference", "Error": str(exc)})
                print(f"  ERROR: {exc}", flush=True)
    except KeyboardInterrupt:
        aborted = True
        print("Interrupted: saving completed files only.", flush=True)
    summary = pd.DataFrame(summaries)
    windows = pd.concat(window_frames, ignore_index=True) if window_frames else pd.DataFrame()
    summary.to_csv(output / "Summary.csv", index=False, encoding="utf-8-sig")
    windows.to_csv(output / "WindowResults.csv", index=False, encoding="utf-8-sig")
    errors_frame().to_csv(output / "Errors.csv", index=False, encoding="utf-8-sig")
    completion = {"candidate_files": len(candidates), "successful_files": len(summary),
                  "error_records": len(errors), "interrupted": aborted,
                  "not_processed_candidates": len(candidates) - len(summary) - sum(e["Stage"] == "inference" for e in errors),
                  "heatmaps_created": False}
    status_path = output / "completion.json"
    status_path.write_text(json.dumps(completion, indent=2), encoding="utf-8")
    if summary.empty:
        raise RuntimeError(f"No successful evaluations. See {output / 'Errors.csv'}")
    save_heatmaps(summary, windows, output, args.cpa_time)
    completion["heatmaps_created"] = True
    status_path.write_text(json.dumps(completion, indent=2), encoding="utf-8")
    print(f"Saved: {output}\nSuccess={len(summary)}, errors={len(errors)}, interrupted={aborted}", flush=True)
    return output


def make_parser():
    """Expose paths, inference threshold, positive interval and optional CPA time."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", help="Folder recursively containing tagged positive WAVs")
    parser.add_argument("--model", help="Trained .keras/.h5 model; class order must match training")
    parser.add_argument("--output-dir", help="Output parent; default is AI_heatmap_results next to input folder")
    parser.add_argument("--threshold", type=float, default=.5)
    parser.add_argument("--class-order", choices=["other,siren", "siren,other"], default="other,siren")
    parser.add_argument("--cpa-time", type=float, help="Common geometric CPA time [s]; omitted = absolute reception time")
    parser.add_argument("--eval-start", type=float, help="Only evaluate complete windows starting at/after this time [s]")
    parser.add_argument("--eval-end", type=float, help="Only evaluate complete windows ending at/before this time [s]")
    parser.add_argument("--assume-positive", action="store_true", help="Confirm all selected windows contain siren; not for negatives")
    return parser


def choose_paths(args):
    """Interactive path selection when no CLI paths are provided; no inferred model."""
    import tkinter as tk
    from tkinter import filedialog, messagebox, simpledialog
    root = tk.Tk()
    root.withdraw()
    try:
        args.input_dir = filedialog.askdirectory(title="条件名付きWAVのフォルダを選択")
        if not args.input_dir:
            return None
        args.model = filedialog.askopenfilename(title="学習済みAIモデルを選択", filetypes=[("Keras model", "*.keras *.h5"), ("All files", "*.*")])
        if not args.model:
            return None
        args.assume_positive = messagebox.askyesno("評価の前提", "選択した評価区間の全窓を『サイレンあり』としてRecallを計算します。\n背景音のみ・無音区間を含む場合は区間指定が必要です。\n\nこの前提で評価しますか？")
        if not args.assume_positive:
            return None
        if not messagebox.askyesno("クラス順の確認", "モデル出力のクラス順は [other, siren] ですか？\n異なる場合はキャンセルし、--class-orderを指定してください。"):
            return None
        value = simpledialog.askstring("時間軸", "CPA基準の図にする場合は、全ファイル共通のCPA時刻[s]を入力。\n空欄なら録音開始基準。例: 4", initialvalue="")
        if value is None:
            return None
        if value.strip():
            args.cpa_time = float(value)
        interval = simpledialog.askstring("評価区間", "全長なら空欄。サイレンがある共通区間だけ評価する場合は開始,終了[s]を入力。\n例: 1,8（区間内に完全に収まる1秒窓を使用）", initialvalue="")
        if interval is None:
            return None
        if interval.strip():
            args.eval_start, args.eval_end = map(float, interval.split(","))
        return args
    finally:
        root.destroy()


def main():
    """CLI/dialog entry point; processing errors are not reported as successful runs."""
    parser = make_parser()
    args = parser.parse_args()
    if not args.input_dir and not args.model:
        args = choose_paths(args)
        if args is None:
            return
    if not args.input_dir or not args.model:
        parser.error("Specify both --input-dir and --model, or neither to open dialogs.")
    run_evaluation(args)


if __name__ == "__main__":
    main()
