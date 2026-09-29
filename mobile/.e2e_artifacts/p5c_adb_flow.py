#!/usr/bin/env python3
"""ADB UI helpers for 5C device proof (no secrets)."""
import re
import subprocess
import sys
import time
from typing import Optional

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "RF8R40ZQ1JH"
UI = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts/p5c_proof_ui.xml"


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEVICE, *args])


def dump() -> str:
    adb("shell", "uiautomator", "dump", "/sdcard/p5c_ui.xml")
    subprocess.check_call(
        ["adb", "-s", DEVICE, "pull", "/sdcard/p5c_ui.xml", UI]
    )
    return open(UI, encoding="utf-8").read()


def tap_desc(needle: str, xml: Optional[str] = None) -> bool:
    t = xml or dump()
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        t,
    ):
        desc = m.group(1).replace("&#10;", " ")
        if needle.lower() in desc.lower():
            x1, y1, x2, y2 = map(int, m.groups()[1:])
            adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            return True
    return False


def tap_home_ride() -> None:
    adb("shell", "input", "tap", "540", "375")


def main() -> None:
    adb("shell", "appops", "set", "com.ora.ora", "android:mock_location", "allow")
    adb(
        "shell",
        "cmd",
        "location",
        "providers",
        "add-test-provider",
        "gps",
        "--supportsAltitude",
        "--supportsSpeed",
        "--supportsBearing",
    )
    adb(
        "shell",
        "cmd",
        "location",
        "providers",
        "set-test-provider-enabled",
        "gps",
        "true",
    )
    adb(
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
    )
    xml = dump()
    if "Where are you headed" not in xml and "Ride request" not in xml:
        adb("shell", "input", "keyevent", "KEYCODE_BACK")
        time.sleep(2)
    if "Where are you headed" in xml or "Set pickup" in xml:
        tap_home_ride()
    elif "Use current location" not in xml:
        tap_home_ride()
    time.sleep(3)
    dump()
    tap_desc("Use current location")
    time.sleep(4)
    xml = dump()
    tap_desc("Confirm pickup", xml)
    time.sleep(2)
    xml = dump()
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    )
    dest = eds[-1] if eds else None
    if dest:
        x1, y1, x2, y2 = map(int, dest)
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(1)
    for _ in range(40):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    adb("shell", "input", "text", "Liberty%sMarket%sLahore")
    time.sleep(6)
    xml = dump()
    if not tap_desc("Gulberg", xml):
        tap_desc("Liberty", xml)
    time.sleep(3)
    xml = dump()
    tap_desc("Confirm destination", xml)
    time.sleep(2)
    tap_desc("Continue", xml)
    time.sleep(3)
    xml = dump()
    tap_desc("Trio", xml)
    time.sleep(2)
    xml = dump()
    tap_desc("Continue", xml)
    time.sleep(5)
    xml = dump()
    tap_desc("Retry pricing", xml)
    time.sleep(10)
    dump()
    png = subprocess.check_output(["adb", "-s", DEVICE, "exec-out", "screencap", "-p"])
    open(
        "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts/p5c_proof_after_pricing.png",
        "wb",
    ).write(png)


if __name__ == "__main__":
    main()
