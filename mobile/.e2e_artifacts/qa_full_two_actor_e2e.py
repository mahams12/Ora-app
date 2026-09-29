#!/usr/bin/env python3
"""Full two-actor E2E — emulator passenger, Samsung driver. Ops only."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

P = os.environ.get("ORA_E2E_PASSENGER", "emulator-5554")
D = os.environ.get("ORA_E2E_DRIVER", "RF8R40ZQ1JH")
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
REPORT: Dict[str, Any] = {"gates": {}, "timings": {}, "rideId": None, "offerId": None}


def adb(dev: str, *args: str) -> str:
    out = subprocess.check_output(["adb", "-s", dev, *args], stderr=subprocess.STDOUT)
    return out.decode("utf-8", errors="replace")


def shell(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, "shell", *args])


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/qa_{tag}_ui.xml"
    shell(dev, "uiautomator", "dump", "/sdcard/qa_ui.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/qa_ui.xml", path])
    return open(path, encoding="utf-8").read()


def nodes(t: str) -> List[Tuple[str, int, int]]:
    out: List[Tuple[str, int, int]] = []
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    ):
        desc = m.group(1).replace("&#10;", " | ").replace("&amp;", "&")
        x1, y1, x2, y2 = map(int, m.groups()[1:])
        out.append((desc, (x1 + x2) // 2, (y1 + y2) // 2))
    return out


def tap(dev: str, needle: str, t: str, exclude: Optional[str] = None) -> bool:
    for desc, cx, cy in nodes(t):
        if exclude and exclude in desc:
            continue
        if needle in desc:
            shell(dev, "input", "tap", str(cx), str(cy))
            return True
    return False


def continue_enabled(t: str) -> bool:
    m = re.search(
        r'content-desc="Continue[^"]*"[^>]*enabled="(true|false)"',
        t,
    )
    return bool(m and m.group(1) == "true")


def wait_for(dev: str, needle: str, tries: int = 30, pause: float = 2.0, tag: str = "w") -> str:
    for _ in range(tries):
        t = dump(dev, tag)
        if needle in t:
            return t
        time.sleep(pause)
    return dump(dev, tag)


def launch(dev: str) -> None:
    shell(dev, "am", "force-stop", PKG)
    subprocess.check_call(
        ["adb", "-s", dev, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(5)


def auth(dev: str, phone: str, otp: str, tag: str) -> None:
    for _ in range(12):
        t = dump(dev, tag)
        if "Signing you in" in t:
            time.sleep(3)
            continue
        break
    t = dump(dev, tag)
    if dev == P and "Where are you headed" in t:
        return
    if dev == D and ('content-desc="Driver"' in t or "Open ride requests" in t):
        return
    if dev == D and "Where are you headed" in t and "not wired to the backend" not in t:
        return
    if "Send code" in t or "Phone number" in t or "Send verification code" in t:
        emu = dev.startswith("emulator-")
        cx, cy = (640, 1200) if emu or dev == P else (540, 1364)
        shell(dev, "input", "tap", str(cx), str(cy))
        digits = phone.lstrip("+")
        shell(dev, "input", "text", digits)
        shell(dev, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        tap(dev, "Send code", dump(dev, tag))
        time.sleep(6)
        otp_y = 500 if (emu or dev == P) else 610
        shell(dev, "input", "tap", str(cx), str(otp_y))
        shell(dev, "input", "text", otp)
        tap(dev, "Verify", dump(dev, tag))
        wait_for(dev, "Where are you headed", 25, 2.0, tag + "_postauth")


def passenger_create_ride() -> None:
    subprocess.call(["adb", "-s", P, "emu", "geo", "fix", "74.3587", "31.5204"])
    launch(P)
    auth(P, "+923012345678", "123456", "p_auth")
    t = dump(P, "p_home")
    if not (
        tap(P, "Where are you headed?", t)
        or tap(P, "Where are you headed", t)
        or tap(P, "Set pickup", t)
    ):
        shell(P, "input", "tap", "640", "450")
    time.sleep(3)
    t = wait_for(P, "Where to?", 20, 2.0, "p_compose")
    if "Use current location" not in t and "Where to?" not in t:
        fail("ride compose not opened")
    tap(P, "Use current location", dump(P, "p_pick"))
    time.sleep(4)
    tap(P, "Confirm pickup | Confirm pickup", dump(P, "p_pick2"), exclude="destination to continue")
    time.sleep(2)
    t = dump(P, "p_dest")
    eds = re.findall(r'EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        shell(P, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        time.sleep(1)
        for _ in range(40):
            shell(P, "input", "keyevent", "KEYCODE_DEL")
        shell(P, "input", "text", "Liberty%Market%Lahore")
        time.sleep(8)
        t_sug = dump(P, "p_sug")
        if not (
            tap(P, "Liberty Market Gulberg III", t_sug)
            or tap(P, "Gulberg III", t_sug)
            or tap(P, "Liberty Market", t_sug)
        ):
            shell(P, "input", "tap", "673", "1513")
        time.sleep(4)
    for _ in range(8):
        t = dump(P, "p_conf")
        if "Confirm destination" in t:
            tap(P, "Confirm destination", t)
            time.sleep(3)
            break
        shell(P, "input", "swipe", "640", "1200", "640", "700", "400")
        time.sleep(1.5)
    t = wait_for(P, "Destination confirmed", 12, 2.0, "p_dest_ok")
    if "Destination confirmed" not in t:
        t = dump(P, "p_dest_ok2")
        if "Confirm destination" in t:
            tap(P, "Confirm destination", t)
            time.sleep(3)
            t = wait_for(P, "Destination confirmed", 10, 2.0, "p_dest_ok3")
    t = dump(P, "p_dest_final")
    if "Pickup confirmed" not in t and "Confirm pickup" in t:
        tap(P, "Confirm pickup", t)
        time.sleep(3)
        t = dump(P, "p_pick_final")
    if "Destination confirmed" not in t and not continue_enabled(t):
        REPORT["gates"]["ride_creation"] = "RED"
        fail("destination not confirmed — Continue still disabled")
    t0 = time.time()
    t = dump(P, "p_cont")
    if not tap(P, "Continue", t):
        shell(P, "input", "tap", "640", "1674")
    t = wait_for(P, "Select a ride", 20, 2.0, "p_rev")
    if "Select a ride" not in t:
        REPORT["gates"]["ride_creation"] = "RED"
        fail("passenger review not reached")
    tap(P, "Easy", t) or tap(P, "Trio,", t)
    time.sleep(2)
    t_city = dump(P, "p_city")
    tap(P, "Lahore", t_city) or tap(P, "lahore", t_city)
    time.sleep(1)
    t_pr = time.time()
    tap(P, "Retry pricing", dump(P, "p_price"))
    time.sleep(20)
    REPORT["timings"]["pricing_s"] = round(time.time() - t_pr, 2)
    t_cr = time.time()
    for _ in range(3):
        t = dump(P, "p_price2")
        if "Waiting for offers" in t:
            break
        if tap(P, "Request Easy", t) or tap(P, "Request Trio", t) or tap(P, "Request ", t):
            time.sleep(4)
            continue
        time.sleep(3)
    t = wait_for(P, "Waiting for offers", 25, 2.0, "p_wait")
    REPORT["timings"]["ride_create_s"] = round(time.time() - t_cr, 2)
    REPORT["gates"]["ride_creation"] = "GREEN" if "Waiting for offers" in t else "RED"
    if "Waiting for offers" not in t:
        fail("ride not created — no waiting screen")


def fetch_latest_ride_id() -> Optional[str]:
    cmd = [
        "./node_modules/.bin/tsx",
        "scripts/e2e_fetch_latest_ride.ts",
    ]
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": "./secrets/service-account.json"}
    root = "/Users/jazimsaeed/Ora-app/backend/auth-service"
    out = subprocess.check_output(cmd, cwd=root, env=env, stderr=subprocess.STDOUT)
    data = json.loads(out.decode())
    rides = data.get("rides") or []
    if not rides:
        return None
    return rides[0].get("rideId")


def driver_ready() -> None:
    launch(D)
    auth(D, "+923012345677", "000000", "d_auth")
    t = dump(D, "d_home")
    if "not wired to the backend" in t or "Driver mode is planned" in t:
        tap(D, "Got it", t)
        fail("Samsung not on approved driver session — re-login as +923012345677")
    if "Earn on ORA" in t:
        tap(D, "Earn on ORA", t)
        t = wait_for(D, "Open ride requests", 20, 2.0, "d_dhome")
        if "not wired to the backend" in t:
            fail("driver gate blocked — wrong account or stale profile")
    tap(D, "Open ride requests", dump(D, "d_open")) or tap(D, "Open ride", dump(D, "d_open"))
    time.sleep(5)
    t = dump(D, "d_open2")
    REPORT["gates"]["driver_ready"] = "GREEN" if "Cannot reach" not in t and "unexpected" not in t.lower() else "RED"


def foreground(dev: str) -> None:
    shell(dev, "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(3)


def driver_discover_and_offer(expected_fare_minor: int = 114000) -> None:
    foreground(D)
    tap(D, "Open ride requests", dump(D, "d_reopen")) or tap(D, "Open ride", dump(D, "d_reopen"))
    time.sleep(3)
    t0 = time.time()
    shell(D, "input", "swipe", "540", "600", "540", "1400", "500")
    time.sleep(8)
    REPORT["timings"]["driver_discovery_s"] = round(time.time() - t0, 2)
    t = dump(D, "d_disc")
    if not any(k in t for k in ("Liberty", "Ride request", "Current location", "Rs ")):
        REPORT["gates"]["driver_discovery"] = "RED"
        fail("no ride on driver open list")
    REPORT["gates"]["driver_discovery"] = "GREEN"
    if not tap(D, "Respond", t):
        fail("Respond not found")
    time.sleep(2)
    t = dump(D, "d_offer_sheet")
    tap(D, "Accept passenger price", t)
    time.sleep(1)
    # Amount field may already hold minor units
    t = dump(D, "d_offer2")
    tap(D, "Submit offer", t) or tap(D, "Submit", t)
    time.sleep(8)
    t = dump(D, "d_offer3")
    REPORT["gates"]["driver_offer"] = "GREEN" if "offer" in t.lower() or "submitted" in t.lower() else "YELLOW"


def passenger_select_offer() -> None:
    t0 = time.time()
    t = wait_for(P, "Select", 40, 3.0, "p_offers")
    if "Select" not in t:
        REPORT["gates"]["passenger_offer"] = "RED"
        fail("no offer on passenger")
    REPORT["gates"]["passenger_offer"] = "GREEN"
    REPORT["timings"]["offer_appear_s"] = round(time.time() - t0, 2)
    tap(P, "Select", t)
    time.sleep(10)
    t = dump(P, "p_after_sel")
    REPORT["gates"]["assignment"] = "GREEN" if any(
        s in t for s in ("DRIVER_ASSIGNED", "Active", "En route", "Assigned")
    ) else "YELLOW"


def driver_open_assigned_job(ride_id: str) -> None:
    # drawer → My trips → tap trip
    t = dump(D, "d_nav")
    tap(D, "Menu", t) or shell(D, "input", "keyevent", "KEYCODE_MENU")
    time.sleep(2)
    tap(D, "My trips", dump(D, "d_drawer"))
    time.sleep(5)
    t = dump(D, "d_trips")
    if not tap(D, "Liberty", t):
        tap(D, "Current location", t) or tap(D, "Assigned", t)
    time.sleep(4)


def driver_progression_loop() -> None:
    labels = ["Mark en route", "Mark arrived", "Start ride", "Complete ride"]
    for label in labels:
        t = wait_for(D, label, 15, 2.0, "d_prog")
        if label not in t:
            break
        t0 = time.time()
        tap(D, label, t)
        time.sleep(6)
        REPORT["timings"][f"progress_{label}"] = round(time.time() - t0, 2)
    t = dump(D, "d_done")
    if "Close ride" in t:
        tap(D, "Close ride", t)
        time.sleep(5)
        REPORT["gates"]["RIDE_CLOSED"] = "GREEN"
    elif "RIDE_COMPLETED" in t:
        REPORT["gates"]["COMPLETED"] = "GREEN"
        REPORT["gates"]["RIDE_CLOSED"] = "YELLOW"


def fail(msg: str) -> None:
    print("FAIL:", msg, file=sys.stderr)
    print(json.dumps(REPORT, indent=2))
    sys.exit(1)


def main() -> None:
    REPORT["started"] = datetime.now(timezone.utc).isoformat()
    driver_ready()
    passenger_create_ride()
    ride_id = fetch_latest_ride_id()
    REPORT["rideId"] = ride_id
    if not ride_id:
        fail("no rideId from backend")
    driver_discover_and_offer()
    passenger_select_offer()
    if ride_id:
        driver_open_assigned_job(ride_id)
    driver_progression_loop()
    # snapshot final state
    subprocess.call(
        [
            "./node_modules/.bin/tsx",
            "scripts/e2e_ride_snapshot.ts",
            ride_id or "",
        ],
        cwd="/Users/jazimsaeed/Ora-app/backend/auth-service",
        env={**subprocess.os.environ, "GOOGLE_APPLICATION_CREDENTIALS": "./secrets/service-account.json"},
    )
    print(json.dumps(REPORT, indent=2))


if __name__ == "__main__":
    main()
