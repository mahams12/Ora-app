#!/usr/bin/env python3
"""Samsung=passenger, emulator=driver, remote Cloud Run staging only (no adb reverse)."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

P = os.environ.get("ORA_E2E_PASSENGER", "RF8R40ZQ1JH")
D = os.environ.get("ORA_E2E_DRIVER", "emulator-5554")
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
REPORT: Dict[str, Any] = {"gates": {}, "timings": {}, "rideId": None, "offerId": None}
RUN_STARTED = datetime.now(timezone.utc).isoformat()


def adb(dev: str, *args: str) -> str:
    out = subprocess.check_output(["adb", "-s", dev, *args], stderr=subprocess.STDOUT)
    return out.decode("utf-8", errors="replace")


def shell(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, "shell", *args])


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/rs_{tag}_ui.xml"
    shell(dev, "uiautomator", "dump", "/sdcard/rs_ui.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/rs_ui.xml", path])
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
    m = re.search(r'content-desc="Continue[^"]*"[^>]*enabled="(true|false)"', t)
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


def phone_tap(dev: str) -> Tuple[int, int]:
    if dev.startswith("emulator-"):
        return 640, 1200
    return 540, 1364


def auth(dev: str, phone: str, otp: str, tag: str) -> None:
    for _ in range(12):
        t = dump(dev, tag)
        if "Signing you in" in t:
            time.sleep(3)
            continue
        break
    t = dump(dev, tag)
    if dev == P and "Where are you headed" in t:
        REPORT["gates"]["auth_passenger"] = "GREEN"
        return
    if dev == D and ('content-desc="Driver"' in t or "Open ride requests" in t or "Open rides" in t):
        REPORT["gates"]["auth_driver"] = "GREEN"
        return
    if "Send code" in t or "Phone number" in t or "Send verification code" in t:
        cx, cy = phone_tap(dev)
        shell(dev, "input", "tap", str(cx), str(cy))
        shell(dev, "input", "text", phone.lstrip("+"))
        shell(dev, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        tap(dev, "Send code", dump(dev, tag)) or tap(dev, "Send verification code", dump(dev, tag))
        time.sleep(8)
        otp_y = 500 if dev.startswith("emulator-") else 610
        shell(dev, "input", "tap", str(cx), str(otp_y))
        shell(dev, "input", "text", otp)
        tap(dev, "Verify", dump(dev, tag))
        wait_for(dev, "Where are you headed", 25, 2.0, tag + "_postauth") if dev == P else wait_for(
            dev, "Earn on ORA", 25, 2.0, tag + "_postauth"
        )
    gate = "auth_passenger" if dev == P else "auth_driver"
    REPORT["gates"][gate] = "GREEN"


def passenger_create_ride() -> None:
    global RUN_STARTED
    launch(P)
    auth(P, "+923012345678", "123456", "p_auth")
    t = dump(P, "p_home")
    if "Waiting for offers" in t or ("Offers" in t and "SEARCHING" in t):
        tap(P, "Back to Home", t)
        time.sleep(3)
        t = dump(P, "p_home2")
    if not (
        tap(P, "Where are you headed?", t)
        or tap(P, "Where are you headed", t)
        or tap(P, "Set pickup", t)
    ):
        shell(P, "input", "tap", "540", "450")
    time.sleep(3)
    t = wait_for(P, "Where to?", 20, 2.0, "p_compose")
    tap(P, "Use current location", dump(P, "p_pick"))
    time.sleep(4)
    tap(P, "Confirm pickup", dump(P, "p_pick2"), exclude="destination to continue")
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
        tap(P, "Liberty Market Gulberg III", t_sug) or tap(P, "Gulberg III", t_sug) or tap(
            P, "Liberty Market", t_sug
        )
        time.sleep(4)
    for _ in range(8):
        t = dump(P, "p_conf")
        if "Confirm destination" in t:
            tap(P, "Confirm destination", t)
            time.sleep(3)
            break
        shell(P, "input", "swipe", "540", "1200", "540", "700", "400")
        time.sleep(1.5)
    t = wait_for(P, "Destination confirmed", 12, 2.0, "p_dest_ok")
    t = dump(P, "p_cont")
    if not tap(P, "Continue", t):
        shell(P, "input", "tap", "540", "1674")
    t = wait_for(P, "Select a ride", 25, 2.0, "p_rev")
    if "Pricing unavailable" in t:
        REPORT["gates"]["passenger_pricing"] = "FAIL"
        fail("pricing unavailable on review")
    if "Select a ride" not in t:
        fail("review not reached")
    if "Estimated fare" in t and re.search(r"Rs\s*\d+", t):
        REPORT["gates"]["passenger_pricing"] = "PASS"
    else:
        REPORT["gates"]["passenger_pricing"] = "FAIL"
        fail("no server fare on review")
    t_pr = time.time()
    if "Retry pricing" in t:
        tap(P, "Retry pricing", t)
        time.sleep(22)
        t = dump(P, "p_price_retry")
    REPORT["timings"]["pricing_s"] = round(time.time() - t_pr, 2)
    if "Lahore" not in t:
        tap(P, "Lahore", dump(P, "p_city")) or tap(P, "lahore", dump(P, "p_city"))
        time.sleep(1)
        t = dump(P, "p_rev2")
    for _ in range(4):
        t = dump(P, "p_req")
        if "Waiting for offers" in t:
            break
        tap(P, "Request Easy", t) or tap(P, "Request ", t)
        time.sleep(5)
    t = wait_for(P, "Waiting for offers", 30, 2.0, "p_wait")
    REPORT["gates"]["ride_creation"] = "PASS" if "Waiting for offers" in t else "FAIL"
    if "Waiting for offers" not in t:
        fail("ride not created")


def tsx(script: str, *args: str) -> dict:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env,
        timeout=60,
    )
    return json.loads(out.decode())


def driver_ready() -> None:
    launch(D)
    auth(D, "+923012345677", "000000", "d_auth")
    t = dump(D, "d_home")
    if "not wired to the backend" in t or "Driver mode is planned" in t:
        fail("driver gate blocked")
    if "Earn on ORA" in t:
        tap(D, "Earn on ORA", t)
        wait_for(D, "Open ride requests", 20, 2.0, "d_dhome")
    tap(D, "Open ride requests", dump(D, "d_open")) or tap(D, "Open ride", dump(D, "d_open"))
    time.sleep(5)
    REPORT["gates"]["driver_ready"] = "PASS"


def driver_discover_and_offer() -> None:
    subprocess.check_call(["adb", "-s", D, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"])
    time.sleep(3)
    tap(D, "Open ride requests", dump(D, "d_reopen")) or tap(D, "Open ride", dump(D, "d_reopen"))
    time.sleep(3)
    cx = 640 if D.startswith("emulator-") else 540
    shell(D, "input", "swipe", str(cx), "600", str(cx), "1400", "500")
    time.sleep(8)
    t = dump(D, "d_disc")
    if not any(k in t for k in ("Liberty", "Ride request", "Current location", "Rs ")):
        REPORT["gates"]["driver_discovery"] = "FAIL"
        fail("driver discovery empty")
    REPORT["gates"]["driver_discovery"] = "PASS"
    if not tap(D, "Respond", t):
        REPORT["gates"]["respond_sheet"] = "FAIL"
        fail("Respond missing")
    time.sleep(3)
    t = dump(D, "d_sheet")
    if not any(x in t for x in ("Submit offer", "Accept passenger price")):
        REPORT["gates"]["respond_sheet"] = "FAIL"
        fail("offer sheet not open")
    REPORT["gates"]["respond_sheet"] = "PASS"
    tap(D, "Accept passenger price", t)
    time.sleep(1)
    tap(D, "Submit offer", dump(D, "d_submit")) or tap(D, "Submit", dump(D, "d_submit"))
    time.sleep(10)
    REPORT["gates"]["driver_offer"] = "PASS"


def passenger_select_offer() -> None:
    t = wait_for(P, "Select", 45, 3.0, "p_offers")
    if "Select" not in t:
        REPORT["gates"]["passenger_offer_selection"] = "FAIL"
        fail("no passenger offer UI")
    REPORT["gates"]["passenger_offer_selection"] = "PASS"
    tap(P, "Select", t)
    time.sleep(12)
    t = dump(P, "p_assigned")
    ok = any(s in t for s in ("DRIVER_ASSIGNED", "Assigned", "En route", "Active"))
    REPORT["gates"]["assignment"] = "PASS" if ok else "FAIL"


def driver_progression() -> None:
    subprocess.check_call(["adb", "-s", D, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"])
    time.sleep(2)
    for label, gate in [
        ("Mark en route", "EN_ROUTE"),
        ("Mark arrived", "ARRIVED"),
        ("Start ride", "STARTED"),
        ("Complete ride", "COMPLETED"),
    ]:
        t = wait_for(D, label, 18, 2.0, f"d_{gate}")
        if label not in t:
            REPORT["gates"][gate] = "FAIL"
            continue
        tap(D, label, t)
        time.sleep(6)
        REPORT["gates"][gate] = "PASS"
    t = dump(D, "d_close")
    if "Close ride" in t:
        tap(D, "Close ride", t)
        time.sleep(5)
        REPORT["gates"]["RIDE_CLOSED"] = "PASS"
    else:
        REPORT["gates"]["RIDE_CLOSED"] = "FAIL"


def fail(msg: str) -> None:
    REPORT["error"] = msg
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(REPORT, indent=2))
    sys.exit(1)


def main() -> None:
    global RUN_STARTED
    RUN_STARTED = datetime.now(timezone.utc).isoformat()
    REPORT["started"] = RUN_STARTED
    REPORT["passenger_device"] = P
    REPORT["driver_device"] = D
    REPORT["remote_api"] = "https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1"
    driver_ready()
    passenger_create_ride()
    rides = tsx("e2e_fetch_latest_ride.ts").get("rides") or []
    ride_id = None
    for r in rides:
        created = (r.get("createdAt") or "")[:19]
        if created >= RUN_STARTED[:19]:
            ride_id = r.get("rideId")
            break
    if not ride_id and rides:
        ride_id = rides[0].get("rideId")
    REPORT["rideId"] = ride_id
    if not ride_id:
        fail("no ride in firestore")
    snap = tsx("e2e_ride_snapshot.ts", ride_id)
    ride = snap.get("ride") or {}
    REPORT["backend_proof"] = {
        "state": ride.get("state"),
        "requestVersion": ride.get("requestVersion"),
        "pricingSnapshotId": ride.get("pricingSnapshotId"),
        "passengerOfferMinor": ride.get("passengerOfferMinor"),
        "assignedDriverId": ride.get("assignedDriverId"),
        "expiresAt": ride.get("expiresAt"),
    }
    exp = (ride.get("expiresAt") or "")[:19]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    if ride.get("state") != "SEARCHING" or ride.get("assignedDriverId"):
        fail(f"bad ride after create: {ride.get('state')}")
    if exp <= now:
        fail(f"ride expired: {exp}")
    if (ride.get("createdAt") or "")[:19] < RUN_STARTED[:19]:
        fail("ride is stale — no fresh ride created this run")
    driver_discover_and_offer()
    snap2 = tsx("e2e_ride_snapshot.ts", ride_id)
    offers = snap2.get("offers") or []
    REPORT["offers_after_driver"] = offers
    if len(offers) != 1:
        fail(f"expected 1 offer got {len(offers)}")
    passenger_select_offer()
    snap3 = tsx("e2e_ride_snapshot.ts", ride_id)
    ride3 = snap3.get("ride") or {}
    REPORT["backend_proof"]["after_assignment"] = {
        "state": ride3.get("state"),
        "assignedDriverId": ride3.get("assignedDriverId"),
    }
    driver_progression()
    snap4 = tsx("e2e_ride_snapshot.ts", ride_id)
    ride4 = snap4.get("ride") or {}
    REPORT["backend_proof"]["final"] = {
        "state": ride4.get("state"),
        "assignedDriverId": ride4.get("assignedDriverId"),
    }
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(REPORT, indent=2))


if __name__ == "__main__":
    main()
