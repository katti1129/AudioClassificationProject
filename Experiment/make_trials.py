"""Generate a balanced list from a manifest, or create unmistakably synthetic DEMO stimuli."""
import argparse
import csv
import random
from common import ROOT, ROUTES, sound_path


def generate(manifest, output, repeats, seed):
    if repeats < 1:
        raise ValueError("repeats must be positive")
    with open(manifest, encoding="utf-8-sig", newline="") as f:
        sounds = list(csv.DictReader(f))
    for row in sounds:
        sound_path(row["file"])
        if row["class"] not in ("siren", "other"):
            raise ValueError("Invalid class")
    if {r["class"] for r in sounds} != {"siren", "other"}:
        raise ValueError("Both siren and other are required")
    rows = [dict(file=s["file"], **{"class": s["class"]}, direction=d)
            for _ in range(repeats) for s in sounds for d in ROUTES]
    random.Random(seed).shuffle(rows)
    with open(output, "x", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["trial_id", "file", "class", "direction"])
        writer.writeheader()
        for i, row in enumerate(rows, 1):
            writer.writerow(dict(trial_id=str(i), **row))
    print(f"{len(rows)} trials -> {output}; seed={seed}. Keep this list for reproducibility.")
    print("Equal class counts require equal numbers of siren/other files in manifest.")


def demo():
    import numpy as np
    import soundfile as sf
    folder = ROOT / "sounds"
    folder.mkdir(exist_ok=True)
    rate = 48000
    t = np.arange(rate * 2) / rate
    for label, frequency in [("siren", 800), ("other", 400)]:
        path = folder / f"DEMO_{label}.wav"
        if path.exists():
            raise FileExistsError(path)
        # These are tones, NOT research siren/other exemplars.
        x = .3 * np.sin(2 * np.pi * frequency * t)
        x[:480] *= np.linspace(0, 1, 480)
        x[-480:] *= np.linspace(1, 0, 480)
        sf.write(path, x, rate)
    print("Created synthetic DEMO tones; never use them as experimental stimuli.")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", default=str(ROOT / "manifest.example.csv"))
    p.add_argument("--output", default=str(ROOT / "trials.csv"))
    p.add_argument("--repeats", type=int, default=4)
    p.add_argument("--seed", type=int, default=20261117)
    p.add_argument("--demo", action="store_true")
    a = p.parse_args()
    if a.demo:
        demo()
    generate(a.manifest, a.output, a.repeats, a.seed)
