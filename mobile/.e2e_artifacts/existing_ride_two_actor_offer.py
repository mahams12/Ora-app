#!/usr/bin/env python3
"""One bounded driver offer on existing ride — Samsung RF8R40ZQ1JH only."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

D = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
RID = "554dd535-3445-4733-b321-59bdb46c0829"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
MARKER = f"=== TWO_ACTOR_OFFER_TEST {datetime.now(timezone.utc).isoformat()} ==="


def env() -> dict:
    return {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}


def tsx(script: str, *args: str) -> dict:
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env(),
        timeout=45,
    )
    return json.loads(out.decode())


def sh(*args: str) -> str:
    return subprocess.check_output(["adb", "-s", D, "shell", *args], stderr=subprocess.STDOUT, timeout=45).decode(
        "utf-8", errors="replace"
    )


def dump(tag: str) -> str:
    path = f"{ART}/ta_{tag}.xml"
    sh("uiautomator", "dump", "/sdcard/ta.xml")
    subprocess.check_call(["adb", "-s", D, "pull", "/sdcard/ta.xml", path], timeout=25)
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


def tap_node(n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def tap_desc(t: str, needle: str, *, prefix: bool = False) -> bool:
    for n in parse_nodes(t):
        d = n["desc"]
        if prefix and not d.startswith(needle):
            continue
        if not prefix and needle not in d:
            continue
        if not n["clickable"]:
            continue
        tap_node(n)
        return True
    return False


def find_respond_button(t: str) -> dict | None:
    for n in parse_nodes(t):
        if n["class"] != "android.widget.Button":
            continue
        blob = f"{n['desc']}\n{n['text']}"
        if "Respond to ride request" in blob or re.search(r"^Respond(\n|$)", blob):
            return n
    return None


def main() -> int:
    print(MARKER)
    snap0 = tsx("e2e_ride_snapshot.ts", RID)
    ride = snap0["ride"]
    offers_before = snap0.get("offers") or []
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    exp = (ride.get("expiresAt") or "")[:19]
    print("RIDE_PRE", json.dumps({"state": ride.get("state"), "expiresAt": exp, "offers": len(offers_before)}, indent=2))
    if ride.get("state") != "SEARCHING" or ride.get("assignedDriverId"):
        print("BLOCKED ride_not_open", ride.get("state"), ride.get("assignedDriverId"))
        return 2
    if exp and exp <= now:
        print("BLOCKED ride_expired", exp, now)
        return 2
    if len(offers_before) > 0:
        print("BLOCKED offers_already_exist", offers_before)
        return 2

    subprocess.check_call(["adb", "-s", D, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    sh("input", "keyevent", "KEYCODE_WAKEUP")
    subprocess.check_call(["adb", "-s", D, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"], timeout=15)
    time.sleep(8)

    t0 = dump("boot")
    if "Phone number" in t0 or "Send verification code" in t0 or "Welcome to ORA" in t0:
        eds = [n for n in parse_nodes(t0) if n["class"] == "android.widget.EditText"]
        if eds:
            tap_node(eds[0])
        else:
            sh("input", "tap", "540", "1364")
        for _ in range(24):
            sh("input", "keyevent", "67")
        sh("input", "text", "923012345677")
        time.sleep(1)
        t0 = dump("send")
        tap_desc(t0, "Send code") or tap_desc(t0, "Send verification code")
        time.sleep(10)
        sh("input", "tap", "540", "610")
        sh("input", "text", "000000")
        time.sleep(1)
        t0 = dump("verify")
        tap_desc(t0, "Verify", prefix=True)
        time.sleep(12)

    open_list = False
    for i in range(8):
        t = dump(f"nav{i}")
        if "Liberty" in t or "Current location" in t:
            if "Open ride" in t or "Respond" in t or "Rs " in t:
                open_list = True
                break
        if tap_desc(t, "Earn on ORA"):
            time.sleep(4)
            continue
        if tap_desc(t, "Open ride requests", prefix=True) or tap_desc(t, "Open ride", prefix=True):
            time.sleep(5)
            continue
        if tap_desc(t, "Menu"):
            time.sleep(2)
            t2 = dump(f"drawer{i}")
            if tap_desc(t2, "Earn on ORA") or tap_desc(t2, "Driver"):
                time.sleep(4)
                continue
            if tap_desc(t2, "Open ride requests", prefix=True):
                time.sleep(5)
                continue
        time.sleep(2)

    t = dump("open_list")
    if not open_list and not ("Liberty" in t and ("Respond" in t or "Passenger offer" in t)):
        print("BLOCKED driver_discovery", t[:800])
        return 2

    discovery = {
        "liberty": "Liberty" in t,
        "current_location": "Current location" in t,
        "passenger_offer": "Passenger offer" in t or "Rs 310" in t or "Rs 310" in t.replace("&#10;", "\n"),
        "easy": "easy" in t.lower() or "Easy" in t,
    }
    print("DISCOVERY", discovery)

    respond = find_respond_button(t)
    if respond is None:
        # fallback: smallest clickable with Respond in desc (not whole card)
        cands = [n for n in parse_nodes(t) if n["clickable"] and "Respond" in n["desc"] and n["class"] == "android.widget.Button"]
        respond = cands[0] if cands else None
    print("RESPOND_NODE", respond)
    if respond is None:
        print("FAIL respond_control_missing")
        return 1

    tap_node(respond)
    print("TAPPED_RESPOND_ONCE")
    time.sleep(3)
    t_sheet = dump("offer_sheet")
    opened = any(s in t_sheet for s in ("Submit offer", "Accept passenger price", "Amount"))
    print("SHEET_OPENED", opened)
    if not opened:
        print("FAIL sheet_did_not_open", t_sheet[:1200])
        return 1

    sheet_fields = [n["desc"][:120] for n in parse_nodes(t_sheet) if n["desc"].strip()][:15]
    print("SHEET_FIELDS", sheet_fields)

    tap_desc(t_sheet, "Accept passenger price")
    time.sleep(2)
    t_sub = dump("pre_submit")
    if not tap_desc(t_sub, "Submit offer", prefix=True):
        print("FAIL submit_offer_missing")
        return 1
    print("TAPPED_SUBMIT_OFFER_ONCE")
    time.sleep(10)

    snap1 = tsx("e2e_ride_snapshot.ts", RID)
    ride_after = snap1["ride"]
    offers = snap1.get("offers") or []
    print("OFFERS_AFTER", json.dumps(offers, indent=2))
    print("RIDE_AFTER", json.dumps({"state": ride_after.get("state"), "assignedDriverId": ride_after.get("assignedDriverId"), "requestVersion": ride_after.get("requestVersion")}, indent=2))

    if len(offers) != 1:
        print("FAIL offer_count", len(offers))
        return 1
    o = offers[0]
    if ride_after.get("state") != "SEARCHING" or ride_after.get("assignedDriverId"):
        print("FAIL ride_state_changed")
        return 1
    if ride_after.get("requestVersion") != 1:
        print("FAIL request_version", ride_after.get("requestVersion"))
        return 1

    amt = o.get("amountMinor")
    print("PASS", json.dumps({
        "rideId": RID,
        "offerId": o.get("offerId"),
        "driverId": o.get("driverId"),
        "amountMinor": amt,
        "amountHuman": f"Rs {amt // 100}" if isinstance(amt, int) else None,
        "status": o.get("state") or o.get("status"),
        "requestVersion": o.get("requestVersion"),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
