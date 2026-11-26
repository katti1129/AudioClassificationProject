"""Configuration and trial validation. No audio dependencies."""
import csv
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KEYS = {"w": "north", "d": "east", "s": "south", "a": "west"}
ROUTES = {"west": ("parent", 0), "south": ("parent", 1),
          "north": ("child", 0), "east": ("child", 1)}


def config(path=None):
    data = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    if path:
        data.update(json.loads(Path(path).read_text(encoding="utf-8")))
    for name in ("sample_rate", "min_above_ms", "onset_timeout_s",
                 "response_timeout_s", "silence_s", "settle_s"):
        if not math.isfinite(float(data[name])) or data[name] <= 0:
            raise ValueError(f"{name} must be positive")
    if not 0 < data["gain"] <= 1:
        raise ValueError("gain must be in (0, 1]")
    if not -120 < data["threshold_dbfs"] < 0:
        raise ValueError("threshold_dbfs must be between -120 and 0")
    if not math.isfinite(float(data["input_time_correction_ms"])):
        raise ValueError("invalid input time correction")
    return data


def sound_path(name):
    base = (ROOT / "sounds").resolve()
    path = (base / name).resolve()
    if not path.is_relative_to(base) or path.suffix.lower() != ".wav":
        raise ValueError("Only WAV files inside sounds/ are allowed")
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_trials(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError("Empty trial list")
    seen = set()
    for row in rows:
        if not row.get("trial_id") or row["trial_id"] in seen:
            raise ValueError("trial_id must be unique and nonempty")
        seen.add(row["trial_id"])
        if row.get("direction") not in ROUTES or row.get("class") not in ("siren", "other"):
            raise ValueError(f"Invalid trial: {row}")
        sound_path(row["file"])
    return rows


def score(label, direction, response):
    if label == "other":
        return "correct_rejection" if response is None else "false_alarm"
    if response is None:
        return "miss"
    return "correct_direction" if response == direction else "wrong_direction"
