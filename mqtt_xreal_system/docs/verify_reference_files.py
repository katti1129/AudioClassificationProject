"""Check the original baseline files without modifying them."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
baseline = json.loads(Path(__file__).with_name("baseline_hashes.json").read_text(encoding="utf-8-sig"))
errors = []
for entry in baseline:
    path = root / entry["Path"].replace("\\", "/")
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest().upper() != entry["Hash"]:
        errors.append(entry["Path"])
if errors:
    raise SystemExit("Baseline changed: " + ", ".join(errors))
print(f"PASS: {len(baseline)} original files unchanged (SHA256)")
