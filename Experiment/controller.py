"""Experiment state machine. GUI is notified through a thread-safe queue."""
import csv
import json
import queue
import threading
import time
from datetime import datetime
from pathlib import Path
from audio import Player, Recorder
from common import ROOT, ROUTES, digest, score, sound_path
from network import Client


class Controller:
    def __init__(self, cfg, trials, participant, condition, mode, notify):
        self.cfg, self.trials, self.notify = cfg, trials, notify
        self.participant, self.condition, self.mode = participant, condition, mode
        self.stop_event = threading.Event()
        self.pause_event = threading.Event()
        self.inputs = queue.Queue()
        self.accepting = False
        self.client = None
        self.player = Player(cfg)
        self.last_ping = 0
        self.folder = ROOT / "results" / (datetime.now().strftime("%Y%m%d_%H%M%S_%f") + "_" + participant)

    def post(self, state, **details):
        self.notify.put(dict(state=state, **details))

    def key(self, direction, timestamp):
        self.inputs.put((direction, timestamp, self.accepting))

    def event(self, kind, **data):
        self.events.write(json.dumps(dict(event=kind, perf_counter=time.perf_counter(), **data),
                                    ensure_ascii=False) + "\n")
        self.events.flush()

    def tick(self):
        if self.stop_event.is_set():
            raise InterruptedError("Operator emergency stop")
        if self.client and time.perf_counter() - self.last_ping > .25:
            reply = self.client.call("status")
            self.last_ping = time.perf_counter()
            if reply.get("audio_error"):
                raise RuntimeError("Child audio: " + reply["audio_error"])
        if self.player.error:
            raise RuntimeError("Parent audio: " + self.player.error)

    def wait(self, seconds):
        end = time.perf_counter() + seconds
        while time.perf_counter() < end:
            self.tick()
            time.sleep(.01)

    def stop_audio(self):
        self.player.stop()
        if self.client:
            self.client.call("stop")
        self.event("playback_stop_ack")

    def run(self):
        try:
            self._run()
        except Exception as e:
            self.post("起動エラー", error=str(e))
        finally:
            self.post("終了処理完了")

    def _run(self):
        self.folder.mkdir(parents=True, exist_ok=False)
        safe_cfg = {k: v for k, v in self.cfg.items() if k != "token"}
        metadata = dict(config=safe_cfg, participant=self.participant, condition=self.condition,
                        mode=self.mode, routes=ROUTES, trials=self.trials,
                        timing_note="Provisional ADC/perf_counter bridge; validate externally before reporting RT",
                        stimulus_hashes={r["file"]: digest(sound_path(r["file"])) for r in self.trials})
        (self.folder / "session.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
        fields = ["trial_id", "file", "class", "direction", "pc", "channel", "response", "onset",
                  "onset_sample", "response_time", "rt_s", "outcome", "valid", "error", "timing_calibrated"]
        try:
            with open(self.folder / "events.jsonl", "w", encoding="utf-8") as self.events, \
                    open(self.folder / "trials.csv", "w", encoding="utf-8-sig", newline="") as results:
                writer = csv.DictWriter(results, fieldnames=fields)
                writer.writeheader()
                self.event("session_start")
                try:
                    if any(ROUTES[r["direction"]][0] == "child" for r in self.trials):
                        self.client = Client(self.cfg)
                        self.client.call("status")
                    for number, trial in enumerate(self.trials, 1):
                        while self.pause_event.is_set():
                            self.post("一時停止中")
                            self.wait(.1)
                        self.tick()
                        row = self.run_trial(trial, number)
                        writer.writerow(row)
                        results.flush()
                        self.post("試行保存", row=row, folder=str(self.folder))
                        if not row["valid"]:
                            raise RuntimeError("Invalid trial; session stopped: " + row["error"])
                        if number < len(self.trials):
                            self.post("無音待機（5秒、設定変更可）")
                            self.wait(self.cfg["silence_s"])
                            if self.mode == "practice":
                                self.pause_event.set()
                    self.post("完了", folder=str(self.folder))
                except Exception as e:
                    self.event("session_error", error=str(e))
                    self.post("中断", error=str(e), folder=str(self.folder))
                finally:
                    self.accepting = False
                    try:
                        self.stop_audio()
                    except Exception as e:
                        self.event("stop_failed", error=str(e))
                    if self.client:
                        self.client.close()
                    self.event("session_end")
        except Exception as e:
            self.post("保存または起動エラー", error=str(e), folder=str(self.folder))
    def run_trial(self, trial, number):
        pc, channel = ROUTES[trial["direction"]]
        row = {k: trial[k] for k in ("trial_id", "file", "class", "direction")}
        row.update(pc=pc, channel=channel, response="", onset="", onset_sample="", response_time="",
                   rt_s="", outcome="invalid", valid=False, error="",
                   timing_calibrated=self.cfg["timing_calibrated"])
        rec = Recorder(self.cfg, self.folder / f"trial_{number:04d}.wav")
        self.event("trial_prepare", **row)
        pending = []
        try:
            self.post("準備中", number=number, total=len(self.trials), trial=trial)
            path = sound_path(trial["file"])
            if pc == "child":
                self.client.call("prepare", trial_id=trial["trial_id"], file=trial["file"],
                                 channel=channel, sha256=digest(path), gain=self.cfg["gain"],
                                 sample_rate=self.cfg["sample_rate"])
            else:
                self.player.prepare(path, channel)
            rec.start()
            self.wait(self.cfg["settle_s"])
            while not self.inputs.empty():
                self.event("ignored_input", data=self.inputs.get_nowait())
            start = rec.arm()
            self.accepting = True
            self.event("play_requested", trial_id=trial["trial_id"], requested_at=start)
            self.post("発音検出・回答待ち")
            if pc == "child":
                self.client.call("play", trial_id=trial["trial_id"])
            else:
                self.player.play()
            last_view = 0
            while True:
                self.tick()
                if rec.error:
                    raise RuntimeError(rec.error)
                while not self.inputs.empty():
                    answer = self.inputs.get_nowait()
                    self.event("key", direction=answer[0], timestamp=answer[1], armed=answer[2])
                    if answer[2]:
                        pending.append(answer)
                now = time.perf_counter()
                if now - last_view > .1:
                    self.post("回答待ち" if rec.onset else "発音検出待ち", peak=rec.peak_dbfs,
                              elapsed=now - rec.onset if rec.onset else None)
                    last_view = now
                if rec.onset is None:
                    if now - start >= self.cfg["onset_timeout_s"]:
                        raise RuntimeError("No acoustic onset detected; not scored as participant miss")
                else:
                    row.update(onset=rec.onset, onset_sample=rec.onset_sample)
                    deadline = rec.onset + self.cfg["response_timeout_s"]
                    if pending:
                        direction, timestamp, _ = pending[0]
                        if timestamp < rec.onset:
                            raise RuntimeError("Premature key before detected acoustic onset")
                        if timestamp <= deadline:
                            row.update(response=direction, response_time=timestamp, rt_s=timestamp - rec.onset)
                            break
                    if now >= deadline:
                        break
                time.sleep(.005)
            row["outcome"] = score(trial["class"], trial["direction"], row["response"] or None)
            row["valid"] = True
        except Exception as e:
            row["error"] = str(e)
        finally:
            self.accepting = False
            try:
                self.stop_audio()
            except Exception as e:
                row.update(valid=False, error=row["error"] + "; stop: " + str(e))
            try:
                rec.close()
                if rec.error:
                    row.update(valid=False, error=row["error"] + "; recording: " + rec.error)
            except Exception as e:
                row.update(valid=False, error=row["error"] + "; close: " + str(e))
            if not row["valid"]:
                row["outcome"] = "invalid"
            self.event("trial_end", **row)
        return row
