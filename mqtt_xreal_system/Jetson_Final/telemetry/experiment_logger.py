"""Bounded asynchronous CSV logger (telemetry avoids shadowing stdlib logging)."""
import csv
from datetime import datetime, timezone
from pathlib import Path
from queue import Queue, Empty, Full
from threading import Event, Thread


class ExperimentLogger:
    fields = ("timestamp", "final_class", "confidence_pct", "doa_deg", "rms", "inference_ms", "mqtt_connected")

    def __init__(self, directory=None):
        self.dropped = 0
        self.error = None
        self._queue = Queue(maxsize=512)
        self._stop = Event()
        self._thread = None
        self.path = None
        if directory:
            folder = Path(directory)
            try:
                folder.mkdir(parents=True, exist_ok=True)
            except OSError as exc:
                self.error = str(exc)
                return
            self.path = folder / (datetime.now(timezone.utc).strftime("experiment_%Y%m%d_%H%M%S_%f") + ".csv")
            self._thread = Thread(target=self._write, daemon=True, name="experiment-csv")
            self._thread.start()

    def submit(self, row):
        if self._thread and not self._stop.is_set() and self.error is None:
            try:
                self._queue.put_nowait(dict(row))
            except Full:
                self.dropped += 1

    def _write(self):
        try:
            with self.path.open("w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=self.fields, extrasaction="ignore")
                writer.writeheader()
                while not self._stop.is_set() or not self._queue.empty():
                    try:
                        writer.writerow(self._queue.get(timeout=0.2))
                        output.flush()
                    except Empty:
                        pass
        except OSError as exc:
            self.error = str(exc)

    def close(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)
