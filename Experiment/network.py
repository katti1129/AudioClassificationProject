"""One request at a time, authenticated JSON lines over trusted local TCP only."""
import json
import socket
import uuid

LIMIT = 16384


def receive(reader):
    line = reader.readline(LIMIT + 1)
    if not line or len(line) > LIMIT or not line.endswith(b"\n"):
        raise ConnectionError("Disconnected or invalid message")
    return json.loads(line)


def send(sock, message):
    sock.sendall(json.dumps(message).encode("utf-8") + b"\n")


class Client:
    def __init__(self, cfg):
        self.cfg = cfg
        try:
            self.sock = socket.create_connection((cfg["host"], cfg["port"]), timeout=2)
        except OSError as e:
            raise ConnectionError(f"TCP connect to {cfg['host']}:{cfg['port']} failed: {e}") from e
        self.sock.settimeout(2)
        self.reader = self.sock.makefile("rb")

    def call(self, command, **kwargs):
        request_id = uuid.uuid4().hex
        try:
            send(self.sock, dict(command=command, request_id=request_id,
                                 token=self.cfg["token"], **kwargs))
        except OSError as e:
            raise ConnectionError(f"Send command={command} failed: {e}") from e
        try:
            result = receive(self.reader)
        except (OSError, ValueError) as e:
            raise ConnectionError(f"Receive reply command={command} failed: {e}") from e
        if result.get("request_id") != request_id or not result.get("ok"):
            raise RuntimeError(result.get("error", "Protocol mismatch"))
        return result

    def close(self):
        self.reader.close()
        self.sock.close()
