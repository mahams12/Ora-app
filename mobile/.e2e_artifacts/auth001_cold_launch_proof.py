#!/usr/bin/env python3
"""AUTH-001 physical cold-launch proof — ops only."""
import json
import re
import subprocess
import sys
import time
from pathlib import Path

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ART = Path(__file__).resolve().parent
UI = ART / "auth001_ui.xml"
REPORT = ART / "auth001_device_proof_report.json"
BACKEND_LOG = ART / "p5c_backend_8081.log"
MARKERS = (
    "AUTH_BOOT_START",
    "AUTH_BOOT_COMPLETE",
    "AUTH_BOOT_TIMEOUT",
    "AUTH_BOOT_ERROR",
    "AUTH_RETRY_START",
    "AUTH_RETRY_COMPLETE",
)


def adb(*args: str, capture: bool = False) -> str:
    r = subprocess.run(
        ["adb", "-s", DEVICE, *args],
        check=False,
        capture_output=capture,
        text=True,
    )
    if capture:
        return r.stdout or ""
    if r.returncode != 0:
        raise subprocess.CalledProcessError(r.returncode, r.args)
    return ""


def dump_ui() -> str:
    adb("shell", "uiautomator", "dump", "/sdcard/auth001_ui.xml")
    adb("pull", "/sdcard/auth001_ui.xml", str(UI))
    return UI.read_text(encoding="utf-8")


def screen_state(xml: str) -> dict:
    return {
        "signing_in": "Signing you in" in xml,
        "try_again": "Try again" in xml,
        "home": "Where are you headed" in xml or "Request a ride" in xml,
        "phone": "Send code" in xml or "Phone number" in xml,
        "bootstrap_error": "deployment could not be found" in xml.lower()
        or "network error" in xml.lower(),
    }


def tap_try_again(xml: str) -> bool:
    for m in re.finditer(
        r'text="Try again"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    ):
        x1, y1, x2, y2 = map(int, m.groups())
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        return True
    return False


def count_backend(path: Path, needle: str) -> int:
    if not path.is_file():
        return 0
    return path.read_text(encoding="utf-8", errors="replace").count(needle)


def main() -> None:
    t0 = time.time()
    adb("reverse", "tcp:8081", "tcp:8080")
    adb("install", "-r", "/Users/jazimsaeed/Ora-app/mobile/build/app/outputs/flutter-apk/app-debug.apk")
    reg_before = count_backend(BACKEND_LOG, "register_ok")
    me_before = count_backend(BACKEND_LOG, 'GET /v1/auth/me')

    adb("shell", "am", "force-stop", PKG)
    adb("logcat", "-c")
    adb(
        "shell",
        "am",
        "start",
        "-W",
        "-n",
        f"{PKG}/.MainActivity",
    )

    timeline: list[dict] = []
    home_ms: int | None = None
    try_again_tapped = False
    try_again_ms: int | None = None

    for i in range(30):
        time.sleep(2)
        xml = dump_ui()
        st = screen_state(xml)
        elapsed = int((time.time() - t0) * 1000)
        timeline.append({"poll": i, "elapsedMs": elapsed, **st})
        if st["home"] and home_ms is None:
            home_ms = elapsed
            break
        if elapsed >= 30000 and not try_again_tapped and st["try_again"]:
            try_again_tapped = True
            try_again_ms = elapsed
            tap_try_again(xml)

    logcat = adb("logcat", "-d", capture=True)
    markers = {m: logcat.count(m) for m in MARKERS}
    last_marker = None
    for line in reversed(logcat.splitlines()):
        for m in MARKERS:
            if m in line:
                last_marker = m
                break
        if last_marker:
            break

    reg_after = count_backend(BACKEND_LOG, "register_ok")
    me_after = count_backend(BACKEND_LOG, 'GET /v1/auth/me')

    report = {
        "device": DEVICE,
        "test": "AUTH-001 cold launch",
        "homeDetectedMs": home_ms,
        "tryAgainTapped": try_again_tapped,
        "tryAgainAtMs": try_again_ms,
        "finalScreen": screen_state(dump_ui()),
        "logcatMarkers": markers,
        "lastMarkerSeen": last_marker,
        "backendRegisterOkDelta": reg_after - reg_before,
        "backendMeDelta": me_after - me_before,
        "timelineTail": timeline[-5:],
        "auth001Green": home_ms is not None and home_ms < 60000,
    }
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
