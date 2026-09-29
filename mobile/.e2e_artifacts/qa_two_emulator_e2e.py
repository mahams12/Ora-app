#!/usr/bin/env python3
"""Two-emulator E2E wrapper — waits for both adb devices, then runs qa_full_two_actor_e2e."""
from __future__ import annotations

import os
import subprocess
import sys
import time

P = os.environ.get("ORA_E2E_PASSENGER", "emulator-5554")
D = os.environ.get("ORA_E2E_DRIVER", "emulator-5556")
TIMEOUT = int(os.environ.get("ORA_E2E_DEVICE_WAIT_S", "180"))


def adb_ok(serial: str) -> bool:
    try:
        out = subprocess.check_output(
            ["adb", "-s", serial, "shell", "getprop", "sys.boot_completed"],
            stderr=subprocess.DEVNULL,
            timeout=15,
        ).decode().strip()
        return out == "1"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return False


def wait_both() -> None:
    t0 = time.time()
    while time.time() - t0 < TIMEOUT:
        if adb_ok(P) and adb_ok(D):
            print(f"devices ready: passenger={P} driver={D}", flush=True)
            return
        subprocess.call(["adb", "devices"], stdout=subprocess.DEVNULL)
        time.sleep(4)
    print(f"TIMEOUT waiting for {P} and {D}", file=sys.stderr)
    subprocess.call(["adb", "devices"])
    sys.exit(2)


def main() -> None:
    os.environ.setdefault("ORA_E2E_PASSENGER", P)
    os.environ.setdefault("ORA_E2E_DRIVER", D)
    wait_both()
    subprocess.check_call(
        [sys.executable, os.path.join(os.path.dirname(__file__), "qa_full_two_actor_e2e.py")],
        env=os.environ,
    )


if __name__ == "__main__":
    main()
