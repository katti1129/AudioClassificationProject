"""Configuration is supplied explicitly, independently of the current directory."""
import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    model: Path
    broker: str = "127.0.0.1"
    port: int = 1883
    topic: str = "research/ambulance/v1/state"
    interval: float = 0.10
    result_ttl: float = 1.0
    log_dir: Path | None = None


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="ReSpeaker CRNN + GUI + MQTT for XREAL")
    parser.add_argument("--model", required=True, type=Path, help="Existing trained best.keras")
    parser.add_argument("--broker", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1883)
    parser.add_argument("--topic", default="research/ambulance/v1/state")
    parser.add_argument("--interval", type=float, default=0.10)
    parser.add_argument("--result-ttl", type=float, default=1.0)
    parser.add_argument("--log-dir", type=Path, default=None, help="Enable CSV logging to this folder")
    args = parser.parse_args(argv)
    if not args.model.is_file():
        parser.error("--model must point to an existing trained model")
    if not 1 <= args.port <= 65535 or not 0.02 <= args.interval <= 1 or args.result_ttl <= args.interval:
        parser.error("port 1..65535, interval .02..1, result-ttl > interval required")
    if not args.topic or any(c in args.topic for c in ("+", "#", "\0")):
        parser.error("topic must be a nonempty publish topic without wildcards")
    return Config(**vars(args))
