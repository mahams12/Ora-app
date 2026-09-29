#!/usr/bin/env python3
"""Two-actor QA automation — emulator passenger, Samsung driver. Ops only."""
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Optional

PASSENGER = "emulator-5554"
DRIVER = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ROOT = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
UI_E = f"{ROOT}/qa_emulator_ui.xml"
UI_D = f"{ROOT}/qa_samsung_ui.xml"


def adb(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, *args])


def dump(dev: str, path: str) -> str:
    adb(dev, "shell", "uiautomator", "dump", "/sdcard/qa_ui.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/qa_ui.xml", path])
    return open(path, encoding="utf-8").read()


def tap_contains(dev: str, needle: str, t: str, exclude: Optional[str] = None) -> bool:
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    ):
        desc = m.group(1).replace("&#10;", " | ").replace("&amp;", "&")
        if exclude and exclude in desc:
            continue
        if needle in desc:
            x1, y1, x2, y2 = map(int, m.groups()[1:])
            adb(dev, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def prep_gps(dev: str) -> None:
    subprocess.call(["adb", "-s", dev, "shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION"])
    subprocess.call(["adb", "-s", dev, "shell", "appops", "set", PKG, "android:mock_location", "allow"])
    subprocess.call(
        ["adb", "-s", dev, "shell", "cmd", "location", "providers", "add-test-provider", "gps",
         "--supportsAltitude", "--supportsSpeed", "--supportsBearing"],
        stderr=subprocess.DEVNULL,
    )
    subprocess.call(["adb", "-s", dev, "shell", "cmd", "location", "providers", "set-test-provider-enabled", "gps", "true"])
    subprocess.call(
        ["adb", "-s", dev, "shell", "cmd", "location", "providers", "set-test-provider-location",
         "gps", "--location", "31.5204,74.3587", "--accuracy", "5"],
    )


def main() -> None:
    metrics: dict = {"start_utc": datetime.now(timezone.utc).isoformat()}

    prep_gps(PASSENGER)
    adb(PASSENGER, "shell", "am", "force-stop", PKG)
    adb(PASSENGER, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(6)
    t = dump(PASSENGER, UI_E)
    if "Where are you headed" not in t and ("Send code" in t or "Phone number" in t):
        adb(PASSENGER, "shell", "input", "tap", "640", "1200")
        adb(PASSENGER, "shell", "input", "text", "+923012345678")
        adb(PASSENGER, "shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        tap_contains(PASSENGER, "Send code", dump(PASSENGER, UI_E))
        time.sleep(6)
        adb(PASSENGER, "shell", "input", "tap", "640", "500")
        adb(PASSENGER, "shell", "input", "text", "123456")
        tap_contains(PASSENGER, "Verify", dump(PASSENGER, UI_E))
        time.sleep(10)

    tap_contains(PASSENGER, "Where are you headed", dump(PASSENGER, UI_E)) or adb(PASSENGER, "shell", "input", "tap", "640", "400")
    time.sleep(2)
    tap_contains(PASSENGER, "Use current location", dump(PASSENGER, UI_E))
    time.sleep(3)
    tap_contains(PASSENGER, "Confirm pickup | Confirm pickup", dump(PASSENGER, UI_E), exclude="destination to continue")
    time.sleep(2)
    t = dump(PASSENGER, UI_E)
    eds = re.findall(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        adb(PASSENGER, "shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        time.sleep(1)
        for _ in range(35):
            adb(PASSENGER, "shell", "input", "keyevent", "KEYCODE_DEL")
        adb(PASSENGER, "shell", "input", "text", "Liberty%sMarket%sLahore")
        time.sleep(5)
        tap_contains(PASSENGER, "Gulberg", dump(PASSENGER, UI_E)) or tap_contains(PASSENGER, "Liberty Market", dump(PASSENGER, UI_E))
        time.sleep(3)
    tap_contains(PASSENGER, "Confirm destination | Confirm destination", dump(PASSENGER, UI_E))
    time.sleep(2)
    tap_contains(PASSENGER, "Continue | Continue", dump(PASSENGER, UI_E))
    time.sleep(8)
    t = dump(PASSENGER, UI_E)
    if "Select a ride" not in t:
        print("FAIL passenger review")
        sys.exit(1)
    tap_contains(PASSENGER, "Easy", t) or tap_contains(PASSENGER, "Trio,", t)
    time.sleep(2)
    t0 = time.time()
    tap_contains(PASSENGER, "Retry pricing", dump(PASSENGER, UI_E))
    time.sleep(18)
    metrics["pricing_latency_s"] = round(time.time() - t0, 2)
    t = dump(PASSENGER, UI_E)
    t1 = time.time()
    if not (tap_contains(PASSENGER, "Request Easy", t) or tap_contains(PASSENGER, "Request Trio", t)):
        print("FAIL submit")
        sys.exit(1)
    time.sleep(10)
    metrics["ride_submit_s"] = round(time.time() - t1, 2)
    metrics["passenger_ready"] = "Waiting for offers" in dump(PASSENGER, UI_E)

    prep_gps(DRIVER)
    adb(DRIVER, "shell", "am", "force-stop", PKG)
    adb(DRIVER, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(6)
    t = dump(DRIVER, UI_D)
    if "Earn on ORA" in t:
        tap_contains(DRIVER, "Earn on ORA", t)
        time.sleep(3)
    tap_contains(DRIVER, "Open ride requests", dump(DRIVER, UI_D)) or tap_contains(DRIVER, "Open ride", dump(DRIVER, UI_D))
    time.sleep(5)
    t0 = time.time()
    adb(DRIVER, "shell", "input", "swipe", "540", "600", "540", "1400", "500")
    time.sleep(8)
    metrics["driver_refresh_s"] = round(time.time() - t0, 2)
    dump(DRIVER, UI_D)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
