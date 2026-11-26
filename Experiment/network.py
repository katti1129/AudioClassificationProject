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
        self.sock = socket.create_connection((cfg["host"], cfg["port"]), timeout=2)
        self.sock.settimeout(2)
        self.reader = self.sock.makefile("rb")

    def call(self, command, **kwargs):
        request_id = uuid.uuid4().hex
        send(self.sock, dict(command=command, request_id=request_id,
                             token=self.cfg["token"], **kwargs))
        result = receive(self.reader)
        if result.get("request_id") != request_id or not result.get("ok"):
            raise RuntimeError(result.get("error", "Protocol mismatch"))
        return result

    def close(self):
        self.reader.close()
        self.sock.close()
