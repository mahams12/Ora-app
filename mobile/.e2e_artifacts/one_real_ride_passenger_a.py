#!/usr/bin/env python3
"""Device A passenger path to Review + pricing (ops)."""
import re
import subprocess
import sys
import time
from pathlib import Path

D = "RF8R40ZQ1JH"
ART = Path(__file__).resolve().parent
UI = ART / "one_ride_ui.xml"
LOG = ART / "p5c_backend_8081.log"
MARKER = "ORA-E2E-20260923-1648"


def adb(*a):
    subprocess.check_call(["adb", "-s", D, *a])


def dump() -> str:
    adb("shell", "uiautomator", "dump", "/sdcard/one_ride.xml")
    subprocess.check_call(["adb", "-s", D, "pull", "/sdcard/one_ride.xml", str(UI)])
    return UI.read_text(encoding="utf-8")


def tap_desc(xml: str, needle: str) -> bool:
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    ):
        desc = m.group(1).replace("&#10;", " ")
        if needle.lower() in desc.lower():
            x1, y1, x2, y2 = map(int, m.groups()[1:])
            adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def log_tail(since_marker: bool = True) -> str:
    text = LOG.read_text(encoding="utf-8", errors="replace")
    if since_marker:
        i = text.rfind(MARKER)
        return text[i:] if i >= 0 else text
    return text


def main() -> None:
    # Location prep (Samsung usually allows)
    for cmd in (
        ["shell", "pm", "grant", "com.ora.ora", "android.permission.ACCESS_FINE_LOCATION"],
        ["shell", "pm", "grant", "com.ora.ora", "android.permission.ACCESS_COARSE_LOCATION"],
        ["shell", "appops", "set", "com.ora.ora", "android:mock_location", "allow"],
    ):
        subprocess.run(["adb", "-s", D, *cmd], check=False)
    subprocess.run(
        [
            "adb",
            "-s",
            D,
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
        check=False,
    )
    subprocess.run(
        [
            "adb",
            "-s",
            D,
            "shell",
            "cmd",
            "location",
            "providers",
            "set-test-provider-enabled",
            "gps",
            "true",
        ],
        check=False,
    )
    subprocess.run(
        [
            "adb",
            "-s",
            D,
            "shell",
            "cmd",
            "location",
            "providers",
            "set-test-provider-location",
            "gps",
            "--location",
            "31.5204,74.3587",
            "--accuracy",
            "5",
        ],
        check=False,
    )

    adb("shell", "am", "force-stop", "com.ora.ora")
    adb("shell", "monkey", "-p", "com.ora.ora", "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(8)
    for _ in range(10):
        xml = dump()
        if "Where are you headed" in xml:
            break
        if "Signing you in" in xml:
            time.sleep(8)
            continue
        if tap_desc(xml, "Try again"):
            time.sleep(8)
            continue
        time.sleep(3)

    t_home = time.time()
    tap_desc(dump(), "Where are you headed") or adb("shell", "input", "tap", "540", "375")
    time.sleep(3)
    tap_desc(dump(), "Use current location")
    time.sleep(4)
    tap_desc(dump(), "Confirm pickup")
    time.sleep(2)
    xml = dump()
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    )
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(1)
    for _ in range(35):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    t_places = time.time()
    adb("shell", "input", "text", "Liberty%sMarket%sLahore")
    time.sleep(7)
    xml = dump()
    if "Location lookup isn't available" in xml:
        print("PLACES_FAIL"); sys.exit(2)
    tap_desc(xml, "Gulberg") or tap_desc(xml, "Liberty Market")
    time.sleep(3)
    tap_desc(dump(), "Confirm destination")
    time.sleep(2)
    tap_desc(dump(), "Continue")
    time.sleep(4)
    # Category / review — tap Trio then Continue to review pricing
    xml = dump()
    tap_desc(xml, "Trio")
    time.sleep(2)
    tap_desc(dump(), "Continue")
    time.sleep(2)
    t_price = time.time()
    xml = dump()
    if tap_desc(xml, "Retry pricing"):
        time.sleep(18)
        xml = dump()
    places_ms = int((time.time() - t_places) * 1000)
    price_ms = int((time.time() - t_price) * 1000)
    tail = log_tail()
    has_begin = "pricing_estimate_begin" in tail
    has_ok = "pricing_estimate_ok" in tail and "trio" in tail
    print("places_ms", places_ms)
    print("pricing_wait_ms", price_ms)
    print("pricing_begin_after_marker", has_begin)
    print("pricing_ok_trio_after_marker", has_ok)
    print("ui_has_rs", "Rs" in xml or "270" in xml)
    for m in re.finditer(r'content-desc="([^"]{0,120})"', xml):
        if "Rs" in m.group(1) or "Request" in m.group(1) or "Retry" in m.group(1):
            print("UI:", m.group(1)[:120])
    if not has_ok:
        print("PRICING_GATE_FAIL"); sys.exit(3)
    # Request ride once
    t_create = time.time()
    if not tap_desc(dump(), "Request Trio"):
        tap_desc(dump(), "Request")
    time.sleep(8)
    tail2 = log_tail()
    ride_ids = re.findall(r'"rideId":"([a-f0-9-]{36})"', tail2)
    print("create_ms", int((time.time() - t_create) * 1000))
    print("ride_ids_after_marker", ride_ids[-3:] if ride_ids else [])
    dump()
    print("DONE passenger script")


if __name__ == "__main__":
    main()
