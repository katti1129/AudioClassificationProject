"""No recording/playback. Check TCP, authentication and repeated round trips."""
import argparse
import time
from common import config
from network import Client


def check(cfg):
    print(f"Connecting to {cfg['host']}:{cfg['port']} ...", flush=True)
    client = None
    try:
        client = Client(cfg)
        print("TCP connected", flush=True)
        for i in range(5):
            start = time.perf_counter()
            reply = client.call("status")
            ms = (time.perf_counter() - start) * 1000
            print(f"PASS {i+1}/5: authenticated status reply, round-trip={ms:.1f} ms; "
                  f"connection_only={reply.get('connection_only', 'unknown')}", flush=True)
            time.sleep(.25)
        client.call("bye")
        print("PASS: connection check complete. Audio timing is not measured.", flush=True)
        return 0
    except Exception as e:
        print(f"FAIL: {type(e).__name__}: {e}", flush=True)
        return 1
    finally:
        if client:
            client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.local.json")
    parser.add_argument("--host", help="Override destination for this check only (e.g. 127.0.0.1)")
    args = parser.parse_args()
    cfg = config(args.config)
    if args.host:
        cfg["host"] = args.host
    raise SystemExit(check(cfg))
