"""Child server. Logs protocol stages without logging tokens or message bodies."""
import argparse
import secrets
import socket
import time
from common import config, digest, sound_path
from network import receive, send


def handle_connection(conn, cfg, player, log=print):
    current, played = None, False
    rid, stage, cmd = None, "setup", None
    started = time.monotonic()

    def report(text):
        log(f"[+{time.monotonic() - started:.3f}s] {text}")

    # Send error responses before closing the socket, unlike the original handler.
    with conn:
        try:
            conn.settimeout(2)
            with conn.makefile("rb") as reader:
                while True:
                    rid, cmd = None, None
                    stage = "receive_request"
                    report("Waiting for request")
                    msg = receive(reader)
                    if not isinstance(msg, dict):
                        raise ValueError("Expected JSON object")
                    rid = msg.get("request_id")
                    if not isinstance(rid, str):
                        raise ValueError("Missing request_id")
                    stage = "authenticate"
                    supplied = msg.get("token")
                    if not isinstance(supplied, str) or not secrets.compare_digest(
                            supplied.encode("utf-8"), cfg["token"].encode("utf-8")):
                        raise ValueError("Authentication failed: check matching token locally")
                    cmd = msg.get("command")
                    if cmd not in ("prepare", "play", "stop", "status", "bye"):
                        raise ValueError("Unknown command")
                    report(f"Authenticated command={cmd}")
                    stage = "execute_" + cmd
                    result = {}
                    if cmd == "prepare":
                        if player is None:
                            raise ValueError("Connection-only server: restart without --connection-only")
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
                        if player is None or current != msg["trial_id"] or played:
                            raise ValueError("Stale or duplicate play, or not prepared")
                        player.play()
                        played = True
                    elif cmd in ("stop", "bye"):
                        if player:
                            player.stop()
                    elif cmd == "status":
                        result.update(audio_error=player.error if player else None,
                                      connection_only=player is None)
                    stage = "send_reply_" + cmd
                    send(conn, dict(ok=True, request_id=rid, **result))
                    report(f"Reply sent command={cmd}")
                    if cmd == "bye":
                        report("Session closed normally")
                        return
        except Exception as e:
            report(f"Session stopped: stage={stage}; {type(e).__name__}: {e}")
            if rid is not None:
                try:
                    send(conn, dict(ok=False, request_id=rid, error=f"{stage}: {e}"))
                except OSError as reply_error:
                    report(f"Error reply could not be sent: {reply_error}")
        finally:
            if player:
                player.stop()


def serve(cfg, bind, connection_only=False):
    if not cfg["token"] or cfg["token"] == "CHANGE-ME-before-use":
        raise ValueError("Set the same private token in both config.local.json files")
    player = None
    if not connection_only:
        if cfg["output_device"] is None:
            raise ValueError("Select the child output_device in config.local.json")
        from audio import Player
        player = Player(cfg)
    with socket.socket() as server:
        server.bind((bind, cfg["port"]))
        server.listen(1)
        print(f"Listening on {bind}:{cfg['port']}; Ctrl+C to stop", flush=True)
        if connection_only:
            print("Connection-only mode: no audio playback", flush=True)
        while True:
            conn, addr = server.accept()
            print("Connected:", addr, flush=True)
            handle_connection(conn, cfg, player, log=lambda text: print(text, flush=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.local.json")
    parser.add_argument("--bind", default="127.0.0.1", help="Child LAN IP for remote access")
    parser.add_argument("--connection-only", action="store_true", help="Test network without audio devices")
    args = parser.parse_args()
    serve(config(args.config), args.bind, args.connection_only)
