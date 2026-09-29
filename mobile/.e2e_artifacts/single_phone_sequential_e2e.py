#!/usr/bin/env python3
"""One physical device: passenger → driver → passenger → driver progression."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

DEV = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ART = Path(__file__).resolve().parent
BACKEND = ART.parent.parent / "backend/auth-service"
R: dict = {"started": datetime.now(timezone.utc).isoformat(), "device": DEV}


def env():
    return {
        **dict(subprocess.os.environ),
        "GOOGLE_APPLICATION_CREDENTIALS": str(BACKEND / "secrets/service-account.json"),
    }


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEV, *args])


def sh(*args: str) -> str:
    return subprocess.check_output(["adb", "-s", DEV, "shell", *args], stderr=subprocess.STDOUT).decode(
        "utf-8", errors="replace"
    )


def dump(tag: str) -> str:
    path = ART / f"seq_{tag}.xml"
    for _ in range(8):
        sh("uiautomator", "dump", "/sdcard/seq_ui.xml")
        subprocess.check_call(["adb", "-s", DEV, "pull", "/sdcard/seq_ui.xml", str(path)])
        text = path.read_text(encoding="utf-8")
        if "hierarchy" in text and len(text) > 400:
            return text
        time.sleep(1.2)
    return text


def nodes(t: str) -> list[dict]:
    out: list[dict] = []
    for m in re.finditer(r"<node ([^/]+)/>", t):
        attrs = m.group(1)

        def attr(name: str) -> str:
            mm = re.search(rf'{name}="([^"]*)"', attrs)
            return mm.group(1) if mm else ""

        b = attr("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        out.append(
            {
                "desc": attr("content-desc").replace("&#10;", "\n"),
                "clickable": attr("clickable") == "true",
                "enabled": attr("enabled") == "true",
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return out


def tap_node(n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def tap_desc(t: str, needle: str, *, enabled_only: bool = False) -> bool:
    for n in nodes(t):
        if needle not in n["desc"]:
            continue
        if enabled_only and not n["enabled"]:
            continue
        tap_node(n)
        return True
    return False


def launch() -> None:
    sh("input", "keyevent", "KEYCODE_WAKEUP")
    adb("shell", "am", "force-stop", PKG)
    subprocess.check_call(
        ["adb", "-s", DEV, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(6)


def clear_phone_field() -> None:
    sh("input", "tap", "540", "1364")
    time.sleep(0.4)
    for _ in range(28):
        sh("input", "keyevent", "67")


def login(local_phone: str, otp: str, *, role: str) -> None:
    launch()
    for _ in range(15):
        t = dump("login")
        if "Signing you in" in t:
            time.sleep(3)
            continue
        break
    if role == "passenger" and "Where are you headed" in t:
        return
    if role == "driver" and ("Open ride requests" in t or "Earn on ORA" in t):
        return
    if "Phone number" not in t and "Send verification code" not in t:
        time.sleep(4)
        t = dump("login2")
    clear_phone_field()
    sh("input", "text", local_phone)
    sh("input", "keyevent", "4")
    time.sleep(0.5)
    tap_desc(dump("send"), "Send code") or tap_desc(dump("send2"), "Send verification code")
    time.sleep(10)
    sh("input", "tap", "540", "610")
    sh("input", "text", otp)
    time.sleep(0.5)
    tap_desc(dump("verify"), "Verify")
    for _ in range(20):
        time.sleep(2)
        t = dump("post_auth")
        if role == "passenger" and "Where are you headed" in t:
            return
        if role == "driver" and ("Open ride requests" in t or "Earn on ORA" in t):
            return


def set_lahore_gps() -> None:
    for cmd in (
        ("pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION"),
        ("pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION"),
        ("appops", "set", PKG, "android:mock_location", "allow"),
    ):
        subprocess.run(["adb", "-s", DEV, "shell", *cmd], check=False)
    subprocess.run(
        [
            "adb",
            "-s",
            DEV,
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
            DEV,
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
            DEV,
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


def tsx(script: str, *args: str) -> dict:
    out = subprocess.check_output(
        [str(BACKEND / "node_modules/.bin/tsx"), str(BACKEND / "scripts" / script), *args],
        cwd=str(BACKEND),
        env=env(),
    )
    return json.loads(out.decode())


def wait_review() -> str:
    for _ in range(20):
        t = dump("rev")
        if "Select a ride" in t or "Retry pricing" in t or "Request Easy" in t:
            return t
        if tap_desc(t, "Continue", enabled_only=True):
            time.sleep(4)
            continue
        sh("input", "tap", "540", "1674")
        time.sleep(3)
    return dump("rev_fail")


def passenger_create() -> str:
    login("03012345678", "123456", role="passenger")
    set_lahore_gps()
    launch()
    t = dump("p_home")
    tap_desc(t, "Where are you headed") or sh("input", "tap", "540", "375")
    time.sleep(3)
    tap_desc(dump("pick"), "Use current location")
    time.sleep(4)
    tap_desc(dump("pick2"), "Confirm pickup")
    time.sleep(2)
    t = dump("dest")
    eds = re.findall(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        for _ in range(35):
            sh("input", "keyevent", "67")
        sh("input", "text", "Liberty%Market%Lahore")
    time.sleep(8)
    tap_desc(dump("sug"), "Liberty Market") or tap_desc(dump("sug2"), "Gulberg")
    time.sleep(4)
    for _ in range(6):
        if tap_desc(dump("conf"), "Confirm destination"):
            time.sleep(3)
            break
        sh("input", "swipe", "540", "1200", "540", "700", "400")
        time.sleep(1)
    t = wait_review()
    tap_desc(t, "Easy,") or tap_desc(t, "Trio,") or tap_desc(t, "Zip,")
    time.sleep(2)
    tap_desc(dump("city"), "Lahore") or tap_desc(dump("city2"), "lahore")
    time.sleep(1)
    for _ in range(8):
        t = dump("price")
        if tap_desc(t, "Retry pricing"):
            break
        sh("input", "swipe", "540", "1800", "540", "800", "400")
        time.sleep(1)
    time.sleep(26)
    t = dump("price2")
    if "Rs " not in t and "Request Easy" not in t:
        raise RuntimeError("pricing not loaded")
    tap_desc(t, "Request Easy") or tap_desc(t, "Request Trio") or tap_desc(t, "Request ")
    time.sleep(10)
    t = dump("wait")
    if "Waiting for offers" not in t:
        raise RuntimeError("not on waiting for offers")
    R["gates"] = {"ride_creation": "GREEN"}
    return tsx("e2e_fetch_latest_ride.ts")["rides"][0]["rideId"]


def driver_to_open_rides() -> str:
    login("03012345677", "000000", role="driver")
    launch()
    for _ in range(10):
        t = dump("d_nav")
        if "Liberty" in t and ("Respond" in t or "Current location" in t):
            return t
        if "Earn on ORA" in t:
            tap_desc(t, "Earn on ORA")
            time.sleep(4)
            continue
        if tap_desc(t, "Open ride requests") or tap_desc(t, "Open ride"):
            time.sleep(5)
            continue
        sh("input", "keyevent", "4")
        time.sleep(2)
    return dump("d_open")


def driver_offer(t: str) -> None:
    cards = [n for n in nodes(t) if n["clickable"] and "Respond" in n["desc"]]
    if not cards:
        cards = [n for n in nodes(t) if n["clickable"] and ("Liberty" in n["desc"] or "Rs " in n["desc"])]
    if not cards:
        raise RuntimeError("no ride card on driver list")
    card = min(cards, key=lambda n: (n["bounds"][2] - n["bounds"][0]) * (n["bounds"][3] - n["bounds"][1]))
    x1, y1, x2, y2 = card["bounds"]
    for cx, cy in ((x1 + x2) // 2, y2 - 45), ((x1 + x2) // 2, (y1 + y2) // 2):
        sh("input", "tap", str(cx), str(cy))
        time.sleep(3)
        t2 = dump("sheet")
        if any(s in t2 for s in ("Submit offer", "Accept passenger price")):
            tap_desc(t2, "Accept passenger price")
            time.sleep(2)
            tap_desc(dump("submit"), "Submit offer")
            time.sleep(8)
            R["gates"]["driver_offer"] = "GREEN"
            return
    raise RuntimeError("offer sheet did not open")


def passenger_select() -> None:
    login("03012345678", "123456", role="passenger")
    launch()
    t = dump("p_offers")
    for _ in range(15):
        if "Select" in t:
            break
        time.sleep(3)
        t = dump("p_offers_w")
    if "Select" not in t:
        raise RuntimeError("passenger Select not visible")
    tap_desc(t, "Select")
    time.sleep(10)
    t2 = dump("assigned")
    R["gates"]["assignment"] = (
        "GREEN" if any(s in t2 for s in ("Assigned", "En route", "Active", "DRIVER_ASSIGNED")) else "YELLOW"
    )


def driver_progress() -> None:
    login("03012345677", "000000", role="driver")
    launch()
    tap_desc(dump("d_or"), "Open ride requests") or tap_desc(dump("d_or2"), "Open ride")
    time.sleep(4)
    for label in ("Mark en route", "Mark arrived", "Start ride", "Complete ride"):
        t = dump(f"prog_{label[:6]}")
        if label not in t:
            continue
        tap_desc(t, label)
        time.sleep(6)
    t = dump("close")
    if "Close ride" in t:
        tap_desc(t, "Close ride")
        time.sleep(5)
        R["gates"]["RIDE_CLOSED"] = "GREEN"


def main() -> None:
    adb("reverse", "tcp:8081", "tcp:8080")
    before = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"]
    rid = passenger_create()
    R["rideId"] = rid
    R["freshRide"] = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"] > before
    t = driver_to_open_rides()
    R["driverDiscovered"] = "Liberty" in t or "Current location" in t
    if not R["driverDiscovered"]:
        print(json.dumps(R, indent=2))
        sys.exit(2)
    driver_offer(t)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    R["offerCount"] = len(snap.get("offers") or [])
    passenger_select()
    driver_progress()
    snap2 = tsx("e2e_ride_snapshot.ts", rid)
    R["finalStatus"] = snap2.get("ride", {}).get("status")
    R["finished"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(R, indent=2))


if __name__ == "__main__":
    main()
