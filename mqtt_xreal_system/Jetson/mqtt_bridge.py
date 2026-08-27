"""MQTT publisher for ambulance detection state.

Jetson-side helper.  The broker can run on the same Jetson, so broker_host is
usually 127.0.0.1.  Beam Pro subscribes using the Jetson's LAN/Wi-Fi IP.
"""

from __future__ import annotations

import json
import threading
import time
from typing import Optional

import paho.mqtt.client as mqtt


DEFAULT_TOPIC = "research/ambulance/v1/state"


class SirenMqttPublisher:
    """Publish the latest siren/DOA state without blocking the inference loop."""

    def __init__(
        self,
        broker_host: str = "127.0.0.1",
        broker_port: int = 1883,
        topic: str = DEFAULT_TOPIC,
        min_publish_interval: float = 0.10,
        client_id: str = "jetson-ambulance-publisher",
    ) -> None:
        self.broker_host = broker_host
        self.broker_port = int(broker_port)
        self.topic = topic
        self.min_publish_interval = max(0.0, float(min_publish_interval))

        self._connected = False
        self._closed = False
        self._last_publish_monotonic = 0.0
        self._state_lock = threading.Lock()

        self._client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=client_id,
            protocol=mqtt.MQTTv311,
        )
        self._client.on_connect = self._on_connect
        self._client.on_disconnect = self._on_disconnect
        self._client.reconnect_delay_set(min_delay=1, max_delay=10)

        # connect_async + loop_start keeps network I/O off the inference thread.
        self._client.connect_async(self.broker_host, self.broker_port, keepalive=30)
        self._client.loop_start()

    @property
    def connected(self) -> bool:
        with self._state_lock:
            return self._connected

    def _on_connect(self, client, userdata, connect_flags, reason_code, properties) -> None:
        success = not reason_code.is_failure
        with self._state_lock:
            self._connected = success
        if success:
            print(f"[MQTT] Connected: {self.broker_host}:{self.broker_port}")
        else:
            print(f"[MQTT] Connection failed: {reason_code}")

    def _on_disconnect(self, client, userdata, disconnect_flags, reason_code, properties) -> None:
        with self._state_lock:
            self._connected = False
        if not self._closed:
            print(f"[MQTT] Disconnected: {reason_code}; reconnecting...")

    def publish_state(
        self,
        *,
        final_class: str,
        confidence_pct: float,
        doa_deg: Optional[float],
        rms: float = 0.0,
        inference_ms: float = 0.0,
        force: bool = False,
    ) -> bool:
        """Publish one state message.

        Returns True when the message was accepted by the Paho client.
        confidence_pct uses the same 0-100 scale as the current GUI code.
        doa_deg=-1 means unknown.
        """
        if self._closed:
            return False

        now = time.monotonic()
        if not force and now - self._last_publish_monotonic < self.min_publish_interval:
            return False

        # Do not let network loss block or crash the inference thread.
        if not self.connected:
            return False

        direction = -1.0 if doa_deg is None else float(doa_deg)
        payload = {
            "version": 1,
            "detected": final_class == "siren",
            "class_name": str(final_class),
            "confidence_pct": round(float(confidence_pct), 3),
            "doa_deg": round(direction, 3),
            "rms": round(float(rms), 6),
            "inference_ms": round(float(inference_ms), 3),
            "timestamp_ms": int(time.time() * 1000),
        }

        info = self._client.publish(
            self.topic,
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            qos=0,
            retain=False,
        )
        if info.rc == mqtt.MQTT_ERR_SUCCESS:
            self._last_publish_monotonic = now
            return True

        print(f"[MQTT] publish failed: rc={info.rc}")
        return False

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        try:
            self._client.disconnect()
        finally:
            self._client.loop_stop()
        with self._state_lock:
            self._connected = False
