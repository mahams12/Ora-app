#!/usr/bin/env python3
"""Bounded driver-offer verification — ops only, no monkey, no force-stop loops."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

P = "emulator-5554"
D = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
T0 = time.time()
LIMIT_S = 420
STEP = 0


def deadline() -> None:
    if time.time() - T0 > LIMIT_S:
        abort("BLOCKED", "time_limit_7min")


def abort(kind: str, gate: str, extra: dict | None = None) -> None:
    out = {"result": kind, "gate": gate, **(extra or {})}
    print(json.dumps(out, indent=2))
    sys.exit(0 if kind == "PASS" else 1)


def emu_ok() -> bool:
    try:
        out = subprocess.check_output(["adb", "devices"], stderr=subprocess.STDOUT, timeout=5).decode()
        return f"{P}\tdevice" in out
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False


def require_emu(where: str) -> None:
    if not emu_ok():
        abort("BLOCKED", f"emulator_disconnected:{where}", {"adb_devices": adb_devices()})


def adb_devices() -> str:
    return subprocess.check_output(["adb", "devices", "-l"], timeout=5).decode()


def start_emulator_if_needed() -> None:
    if emu_ok():
        return
    android_home = os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk"))
    emu = f"{android_home}/emulator/emulator"
    log = f"{ART}/bounded_verify_emu.log"
    subprocess.Popen(
        [emu, "-avd", "Pixel_9_Pro", "-no-window", "-no-audio", "-no-boot-anim", "-gpu", "swiftshader_indirect", "-memory", "2048"],
        stdout=open(log, "a"),
        stderr=subprocess.STDOUT,
    )
    boot_deadline = time.time() + 100
    while time.time() < boot_deadline:
        if not emu_ok():
            time.sleep(2)
            continue
        boot = subprocess.check_output(["adb", "-s", P, "shell", "getprop", "sys.boot_completed"], timeout=10).decode().strip()
        if boot == "1":
            return
        time.sleep(2)
    abort("BLOCKED", "emulator_boot_timeout")


def env():
    return {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}


def tsx(script: str, *args: str) -> dict:
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env(),
        timeout=30,
    )
    return json.loads(out.decode())


def am_start(dev: str) -> None:
    subprocess.check_call(
        ["adb", "-s", dev, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"],
        timeout=15,
    )


def sh(dev: str, *args: str) -> str:
    return subprocess.check_output(["adb", "-s", dev, "shell", *args], stderr=subprocess.STDOUT, timeout=30).decode(
        "utf-8", errors="replace"
    )


def dump(dev: str, tag: str) -> str:
    global STEP
    STEP += 1
    deadline()
    require_emu("before_dump") if dev == P else None
    path = f"{ART}/bv_{tag}.xml"
    sh(dev, "uiautomator", "dump", "/sdcard/bv.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/bv.xml", path], timeout=20)
    return open(path, encoding="utf-8").read()


def nodes(t: str) -> list[dict]:
    out: list[dict] = []
    for m in re.finditer(r"<node ([^/]+)/>", t):
        a = m.group(1)

        def g(n: str) -> str:
            mm = re.search(rf'{n}="([^"]*)"', a)
            return mm.group(1) if mm else ""

        b = g("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        out.append(
            {
                "desc": g("content-desc").replace("&#10;", "\n"),
                "clickable": g("clickable") == "true",
                "enabled": g("enabled") == "true",
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return out


def tap_node(dev: str, n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    sh(dev, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def tap_desc(dev: str, t: str, needle: str, *, prefix: bool = False) -> bool:
    for n in nodes(t):
        d = n["desc"]
        if prefix and not d.startswith(needle):
            continue
        if not prefix and needle not in d:
            continue
        tap_node(dev, n)
        return True
    return False


def passenger_ride() -> str:
    start_emulator_if_needed()
    subprocess.check_call(["adb", "-s", P, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    subprocess.call(["adb", "-s", P, "emu", "geo", "fix", "74.3587", "31.5204"], timeout=10)
    am_start(P)
    time.sleep(15)
    t = dump(P, "p0")
    if "Phone number" in t or "Send verification code" in t:
        sh(P, "input", "tap", "640", "1200")
        sh(P, "input", "text", "923012345678")
        sh(P, "input", "keyevent", "4")
        time.sleep(1)
        t = dump(P, "p_auth")
        tap_desc(P, t, "Send code") or tap_desc(P, t, "Send verification code")
        time.sleep(8)
        sh(P, "input", "tap", "640", "500")
        sh(P, "input", "text", "123456")
        time.sleep(1)
        t = dump(P, "p_verify")
        for n in nodes(t):
            if n["desc"].startswith("Verify"):
                tap_node(P, n)
                break
        time.sleep(12)
        t = dump(P, "p_home")

    if "Waiting for offers" in t or ("Ride request" in t and "SEARCHING" in t):
        t = dump(P, "p_stale")
        tap_desc(P, t, "Back to Home")
        time.sleep(3)
        t = dump(P, "p_home2")

    t = dump(P, "p_trip")
    tap_desc(P, t, "Where are you headed")
    time.sleep(3)
    t = dump(P, "p_pick")
    tap_desc(P, t, "Use current location")
    time.sleep(4)
    t = dump(P, "p_pick2")
    tap_desc(P, t, "Confirm pickup", prefix=True)
    time.sleep(2)
    t = dump(P, "p_dest")
    eds = re.findall(r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        sh(P, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        for _ in range(35):
            sh(P, "input", "keyevent", "67")
        sh(P, "input", "text", "Liberty%Market%Lahore")
    time.sleep(8)
    t = dump(P, "p_sug")
    tap_desc(P, t, "Liberty Market Gulberg") or tap_desc(P, t, "Gulberg III")
    time.sleep(4)
    for _ in range(5):
        t = dump(P, "p_conf")
        if tap_desc(P, t, "Confirm destination", prefix=True):
            time.sleep(3)
            break
        sh(P, "input", "swipe", "640", "1200", "640", "700", "400")
        time.sleep(1)
    t = dump(P, "p_cont")
    tap_desc(P, t, "Continue", prefix=True)
    time.sleep(5)
    t = dump(P, "p_rev")
    tap_desc(P, t, "Easy,", prefix=True) or tap_desc(P, t, "Trio,", prefix=True)
    time.sleep(2)
    t = dump(P, "p_city")
    tap_desc(P, t, "Lahore") or tap_desc(P, t, "lahore")
    time.sleep(1)
    t = dump(P, "p_retry")
    tap_desc(P, t, "Retry pricing") or (sh(P, "input", "swipe", "640", "2300", "640", "900", "450") or True)
    time.sleep(26)
    t = dump(P, "p_price")
    if "Waiting for offers" in t:
        before = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"]
        rid = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["rideId"]
        return rid
    if "Request Easy" not in t and "Request Trio" not in t and "Rs " not in t:
        abort("BLOCKED", "passenger_pricing_review", {"ui_snippet": t[:500]})
    t = dump(P, "p_req")
    tap_desc(P, t, "Request Easy", prefix=True) or tap_desc(P, t, "Request Trio", prefix=True)
    time.sleep(10)
    t = dump(P, "p_wait")
    if "Waiting for offers" not in t:
        abort("BLOCKED", "passenger_waiting_for_offers", {"screen": "see bv_p_wait.xml"})
    before = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"]
    snap = tsx("e2e_ride_snapshot.ts", tsx("e2e_fetch_latest_ride.ts")["rides"][0]["rideId"])
    ride = snap["ride"]
    if ride.get("state") != "SEARCHING" or ride.get("assignedDriverId"):
        abort("BLOCKED", "passenger_firestore_state", {"ride": ride})
    if snap.get("offers"):
        abort("BLOCKED", "passenger_offers_not_empty")
    exp = ride.get("expiresAt") or ""
    if exp and exp <= datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S"):
        pass
    print(
        "PASSENGER_OK",
        json.dumps(
            {
                "rideId": ride["rideId"],
                "requestVersion": ride.get("requestVersion"),
                "expiresAt": ride.get("expiresAt"),
                "state": ride.get("state"),
            }
        ),
    )
    return ride["rideId"]


def driver_flow(rid: str) -> None:
    subprocess.check_call(["adb", "-s", D, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    sh(D, "input", "keyevent", "KEYCODE_WAKEUP")
    am_start(D)
    time.sleep(8)
    t = dump(D, "d0")
    if "Phone number" in t or "Send verification code" in t:
        sh(D, "input", "tap", "540", "1364")
        for _ in range(22):
            sh(D, "input", "keyevent", "67")
        sh(D, "input", "text", "03012345677")
        sh(D, "input", "keyevent", "4")
        time.sleep(0.5)
        t = dump(D, "d_send")
        tap_desc(D, t, "Send code") or tap_desc(D, t, "Send verification code")
        time.sleep(10)
        sh(D, "input", "tap", "540", "610")
        sh(D, "input", "text", "000000")
        t = dump(D, "d_ver")
        tap_desc(D, t, "Verify", prefix=True)
        time.sleep(12)
        t = dump(D, "d_after_auth")

    open_reached = False
    for attempt in range(6):
        deadline()
        t = dump(D, f"d_nav{attempt}")
        if "Open ride requests" in t or ("Liberty" in t and ("Respond" in t or "Rs " in t)):
            open_reached = True
            break
        if tap_desc(D, t, "Earn on ORA"):
            time.sleep(4)
            continue
        if tap_desc(D, t, "Open ride requests", prefix=True) or tap_desc(D, t, "Open ride", prefix=True):
            time.sleep(5)
            continue
        if tap_desc(D, t, "Menu"):
            time.sleep(2)
            t2 = dump(D, f"d_drawer{attempt}")
            if tap_desc(D, t2, "Earn on ORA") or tap_desc(D, t2, "Driver"):
                time.sleep(4)
                continue
            if tap_desc(D, t2, "Open ride requests", prefix=True):
                time.sleep(5)
                continue
        time.sleep(2)

    t = dump(D, "d_open")
    if not open_reached and not ("Liberty" in t or "Current location" in t):
        abort(
            "BLOCKED",
            "driver_open_ride_requests",
            {"rideId": rid, "open_reached": open_reached, "screen": "bv_d_open.xml"},
        )

    live = tsx("e2e_ride_snapshot.ts", rid)
    ride = live["ride"]
    if ride.get("state") != "SEARCHING":
        abort("BLOCKED", "ride_not_searching", {"state": ride.get("state"), "rideId": rid})

    if not any(x in t for x in ("Liberty", "Current location", "Respond", "Rs ")):
        abort("BLOCKED", "driver_ride_card_not_visible", {"rideId": rid, "expiresAt": ride.get("expiresAt")})

    # Respond ONCE
    t_before = dump(D, "d_pre_respond")
    cards = [n for n in nodes(t_before) if n["clickable"] and "Respond" in n["desc"]]
    if not cards:
        cards = [n for n in nodes(t_before) if n["clickable"] and ("Liberty" in n["desc"] or "Rs " in n["desc"])]
    if not cards:
        abort("BLOCKED", "driver_respond_control_missing", {"rideId": rid})
    card = cards[0]
    x1, y1, x2, y2 = card["bounds"]
    sh(D, "input", "tap", str((x1 + x2) // 2), str(y2 - 45))
    time.sleep(3)
    t_sheet = dump(D, "d_sheet")
    opened = any(s in t_sheet for s in ("Submit offer", "Accept passenger price"))
    if not opened:
        abort("BLOCKED", "driver_offer_sheet", {"rideId": rid, "respond_bounds": card["bounds"]})

    tap_desc(D, t_sheet, "Accept passenger price")
    time.sleep(2)
    t_sub = dump(D, "d_submit")
    tap_desc(D, t_sub, "Submit offer", prefix=True)
    time.sleep(8)

    snap = tsx("e2e_ride_snapshot.ts", rid)
    offers = snap.get("offers") or []
    if len(offers) != 1:
        abort(
            "FAIL" if opened else "BLOCKED",
            "firestore_offers_count",
            {"rideId": rid, "offerCount": len(offers), "offers": offers},
        )
    o = offers[0]
    abort(
        "PASS",
        "driver_offer_written",
        {
            "rideId": rid,
            "offerId": o.get("offerId"),
            "driverId": o.get("driverId"),
            "amountMinor": o.get("amountMinor"),
            "requestVersion": snap.get("ride", {}).get("requestVersion"),
            "createdAt": o.get("createdAt"),
            "offerCount": 1,
        },
    )


def main() -> None:
    rid = passenger_ride()
    driver_flow(rid)


if __name__ == "__main__":
    main()
