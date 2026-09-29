#!/usr/bin/env python3
"""Driver-ready-first → one passenger ride → one driver offer."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

P = "emulator-5554"
D = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
RID: str | None = None
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
LOG = f"{ART}/backend_8080.log"
MARKER = ""


def env() -> dict:
    return {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}


def tsx(script: str, *args: str) -> dict:
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env(),
        timeout=60,
    )
    return json.loads(out.decode())


def sh(dev: str, *args: str) -> str:
    return subprocess.check_output(["adb", "-s", dev, "shell", *args], stderr=subprocess.STDOUT, timeout=60).decode(
        "utf-8", errors="replace"
    )


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/t2a_{tag}.xml"
    sh(dev, "uiautomator", "dump", "/sdcard/t2a.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/t2a.xml", path], timeout=30)
    return open(path, encoding="utf-8").read()


def parse_nodes(t: str) -> list[dict]:
    out: list[dict] = []
    for m in re.finditer(r"<node ([^/>]+)/?>", t):
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
                "class": g("class"),
                "desc": g("content-desc").replace("&#10;", "\n"),
                "text": g("text"),
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
    for n in parse_nodes(t):
        d = n["desc"]
        if prefix and not d.startswith(needle):
            continue
        if not prefix and needle not in d:
            continue
        if not n["clickable"]:
            continue
        tap_node(dev, n)
        return True
    return False


def auth_phone(dev: str, phone: str, otp: str, tag: str) -> None:
    t = dump(dev, f"{tag}_auth0")
    if "Phone number" not in t and "Welcome to ORA" not in t and "Send verification code" not in t:
        return
    eds = [n for n in parse_nodes(t) if n["class"] == "android.widget.EditText"]
    if eds:
        tap_node(dev, eds[0])
    else:
        sh(dev, "input", "tap", "540", "1364")
    for _ in range(28):
        sh(dev, "input", "keyevent", "67")
    sh(dev, "input", "text", phone.replace("+", ""))
    time.sleep(1)
    t = dump(dev, f"{tag}_auth1")
    tap_desc(dev, t, "Send code") or tap_desc(dev, t, "Send verification code")
    time.sleep(10)
    sh(dev, "input", "tap", "540", "610")
    sh(dev, "input", "text", otp)
    time.sleep(1)
    t = dump(dev, f"{tag}_auth2")
    tap_desc(dev, t, "Verify", prefix=True)
    time.sleep(12)


def driver_ready() -> str:
    subprocess.check_call(["adb", "-s", D, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    sh(D, "input", "keyevent", "KEYCODE_WAKEUP")
    subprocess.check_call(["adb", "-s", D, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"], timeout=15)
    time.sleep(8)
    auth_phone(D, "923012345677", "000000", "drv")

    for i in range(10):
        t = dump(D, f"drv_nav{i}")
        if "Open rides" in t or t.count("Open ride requests") and "Earn" not in t:
            if "Open rides" in t:
                return t
        if tap_desc(D, t, "Earn on ORA"):
            time.sleep(4)
            continue
        if tap_desc(D, t, "Open ride requests", prefix=True):
            time.sleep(5)
            continue
        if tap_desc(D, t, "Menu"):
            time.sleep(2)
            t2 = dump(D, f"drv_drawer{i}")
            if tap_desc(D, t2, "Earn on ORA"):
                time.sleep(4)
                continue
            if tap_desc(D, t2, "Open ride requests", prefix=True):
                time.sleep(5)
                continue
        time.sleep(2)

    t = dump(D, "drv_ready_final")
    if "Open rides" not in t:
        raise RuntimeError("DRIVER_NOT_READY")
    return t


def passenger_create_ride() -> str:
    global MARKER
    subprocess.check_call(["adb", "-s", P, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    subprocess.call(["adb", "-s", P, "emu", "geo", "fix", "74.3587", "31.5204"], timeout=10)
    sh(P, "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION")
    subprocess.check_call(["adb", "-s", P, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"], timeout=15)
    time.sleep(6)

    t = dump(P, "p0")
    if "Waiting for offers" in t or ("Offers" in t and "SEARCHING" in t):
        tap_desc(P, t, "Back to Home")
        time.sleep(3)
        t = dump(P, "p_home")
    auth_phone(P, "923012345678", "123456", "pas")

    t = dump(P, "p_trip")
    tap_desc(P, t, "Where are you headed") or tap_desc(P, t, "Easy")
    time.sleep(3)
    t = dump(P, "p_gps")
    tap_desc(P, t, "Use current location")
    time.sleep(5)
    t = dump(P, "p_cp")
    btn = None
    for n in parse_nodes(t):
        if n["class"] == "android.widget.Button" and "Confirm pickup" in n["desc"]:
            btn = n
            break
    if btn is None:
        raise RuntimeError("CONFIRM_PICKUP_MISSING")
    tap_node(P, btn)
    time.sleep(3)

    t = dump(P, "p_dest0")
    eds = [n for n in parse_nodes(t) if n["class"] == "android.widget.EditText"]
    if eds:
        tap_node(P, eds[-1])
    for _ in range(40):
        sh(P, "input", "keyevent", "67")
    sh(P, "input", "text", "Liberty%sMarket%sLahore")
    time.sleep(6)
    t = dump(P, "p_sug")
    tap_desc(P, t, "Gulberg III") or tap_desc(P, t, "Liberty Market")
    time.sleep(6)
    t = dump(P, "p_dconf")
    for n in parse_nodes(t):
        if n["class"] == "android.widget.Button" and n["desc"].startswith("Confirm destination"):
            tap_node(P, n)
            break
    time.sleep(3)

    t = dump(P, "p_cont")
    for n in parse_nodes(t):
        if n["class"] == "android.widget.Button" and n["desc"].startswith("Continue") and n["enabled"]:
            tap_node(P, n)
            break
    time.sleep(5)

    MARKER = f"=== T2A_FRESH_RIDE_MARKER {datetime.now(timezone.utc).isoformat()} ==="
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(MARKER + "\n")

    t = dump(P, "p_rev")
    req = None
    for n in parse_nodes(t):
        if n["class"] == "android.widget.Button" and n["desc"].startswith("Request Easy") and n["enabled"]:
            req = n
            break
    if req is None:
        raise RuntimeError("REQUEST_EASY_MISSING")
    tap_node(P, req)
    time.sleep(10)

    t = dump(P, "p_wait")
    if "Waiting for offers" not in t and "Offers" not in t:
        raise RuntimeError("PASSENGER_RIDE_NOT_CREATED")

    data = tsx("e2e_fetch_latest_ride.ts")
    rides = data.get("rides") or []
    if not rides:
        raise RuntimeError("NO_RIDE_IN_FIRESTORE")
    rid = rides[0]["rideId"]
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap["ride"]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    exp = (ride.get("expiresAt") or "")[:19]
    if ride.get("state") != "SEARCHING" or exp <= now:
        raise RuntimeError(f"BAD_RIDE_STATE {ride}")
    if snap.get("offers"):
        raise RuntimeError("OFFERS_NOT_EMPTY")
    return rid


def find_respond(t: str) -> dict | None:
    for n in parse_nodes(t):
        if n["class"] != "android.widget.Button":
            continue
        blob = f"{n['desc']}\n{n['text']}"
        if "Respond to ride request" in blob or re.search(r"^Respond(\n|$)", blob):
            return n
    return None


def driver_offer(rid: str) -> None:
    sh(D, "input", "swipe", "540", "600", "540", "1400", "350")
    time.sleep(2)
    t = dump(D, "drv_refresh")
    if "Liberty" not in t and "Current location" not in t:
        tap_desc(D, t, "Refresh")
        time.sleep(4)
        t = dump(D, "drv_list")

    if rid[:8] not in t and "Liberty" not in t:
        raise RuntimeError("DRIVER_DISCOVERY_FAIL")

    respond = find_respond(t)
    if respond is None:
        raise RuntimeError("RESPOND_MISSING")
    tap_node(D, respond)
    time.sleep(3)
    t_sheet = dump(D, "sheet")
    if not any(x in t_sheet for x in ("Submit offer", "Accept passenger price")):
        raise RuntimeError("SHEET_NOT_OPEN")

    tap_desc(D, t_sheet, "Accept passenger price")
    time.sleep(2)
    t_sub = dump(D, "submit")
    if not tap_desc(D, t_sub, "Submit offer", prefix=True):
        raise RuntimeError("SUBMIT_MISSING")
    time.sleep(10)


def main() -> int:
    report: dict = {"started": datetime.now(timezone.utc).isoformat()}
    try:
        ready_xml = driver_ready()
        report["driverReady"] = {
            "openRidesVisible": "Open rides" in ready_xml,
            "artifact": "t2a_drv_ready_final.xml",
        }
        print("DRIVER_READY", json.dumps(report["driverReady"]))

        rid = passenger_create_ride()
        report["rideId"] = rid
        snap0 = tsx("e2e_ride_snapshot.ts", rid)
        ride = snap0["ride"]
        report["createdAt"] = ride.get("createdAt")
        report["expiresAt"] = ride.get("expiresAt")
        report["marker"] = MARKER
        print("PASSENGER_RIDE", rid, report["expiresAt"])

        driver_offer(rid)
        snap1 = tsx("e2e_ride_snapshot.ts", rid)
        offers = snap1.get("offers") or []
        report["offers"] = offers
        report["rideAfter"] = {
            "state": snap1["ride"].get("state"),
            "assignedDriverId": snap1["ride"].get("assignedDriverId"),
            "requestVersion": snap1["ride"].get("requestVersion"),
        }
        if len(offers) != 1:
            report["result"] = "FAIL"
            print(json.dumps(report, indent=2))
            return 1
        o = offers[0]
        amt = o.get("amountMinor")
        report["offer"] = {
            "offerId": o.get("offerId"),
            "driverId": o.get("driverId"),
            "amountMinor": amt,
            "amountRs": amt // 100 if isinstance(amt, int) else None,
            "state": o.get("state") or o.get("status"),
            "requestVersion": o.get("requestVersion"),
        }
        if snap1["ride"].get("state") != "SEARCHING" or snap1["ride"].get("assignedDriverId"):
            report["result"] = "FAIL"
            print(json.dumps(report, indent=2))
            return 1
        report["result"] = "PASS"
        print(json.dumps(report, indent=2))
        return 0
    except Exception as e:
        report["result"] = "BLOCKED" if "NOT_READY" in str(e) or "DISCOVERY" in str(e) else "FAIL"
        report["error"] = str(e)
        print(json.dumps(report, indent=2))
        return 2 if report["result"] == "BLOCKED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
