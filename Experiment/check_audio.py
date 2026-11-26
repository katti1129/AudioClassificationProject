"""Record a fixed microphone placement or test one stereo channel. No latency certification."""
import argparse
import time
from datetime import datetime
import sounddevice as sd
from common import ROOT, config, sound_path
from audio import Recorder, Player


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--config", default="config.local.json")
    p.add_argument("--list-devices", action="store_true")
    p.add_argument("--record", action="store_true")
    p.add_argument("--seconds", type=float, default=15)
    p.add_argument("--play", help="Mono WAV filename inside sounds/")
    p.add_argument("--channel", type=int, choices=[0, 1], default=0)
    a = p.parse_args()
    if a.list_devices:
        print(sd.query_devices())
    else:
        cfg = config(a.config)
        if a.record:
            if cfg["input_device"] is None:
                raise ValueError("Select NSW-088 input_device in config.local.json first")
            out = ROOT / "results" / ("mic_check_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".wav")
            out.parent.mkdir(exist_ok=True)
            rec = Recorder(cfg, out)
            try:
                rec.start()
                time.sleep(cfg["settle_s"])
                rec.arm()
                end = time.perf_counter() + a.seconds
                while time.perf_counter() < end:
                    print(f"peak={rec.peak_dbfs:.1f} dBFS onset={rec.onset} error={rec.error}", flush=True)
                    time.sleep(.25)
            finally:
                rec.close()
            print("Saved:", out, "error:", rec.error)
        elif a.play:
            if cfg["output_device"] is None:
                raise ValueError("Select output_device in config.local.json first")
            player = Player(cfg)
            try:
                player.prepare(sound_path(a.play), a.channel)
                player.play()
                while player.stream.active:
                    time.sleep(.05)
                print("Finished; audio error:", player.error)
            finally:
                player.stop()
        else:
            p.error("Choose --list-devices, --record or --play")
