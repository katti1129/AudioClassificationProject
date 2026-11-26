"""Run on the child PC. Stops playback after connection loss / 2 s without a request."""
import argparse
import secrets
import socket
from audio import Player
from common import config, digest, sound_path
from network import receive, send


def serve(cfg, bind):
    if cfg["token"] == "CHANGE-ME-before-use":
        raise ValueError("Set the same private token in both config.local.json files")
    if cfg["output_device"] is None:
        raise ValueError("Select the child output_device in config.local.json")
    player = Player(cfg)
    with socket.socket() as server:
        server.bind((bind, cfg["port"]))
        server.listen(1)
        print(f"Listening on {bind}:{cfg['port']}; Ctrl+C to stop", flush=True)
        while True:
            conn, addr = server.accept()
            print("Connected:", addr, flush=True)
            current, played = None, False
            try:
                with conn, conn.makefile("rb") as reader:
                    conn.settimeout(2)
                    while True:
                        msg = receive(reader)
                        rid = msg.get("request_id")
                        if not secrets.compare_digest(str(msg.get("token", "")), cfg["token"]):
                            raise ValueError("Authentication failed")
                        cmd = msg.get("command")
                        result = {}
                        if cmd == "prepare":
                            path = sound_path(msg["file"])
                            if digest(path) != msg["sha256"]:
                                raise ValueError("Stimulus hash mismatch")
                            if msg["channel"] not in (0, 1):
                                raise ValueError("Invalid channel")
                            if msg["sample_rate"] != cfg["sample_rate"] or msg["gain"] != cfg["gain"]:
                                raise ValueError("Parent/child audio settings mismatch")
                            player.prepare(path, msg["channel"])
                            current, played = msg["trial_id"], False
                        elif cmd == "play":
                            if current != msg["trial_id"] or played:
                                raise ValueError("Stale or duplicate play")
                            player.play()
                            played = True
                        elif cmd == "stop":
                            player.stop()
                        elif cmd == "status":
                            result["audio_error"] = player.error
                        else:
                            raise ValueError("Unknown command")
                        send(conn, dict(ok=True, request_id=rid, **result))
            except Exception as e:
                print("Session stopped:", e, flush=True)
                try:
                    send(conn, dict(ok=False, request_id=rid, error=str(e)))
                except Exception:
                    pass
            finally:
                player.stop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.local.json")
    parser.add_argument("--bind", default="127.0.0.1", help="Child LAN IP for remote access")
    args = parser.parse_args()
    serve(config(args.config), args.bind)
