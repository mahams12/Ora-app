#!/usr/bin/env python3
"""Production release APK → Play Integrity → prod pricing (no adb reverse)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "mobile" / ".e2e_artifacts"
PKG = "com.ora.ora"
DEVICE = "RF8R40ZQ1JH"
APK = ROOT / "mobile/build/app/outputs/flutter-apk/app-release.apk"
REPORT = ART / "production_release_device_proof_report.json"
UI = ART / "prod_release_ui.xml"
LOG = ART / "prod_release_logcat.txt"
PROD_API = "https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/v1"


def adb(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["adb", "-s", DEVICE, *args],
        capture_output=True,
        text=True,
        check=False,
    )


def dump_ui() -> None:
    adb("shell", "uiautomator", "dump", "/sdcard/prod_ui.xml")
    adb("pull", "/sdcard/prod_ui.xml", str(UI))


def tap_desc(needle: str) -> bool:
    try:
        text = UI.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        text,
    ):
        desc = m.group(1).replace("&#10;", " ")
        if needle.lower() in desc.lower():
            x1, y1, x2, y2 = map(int, m.groups()[1:])
            adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def wait_desc(needle: str, tries: int = 40, delay: float = 2.0) -> bool:
    for _ in range(tries):
        dump_ui()
        if needle in UI.read_text(encoding="utf-8", errors="replace"):
            return True
        time.sleep(delay)
    return False


def main() -> int:
    ART.mkdir(parents=True, exist_ok=True)
    report: dict = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "device": DEVICE,
        "prod_api": PROD_API,
        "apk": str(APK),
    }

    if not APK.is_file():
        report["error"] = "missing_release_apk"
        REPORT.write_text(json.dumps(report, indent=2))
        print(json.dumps(report))
        return 2

    adb("reverse", "--remove-all")
    rev = adb("reverse", "--list").stdout.strip()
    report["adb_reverse"] = rev or "(none)"

    adb("install", "-r", str(APK))
    adb("logcat", "-c")
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)

    # Auth (Firebase test number — ops account)
    if wait_desc("Phone", tries=15):
        tap_desc("Phone") or tap_desc("Enter")
        time.sleep(0.5)
        adb("shell", "input", "text", "923012345678")
        time.sleep(0.5)
        tap_desc("Continue") or tap_desc("Send")
        time.sleep(2)
    if wait_desc("code", tries=20) or wait_desc("OTP", tries=5):
        adb("shell", "input", "text", "123456")
        time.sleep(1)
        tap_desc("Verify") or tap_desc("Continue")

    wait_desc("Home", tries=30) or wait_desc("Ride", tries=30)
    time.sleep(2)

    # Open ride compose / pricing
    tap_desc("Ride") or tap_desc("Request")
    time.sleep(2)
    tap_desc("Easy") or tap_desc("easy")
    time.sleep(3)

    # Wait for fare / distance UI hints
    pricing_ui = wait_desc("PKR", tries=25) or wait_desc("fare", tries=10)
    report["pricing_ui_seen"] = pricing_ui

    adb("logcat", "-d", "-v", "time", "*:I").stdout
    proc = adb("logcat", "-d", "-v", "time")
    LOG.write_text(proc.stdout, encoding="utf-8", errors="replace")
    log_lower = proc.stdout.lower()

    report["log_app_check_error"] = "app attestation failed" in log_lower or (
        "appcheck" in log_lower and "error" in log_lower
    )
    report["log_play_integrity"] = "playintegrity" in log_lower or "play integrity" in log_lower
    report["log_debug_token"] = "debug secret" in log_lower or "debug token" in log_lower
    report["log_app_check_required"] = "app_check_required" in log_lower

    dump_ui()
    ui = UI.read_text(encoding="utf-8", errors="replace") if UI.is_file() else ""
    report["ui_has_pkr"] = "PKR" in ui or "Rs" in ui
    report["ui_has_km"] = "km" in ui.lower()

    report["finished_at"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    ok = (
        report["adb_reverse"] in ("(none)", "")
        and not report.get("log_debug_token")
        and report.get("pricing_ui_seen") or report.get("ui_has_pkr")
    )
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
