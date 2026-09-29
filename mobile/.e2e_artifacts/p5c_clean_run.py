#!/usr/bin/env python3
"""One controlled 5C device flow — ops only."""
import re
import subprocess
import sys
import time
from typing import Optional

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "RF8R40ZQ1JH"
PKG = "com.ora.ora"
UI = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts/p5c_clean_ui.xml"
LOG = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts/p5c_backend_8081.log"


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEVICE, *args])


def dump() -> str:
    for attempt in range(5):
        try:
            subprocess.check_call(
                ["adb", "-s", DEVICE, "shell", "uiautomator", "dump", "/sdcard/p5c_clean.xml"],
                timeout=30,
            )
            subprocess.check_call(
                ["adb", "-s", DEVICE, "pull", "/sdcard/p5c_clean.xml", UI],
                timeout=30,
            )
            return open(UI, encoding="utf-8").read()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            time.sleep(2 + attempt)
    raise RuntimeError("uiautomator dump failed")


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


def wait_desc(needle: str, tries: int = 25) -> bool:
    for _ in range(tries):
        t = dump()
        if needle in t:
            return True
        time.sleep(2)
    return False


def auth_if_needed() -> None:
    for _ in range(6):
        t = dump()
        if "Signing you in" in t:
            tap_desc("Try again")
            time.sleep(8)
        elif "Send code" in t or "Phone number" in t:
            adb("shell", "input", "tap", "540", "1364")
            adb("shell", "input", "text", "+923012345678")
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            time.sleep(1)
            tap_desc("Send code") or adb("shell", "input", "tap", "540", "1640")
            time.sleep(8)
            adb("shell", "input", "tap", "540", "610")
            adb("shell", "input", "text", "123456")
            tap_desc("Verify") or adb("shell", "input", "tap", "540", "810")
            time.sleep(12)
        elif "Where are you headed" in t:
            return
        else:
            time.sleep(2)


def location_prep() -> None:
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION")
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION")
    adb("shell", "settings", "put", "secure", "location_mode", "3")
    adb("shell", "appops", "set", PKG, "android:mock_location", "allow")
    subprocess.call(
        [
            "adb",
            "-s",
            DEVICE,
            "shell",
            "cmd",
            "location",
            "providers",
            "add-test-provider",
            "gps",
            "--supportsAltitude",
            "--supportsSpeed",
            "--supportsBearing",
        ]
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


def trio_selected(xml: str) -> bool:
    # Semantics: label="Trio, Rickshaw, ..." selected="true"
    return bool(
        re.search(
            r'label="Trio,[^"]*"[^>]*selected="true"',
            xml,
        )
        or re.search(
            r'selected="true"[^>]*label="Trio,',
            xml,
        )
    )


def main() -> None:
    location_prep()
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(6)
    auth_if_needed()
    tap_desc("Where are you headed") or adb("shell", "input", "tap", "540", "375")
    time.sleep(3)
    dump()
    tap_desc("Use current location")
    time.sleep(4)
    dump()
    tap_desc("Confirm pickup")
    time.sleep(2)
    t = dump()
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        t,
    )
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(1)
    for _ in range(35):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    adb("shell", "input", "text", "Liberty%sMarket%sLahore")
    time.sleep(6)
    dump()
    tap_desc("Gulberg") or tap_desc("Liberty Market")
    time.sleep(3)
    dump()
    tap_desc("Confirm destination")
    time.sleep(2)
    dump()
    tap_desc("Continue")
    time.sleep(6)
    if not wait_desc("Select a ride", 15):
        print("FAIL: review not reached")
        sys.exit(1)
    t = dump()
    tap_desc("Trio, Rickshaw") or tap_desc("Trio,")
    time.sleep(3)
    t = dump()
    print("trio_selected_ui", trio_selected(t))
    if not trio_selected(t):
        # scroll category list
        adb("shell", "input", "swipe", "540", "1800", "540", "900", "400")
        time.sleep(1)
        t = dump()
        tap_desc("Trio, Rickshaw") or tap_desc("Trio,")
        time.sleep(2)
        t = dump()
        print("trio_selected_ui_after_scroll", trio_selected(t))
    marker = f"=== P5C_RETRY_ATTEMPT {time.strftime('%Y-%m-%dT%H:%M:%S%z')} ==="
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(marker + "\n")
    print("MARKER_WRITTEN", marker)
    if not tap_desc("Retry pricing"):
        print("FAIL: Retry pricing control not found")
        sys.exit(1)
    time.sleep(18)
    dump()
    png = subprocess.check_output(["adb", "-s", DEVICE, "exec-out", "screencap", "-p"])
    open(
        "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts/p5c_clean_after_retry.png",
        "wb",
    ).write(png)


if __name__ == "__main__":
    main()
