"""Run from repository root: python -m mqtt_xreal_system.Jetson_Final.app.realtime_xreal_system --model /path/best.keras"""
import sys
import threading
import time
from datetime import datetime, timezone

from ..config.config import parse_args
from ..mqtt.mqtt_bridge import SirenMqttPublisher
from ..telemetry.experiment_logger import ExperimentLogger
from .state_relay import StateRelay


def main(argv=None):
    config = parse_args(argv)
    # Heavy hardware/ML imports are delayed so --help works on a development PC.
    from . import legacy_gui as gui
    from PySide6.QtWidgets import QLabel
    relay = StateRelay()
    gui.MODEL_PATH = str(config.model.resolve())
    publisher = SirenMqttPublisher(broker_host=config.broker, broker_port=config.port,
                                  topic=config.topic, min_publish_interval=config.interval)
    logger = ExperimentLogger(config.log_dir)
    stop = threading.Event()
    original_update, original_audio = gui.update_gui_state, gui.audio_callback

    def update(final_class, confidence, rms, latency):
        original_update(final_class, confidence, rms, latency)
        relay.update(final_class, confidence, rms, latency)

    def audio(indata, frames, time_info, status):
        original_audio(indata, frames, time_info, status)
        relay.audio_received()

    gui.update_gui_state, gui.audio_callback = update, audio
    original_window = gui.NotificationWindow

    class ConnectedWindow(original_window):
        def __init__(self):
            super().__init__()
            self.setFixedSize(460, 300)
            self.mqtt_label = QLabel("MQTT: connecting")
            self.container.layout().addWidget(self.mqtt_label)

        def refresh_display(self):
            super().refresh_display()
            fresh = relay.snapshot(config.result_ttl) is not None
            self.mqtt_label.setText(
                f"MQTT: {'connected' if publisher.connected else 'disconnected / retrying'}"
                f" | AI: {'fresh' if fresh else 'waiting / stale'}"
                f"\nCSV: {logger.error or ('ON' if logger.path else 'OFF')} | dropped: {logger.dropped}")

    gui.NotificationWindow = ConnectedWindow

    def publish_loop():
        while not stop.is_set():
            sample = relay.snapshot(config.result_ttl)
            if sample is not None:
                # Read DOA at publish time, not at start of the 1 s audio window.
                sample["doa_deg"] = gui.get_current_direction_value()
                publisher.publish_state(**sample)
                logger.submit(dict(sample, timestamp=datetime.now(timezone.utc).isoformat(), mqtt_connected=publisher.connected))
            # Expired AI/audio state is never re-stamped and replayed as fresh.
            stop.wait(config.interval)

    worker = threading.Thread(target=publish_loop, daemon=True, name="mqtt-state-relay")
    worker.start()
    try:
        gui.main()
    finally:
        stop.set()
        worker.join(timeout=2)
        publisher.close()
        logger.close()


if __name__ == "__main__":
    main()
