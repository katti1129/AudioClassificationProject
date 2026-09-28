"""Bounded latest-state handoff; inference never waits for disk or networking."""
import threading
import time


class StateRelay:
    def __init__(self):
        self._lock = threading.Lock()
        self._state = None
        self._updated = float("-inf")
        self._audio_updated = float("-inf")

    def audio_received(self):
        with self._lock:
            self._audio_updated = time.monotonic()

    def update(self, final_class, confidence, rms, latency):
        with self._lock:
            self._state = dict(final_class=final_class, confidence_pct=float(confidence),
                               rms=float(rms), inference_ms=float(latency) * 1000)
            self._updated = time.monotonic()

    def snapshot(self, ttl, audio_ttl=0.5):
        with self._lock:
            now = time.monotonic()
            if now - self._updated > ttl or now - self._audio_updated > audio_ttl:
                return None
            return dict(self._state) if self._state else None
