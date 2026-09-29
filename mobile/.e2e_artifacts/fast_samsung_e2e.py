#!/usr/bin/env python3
"""Fast full E2E on one Samsung."""
from __future__ import annotations

import json
import subprocess
import sys
import time

import driver_offer_gate as g

DEV = "RF8R40ZQ1JH"
g.P = g.D = DEV


def login(local: str, otp: str) -> None:
    subprocess.call(["adb", "-s", DEV, "shell", "input", "keyevent", "KEYCODE_WAKEUP"])
    subprocess.call(["adb", "-s", DEV, "shell", "am", "force-stop", "com.ora.ora"])
    subprocess.call(
        ["adb", "-s", DEV, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(5)
    t = g.pull(DEV, f"{g.ART}/fast_login.xml")
    if "Phone number" not in t and "Send verification code" not in t:
        return
    g.tap(DEV, 540, 1364)
    for _ in range(22):
        g.sh(DEV, "input", "keyevent", "67")
    g.sh(DEV, "input", "text", local)
    g.sh(DEV, "input", "keyevent", "4")
    time.sleep(0.5)
    for n in g.parse_nodes(g.pull(DEV, f"{g.ART}/fast_send.xml")):
        if "Send code" in n["desc"] or "Send verification code" in n["desc"]:
            g.tap_node(DEV, n)
            break
    time.sleep(8)
    g.tap(DEV, 540, 610)
    g.sh(DEV, "input", "text", otp)
    for n in g.parse_nodes(g.pull(DEV, f"{g.ART}/fast_ver.xml")):
        if n["desc"].startswith("Verify"):
            g.tap_node(DEV, n)
            break
    for _ in range(15):
        time.sleep(2)
        t = g.pull(DEV, f"{g.ART}/fast_post.xml")
        if "com.ora.ora" in t and ("Where are you headed" in t or "Open ride" in t or "Earn on ORA" in t):
            return


def main() -> None:
    subprocess.check_call(["adb", "-s", DEV, "reverse", "tcp:8081", "tcp:8080"])
    login("03012345678", "123456")
    subprocess.call(
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
        ]
    )
    subprocess.call(
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
        ]
    )
    subprocess.call(
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
        ]
    )
    before = g.tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"]
    rid = g.create_passenger_ride()
    ride = g.tsx("e2e_fetch_latest_ride.ts")["rides"][0]
    R = {
        "rideId": rid,
        "freshRide": ride["createdAt"] > before,
        "passengerOfferMinor": g.tsx("e2e_ride_snapshot.ts", rid)["ride"].get("passengerOfferMinor"),
    }
    login("03012345677", "000000")
    t = g.driver_open_rides_screen()
    R["driverDiscovered"] = "Liberty" in t or "Current location" in t
    if not R["driverDiscovered"]:
        print(json.dumps(R, indent=2))
        sys.exit(2)
    opened, meta = g.try_open_offer_sheet(t)
    R["respondOpenedSheet"] = opened
    R["respondMeta"] = meta
    if not opened:
        print(json.dumps(R, indent=2))
        sys.exit(3)
    g.submit_offer()
    R["offerCount"] = len(g.tsx("e2e_ride_snapshot.ts", rid).get("offers") or [])
    login("03012345678", "123456")
    subprocess.call(
        ["adb", "-s", DEV, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(6)
    sel = False
    for _ in range(12):
        tp = g.pull(DEV, f"{g.ART}/fast_psel.xml")
        if "Select" in tp:
            for n in g.parse_nodes(tp):
                if n["desc"].startswith("Select"):
                    g.tap_node(DEV, n)
                    sel = True
                    break
            break
        time.sleep(3)
    R["passengerSelect"] = sel
    login("03012345677", "000000")
    subprocess.call(
        ["adb", "-s", DEV, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(5)
    for n in g.parse_nodes(g.pull(DEV, f"{g.ART}/fast_d0.xml")):
        if n["desc"].startswith("Open ride"):
            g.tap_node(DEV, n)
            break
    time.sleep(4)
    for label in ("Mark en route", "Mark arrived", "Start ride", "Complete ride"):
        t = g.pull(DEV, f"{g.ART}/fast_prog.xml")
        for n in g.parse_nodes(t):
            if n["desc"].startswith(label):
                g.tap_node(DEV, n)
                time.sleep(6)
                break
    t = g.pull(DEV, f"{g.ART}/fast_close.xml")
    for n in g.parse_nodes(t):
        if n["desc"].startswith("Close ride"):
            g.tap_node(DEV, n)
            time.sleep(5)
            R["closed"] = True
            break
    R["finalState"] = g.tsx("e2e_ride_snapshot.ts", rid)["ride"].get("state")
    R["verdict"] = "GREEN" if R.get("offerCount") == 1 and sel and R.get("finalState") in (
        "RIDE_CLOSED",
        "COMPLETED",
        "RIDE_COMPLETED",
    ) else ("YELLOW" if sel else "RED")
    print(json.dumps(R, indent=2))


if __name__ == "__main__":
    main()
