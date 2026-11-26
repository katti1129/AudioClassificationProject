"""Explicit stereo playback and raw microphone recording with provisional timestamps."""
import queue
import threading
import time
import numpy as np
import sounddevice as sd
import soundfile as sf


class Player:
    def __init__(self, cfg):
        self.cfg = cfg
        self.stream = None
        self.error = None
        self.data = None

    def prepare(self, path, channel):
        self.stop()
        samples, rate = sf.read(path, dtype="float32", always_2d=True)
        if samples.shape[1] != 1:
            raise ValueError("Use mono WAV stimuli; stereo files are not silently mixed")
        if rate != self.cfg["sample_rate"] or not len(samples):
            raise ValueError("WAV sample rate must match config and contain samples")
        if not np.isfinite(samples).all():
            raise ValueError("Non-finite audio samples")
        self.data = np.zeros((len(samples), 2), dtype="float32")
        self.data[:, channel] = samples[:, 0] * self.cfg["gain"]
        if np.max(np.abs(self.data)) > 1:
            raise ValueError("Playback would clip")
        self.position = 0
        self.error = None

    def play(self):
        if self.data is None:
            raise RuntimeError("Not prepared")

        def callback(out, frames, timing, status):
            if status:
                self.error = str(status)
            out.fill(0)
            n = min(frames, len(self.data) - self.position)
            out[:n] = self.data[self.position:self.position + n]
            self.position += n
            if n < frames:
                raise sd.CallbackStop

        self.stream = sd.OutputStream(device=self.cfg["output_device"], channels=2,
                                      samplerate=self.cfg["sample_rate"], callback=callback)
        self.stream.start()

    def stop(self):
        if self.stream is not None:
            try:
                self.stream.abort()
            finally:
                self.stream.close()
                self.stream = None


class Recorder:
    def __init__(self, cfg, path):
        self.cfg, self.path = cfg, path
        self.onset = None
        self.onset_sample = None
        self.error = None
        self.peak_dbfs = -120.0
        self.armed_at = float("inf")
        self.index = 0
        self.run = 0
        self.blocks = queue.Queue(maxsize=256)
        self.stream = None
        self.writer = None
        self.threshold = 10 ** (cfg["threshold_dbfs"] / 20)
        self.minimum = max(1, round(cfg["sample_rate"] * cfg["min_above_ms"] / 1000))
        self.window = max(1, round(cfg["sample_rate"] * 0.001))
        self.tail = np.zeros(self.window - 1)

    def start(self):
        def write():
            try:
                with sf.SoundFile(self.path, mode="w", samplerate=self.cfg["sample_rate"],
                                  channels=1, subtype="FLOAT") as f:
                    while True:
                        block = self.blocks.get()
                        if block is None:
                            return
                        f.write(block)
            except Exception as e:
                self.error = f"recording write: {e}"
        self.writer = threading.Thread(target=write, daemon=True)
        self.writer.start()
        self.stream = sd.InputStream(device=self.cfg["input_device"], channels=1,
                                     samplerate=self.cfg["sample_rate"], blocksize=256,
                                     callback=self._callback)
        self.stream.start()

    def _callback(self, data, frames, timing, status):
        now = time.perf_counter()
        if status:
            self.error = str(status)
        try:
            self.blocks.put_nowait(data.copy())
        except queue.Full:
            self.error = "Recording queue overflow"
        samples = data[:, 0]
        power = np.concatenate((self.tail, samples.astype("float64") ** 2))
        envelope = np.sqrt(np.convolve(power, np.ones(self.window) / self.window, mode="valid"))
        self.tail = power[-(self.window - 1):] if self.window > 1 else np.empty(0)
        self.peak_dbfs = float(20 * np.log10(max(float(np.max(np.abs(samples))), 1e-6)))
        # Approximate clock bridge. This is NOT a calibrated physical-onset timestamp.
        if timing.inputBufferAdcTime <= 0 or timing.currentTime <= 0:
            self.error = "Audio backend did not provide valid capture timestamps"
        base = (now + timing.inputBufferAdcTime - timing.currentTime
                + self.cfg["input_time_correction_ms"] / 1000)
        rate = self.cfg["sample_rate"]
        if self.onset is None:
            for i, value in enumerate(envelope):
                stamp = base + i / rate
                if stamp >= self.armed_at and abs(value) >= self.threshold:
                    if self.run == 0:
                        self.run_time, self.run_index = stamp, self.index + i
                    self.run += 1
                    if self.run >= self.minimum:
                        self.onset_sample = self.run_index
                        self.onset = self.run_time
                        break
                else:
                    self.run = 0
        self.index += frames

    def arm(self):
        self.run = 0
        self.armed_at = time.perf_counter()
        return self.armed_at

    def close(self):
        if self.stream is not None:
            try:
                self.stream.stop()
            except Exception as e:
                self.error = f"recording stop: {e}"
            finally:
                try:
                    self.stream.close()
                except Exception as e:
                    self.error = f"recording close: {e}"
        if self.writer is not None:
            while self.writer.is_alive():
                try:
                    self.blocks.put(None, timeout=0.2)
                    break
                except queue.Full:
                    pass
            self.writer.join(timeout=3)
            if self.writer.is_alive():
                self.error = "Recording writer did not finish"
