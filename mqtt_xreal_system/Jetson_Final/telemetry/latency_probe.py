"""Optional software-latency experiment. Never changes the state-topic schema.

Onset is an energy onset, NOT a siren classifier. Use isolated siren trials.
All times here are monotonic seconds; ADC timestamps are mapped at callback time.
"""
import json
import math
import queue
import threading
import time
import uuid


class AudioTiming:
    def __init__(self, threshold=0.01, quiet_seconds=1.0, clock=time.monotonic):
        self.threshold, self.quiet_seconds, self.clock = threshold, quiet_seconds, clock
        self.session = uuid.uuid4().hex
        self.sequence = self.inference = self.trial_number = 0
        self.quiet_since = None
        self.armed = False
        self.trial = None
        self.last_sequence = None
        self.last_adc_end = None
        self.invalid_trials = set()
        self.first_detection = {}

    def audio(self, mono, rate, time_info, status=False):
        import numpy as np
        now = self.clock()
        duration = len(mono) / rate
        try:
            adc, current = float(time_info.inputBufferAdcTime), float(time_info.currentTime)
            valid = math.isfinite(adc) and math.isfinite(current) and adc > 0 and current >= adc
        except (AttributeError, TypeError, ValueError):
            adc = current = 0
            valid = False
        start = now + adc - current if valid else now - duration
        method = "adc_mapped" if valid else "callback_estimate"
        gap = valid and self.last_adc_end is not None and abs(adc - self.last_adc_end) > 2 / rate
        self.last_adc_end = adc + duration if valid else None
        self.sequence += 1
        rms = float(np.sqrt(np.mean(np.square(mono))))
        if not math.isfinite(rms):
            status = True
        if status or gap:
            if self.trial:
                self.trial = dict(self.trial, invalid="audio_gap_or_overflow")
            self.armed = False
            self.quiet_since = None
        if rms < self.threshold and not status and not gap:
            if self.quiet_since is None:
                self.quiet_since = start
            if start + duration - self.quiet_since >= self.quiet_seconds:
                self.armed = True
                self.trial = None
        else:
            if self.armed and not status and not gap:
                indices = np.flatnonzero(np.abs(mono) >= self.threshold)
                index = int(indices[0]) if len(indices) else 0
                self.trial_number += 1
                self.trial = dict(session=self.session, trial_id=str(self.trial_number),
                                  t0=start + index / rate, onset_method=method, invalid="")
            self.armed = False
            self.quiet_since = None
        return dict(self.trial or {}, audio_sequence=self.sequence,
                    audio_end=start + duration)

    def buffered(self, metadata):
        result = dict(metadata)
        expected = 1 if self.last_sequence is None else self.last_sequence + 1
        if metadata["audio_sequence"] != expected:
            if metadata.get("trial_id"):
                self.invalid_trials.add(metadata["trial_id"])
        if metadata.get("trial_id") in self.invalid_trials:
            result["invalid"] = "audio_queue_gap"
        if len(self.invalid_trials) > 128:
            self.invalid_trials = {metadata.get("trial_id")}
        self.last_sequence = metadata["audio_sequence"]
        return result

    def result(self, metadata, final_class):
        self.inference += 1
        if not metadata or "trial_id" not in metadata:
            return None
        t1 = self.clock()
        if final_class == "siren":
            t1 = self.first_detection.setdefault(metadata["trial_id"], t1)
        if len(self.first_detection) > 128:
            self.first_detection = {metadata["trial_id"]: t1}
        return dict(metadata, inference_id=self.inference, t1=t1, final_class=final_class)


class LatencyProbe:
    """Separate bounded telemetry connection; failures never interrupt inference."""
    def __init__(self, host, port, state_topic, threshold=0.01, quiet_seconds=1.0):
        import paho.mqtt.client as mqtt
        self.timing = AudioTiming(threshold, quiet_seconds)
        self.root = state_topic + "/latency"
        self.queue = queue.Queue(maxsize=256)
        self.dropped = 0
        self.last_event = None
        self.stop = threading.Event()
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                                  client_id="latency-jetson-" + self.timing.session[:12])
        self.client.max_queued_messages_set(256)
        self.client.reconnect_delay_set(1, 10)
        self.client.on_connect = self._connect
        self.client.on_message = self._message
        self.client.connect_async(host, port, 30)
        self.client.loop_start()
        self.worker = threading.Thread(target=self._run, daemon=True, name="latency-telemetry")
        self.worker.start()

    def _connect(self, client, userdata, flags, reason, properties):
        if not reason.is_failure:
            client.subscribe(self.root + "/sync/request", qos=0)

    def _message(self, client, userdata, message):
        s2 = time.monotonic()
        try:
            if message.retain or len(message.payload) > 2048:
                return
            data = json.loads(message.payload)
            identifier = data["id"]
            if not isinstance(identifier, str) or len(identifier) > 96:
                return
            self._send("sync/response", dict(id=identifier, session=self.timing.session,
                                             s2=s2, s3=time.monotonic()))
        except (ValueError, KeyError, TypeError):
            pass

    def _send(self, suffix, data):
        if not self.client.is_connected():
            self.dropped += 1
            return
        try:
            info = self.client.publish(self.root + "/" + suffix,
                                       json.dumps(data, allow_nan=False), qos=0, retain=False)
            if info.rc != 0:
                self.dropped += 1
        except (ValueError, OSError, RuntimeError):
            self.dropped += 1

    def submit(self, suffix, data):
        try:
            self.queue.put_nowait((suffix, dict(data)))
        except queue.Full:
            self.dropped += 1

    def audio(self, mono, rate, time_info, status):
        metadata = self.timing.audio(mono, rate, time_info, status)
        key = (metadata.get("trial_id"), metadata.get("invalid"))
        if key[0] and key != self.last_event:
            self.submit("event", metadata)
            self.last_event = key
        return metadata

    def published(self, metadata, timestamp_ms, t2):
        if metadata:
            self.submit("result", dict(metadata, timestamp_ms=timestamp_ms, t2=t2,
                                       telemetry_dropped=self.dropped))

    def _run(self):
        while not self.stop.is_set() or not self.queue.empty():
            try:
                suffix, data = self.queue.get(timeout=.1)
            except queue.Empty:
                continue
            self._send(suffix, data)

    def close(self):
        self.stop.set()
        self.worker.join(timeout=2)
        self.client.disconnect()
        self.client.loop_stop()
