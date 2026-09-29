#!/usr/bin/env python3
"""Two-device physical E2E retest (ops only — no product code)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

ART = Path(__file__).resolve().parent
ROOT = ART.parent.parent
LOG = ART / "p5c_backend_8081.log"
REPORT = ART / "two_device_e2e_retest_report.json"
CORR = "ORA-E2E-20260923-1608"

PASSENGER_DEVICE = "RF8R40ZQ1JH"
DRIVER_DEVICE = "H6YLNBV8MF45Z94L"
PASSENGER_PHONE = "+923001234567"
DRIVER_PHONE = "+923012345678"
OTP = "123456"
PKG = "com.ora.ora"

# Lahore test GPS (established P5C procedure)
GPS = "31.5204,74.3587"


@dataclass
class Metrics:
    rows: list[dict] = field(default_factory=list)

    def add(self, metric: str, device: str, ms: Optional[int], note: str = "") -> None:
        band = classify(ms)
        self.rows.append(
            {
                "metric": metric,
                "device": device,
                "ms": ms,
                "classification": band,
                "note": note,
            }
        )


def classify(ms: Optional[int]) -> str:
    if ms is None:
        return "NOT_MEASURED"
    if ms < 300:
        return "FAST"
    if ms < 1000:
        return "GOOD"
    if ms < 2000:
        return "NOTICEABLE"
    if ms < 5000:
        return "SLOW"
    return "VERY_SLOW"


def adb(device: str, *args: str, capture: bool = False) -> str:
    r = subprocess.run(
        ["adb", "-s", device, *args],
        check=False,
        capture_output=capture,
        text=True,
    )
    if capture:
        return r.stdout or ""
    if r.returncode != 0:
        raise subprocess.CalledProcessError(r.returncode, r.args)
    return ""


def dump(device: str, name: str) -> str:
    path = ART / name
    adb(device, "shell", "uiautomator", "dump", f"/sdcard/{name}")
    subprocess.check_call(["adb", "-s", device, "pull", f"/sdcard/{name}", str(path)])
    return path.read_text(encoding="utf-8")


def tap_desc(device: str, xml: str, needle: str) -> bool:
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    ):
        desc = m.group(1).replace("&#10;", " ")
        if needle.lower() in desc.lower():
            x1, y1, x2, y2 = map(int, m.groups()[1:])
            adb(device, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def wait_desc(device: str, needle: str, tries: int = 30, sleep_s: float = 2) -> tuple[bool, int]:
    t0 = time.time()
    for _ in range(tries):
        xml = dump(device, "e2e_ui.xml")
        if needle in xml:
            return True, int((time.time() - t0) * 1000)
        time.sleep(sleep_s)
    return False, int((time.time() - t0) * 1000)


def location_prep(device: str) -> None:
    for perm in (
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
    ):
        subprocess.run(
            ["adb", "-s", device, "shell", "pm", "grant", PKG, perm],
            check=False,
        )
    subprocess.run(
        ["adb", "-s", device, "shell", "settings", "put", "secure", "location_mode", "3"],
        check=False,
    )
    subprocess.run(
        ["adb", "-s", device, "shell", "appops", "set", PKG, "android:mock_location", "allow"],
        check=False,
    )
    for cmd in (
        [
            "shell",
            "cmd",
            "location",
            "providers",
            "add-test-provider",
            "gps",
            "--supportsAltitude",
            "--supportsSpeed",
            "--supportsBearing",
        ],
        ["shell", "cmd", "location", "providers", "set-test-provider-enabled", "gps", "true"],
        [
            "shell",
            "cmd",
            "location",
            "providers",
            "set-test-provider-location",
            "gps",
            "--location",
            GPS,
            "--accuracy",
            "5",
        ],
    ):
        subprocess.run(["adb", "-s", device, *cmd], check=False)


def login_phone(device: str, phone: str) -> None:
    adb(device, "shell", "am", "force-stop", PKG)
    adb(device, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)
    for _ in range(8):
        xml = dump(device, "e2e_login.xml")
        if "Where are you headed" in xml or "Open ride requests" in xml or "Driver" in xml:
            return
        if "Signing you in" in xml:
            time.sleep(6)
            continue
        if tap_desc(device, xml, "Try again"):
            time.sleep(8)
            continue
        if "Send code" in xml or "Phone number" in xml:
            adb(device, "shell", "input", "tap", "540", "1364")
            adb(device, "shell", "input", "text", phone.replace("+", "\\+"))
            adb(device, "shell", "input", "keyevent", "KEYCODE_BACK")
            time.sleep(1)
            tap_desc(device, xml, "Send code") or adb(device, "shell", "input", "tap", "540", "1640")
            time.sleep(8)
            adb(device, "shell", "input", "tap", "540", "610")
            adb(device, "shell", "input", "text", OTP)
            tap_desc(device, dump(device, "e2e_otp.xml"), "Verify") or adb(
                device, "shell", "input", "tap", "540", "810"
            )
            time.sleep(10)
            continue
        if "display name" in xml.lower() or "Your name" in xml:
            adb(device, "shell", "input", "tap", "540", "900")
            adb(device, "shell", "input", "text", "E2E%stest")
            tap_desc(device, dump(device, "e2e_onb.xml"), "Continue") or adb(
                device, "shell", "input", "tap", "540", "1200"
            )
            time.sleep(6)
            continue
        time.sleep(2)


def cold_to_home(device: str, label: str, metrics: Metrics) -> bool:
    adb(device, "shell", "am", "force-stop", PKG)
    adb(device, "logcat", "-c")
    start = adb(
        device,
        "shell",
        "am",
        "start",
        "-W",
        "-n",
        f"{PKG}/.MainActivity",
        capture=True,
    )
    wait_m = re.search(r"WaitTime:\s*(\d+)", start)
    activity_ms = int(wait_m.group(1)) if wait_m else None
    metrics.add(f"{label} activity cold start", device, activity_ms)
    ok, ms = wait_desc(device, "Where are you headed", tries=25)
    if not ok:
        ok, ms = wait_desc(device, "Open ride requests", tries=10)
    metrics.add(f"{label} cold → Home", device, ms if ok else None, "fail" if not ok else "")
    return ok


def passenger_compose(device: str, metrics: Metrics) -> bool:
    t0 = time.time()
    tap_desc(device, dump(device, "e2e_compose0.xml"), "Where are you headed") or adb(
        device, "shell", "input", "tap", "540", "375"
    )
    time.sleep(3)
    tap_desc(device, dump(device, "e2e_compose1.xml"), "Use current location")
    time.sleep(4)
    tap_desc(device, dump(device, "e2e_compose2.xml"), "Confirm pickup")
    time.sleep(2)
    xml = dump(device, "e2e_compose3.xml")
    if "Location lookup isn't available" in xml:
        metrics.add("Places search", device, None, "FAILED lookup unavailable")
        return False
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    )
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        adb(device, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(1)
    for _ in range(35):
        adb(device, "shell", "input", "keyevent", "KEYCODE_DEL")
    adb(device, "shell", "input", "text", "Liberty%sMarket%sLahore")
    t_places = time.time()
    time.sleep(6)
    xml = dump(device, "e2e_compose4.xml")
    if "Location lookup isn't available" in xml:
        metrics.add("Places search", device, int((time.time() - t_places) * 1000), "FAILED")
        return False
    tap_desc(device, xml, "Gulberg") or tap_desc(device, xml, "Liberty")
    metrics.add("Places search", device, int((time.time() - t_places) * 1000))
    time.sleep(3)
    tap_desc(device, dump(device, "e2e_compose5.xml"), "Confirm destination")
    time.sleep(2)
    tap_desc(device, dump(device, "e2e_compose6.xml"), "Continue")
    time.sleep(4)
    ok, ms = wait_desc(device, "Select a ride", tries=12)
    metrics.add("Home → Review", device, int((time.time() - t0) * 1000))
    if not ok:
        return False
    tap_desc(device, dump(device, "e2e_review.xml"), "Trio")
    time.sleep(3)
    t_pr = time.time()
    if tap_desc(device, dump(device, "e2e_review2.xml"), "Retry pricing"):
        time.sleep(15)
    xml = dump(device, "e2e_review3.xml")
    pricing_ok = "Rs" in xml or "270" in xml or "Estimated fare" in xml
    metrics.add("Pricing UI ready", device, int((time.time() - t_pr) * 1000), "" if pricing_ok else "no fare visible")
    return pricing_ok


def main() -> None:
    metrics = Metrics()
    results: dict = {"correlationId": CORR, "phases": {}, "metrics": []}

    with open(LOG, "a", encoding="utf-8") as f:
        f.write(f"\n=== {CORR} TWO_DEVICE_E2E_RETEST ===\n")

    for d in (PASSENGER_DEVICE, DRIVER_DEVICE):
        adb(d, "reverse", "tcp:8081", "tcp:8080")
        location_prep(d)

    # Auth
    login_phone(PASSENGER_DEVICE, PASSENGER_PHONE)
    login_phone(DRIVER_DEVICE, DRIVER_PHONE)
    p_ok = cold_to_home(PASSENGER_DEVICE, "Passenger", metrics)
    d_ok = cold_to_home(DRIVER_DEVICE, "Driver", metrics)
    results["phases"]["auth"] = {"passengerHome": p_ok, "driverHome": d_ok}
    if not (p_ok and d_ok):
        REPORT.write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(json.dumps(results, indent=2))
        sys.exit(1)

    compose_ok = passenger_compose(PASSENGER_DEVICE, metrics)
    results["phases"]["compose_pricing"] = {"ok": compose_ok}
    results["metrics"] = metrics.rows
    REPORT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))
    sys.exit(0 if compose_ok else 2)


if __name__ == "__main__":
    main()
