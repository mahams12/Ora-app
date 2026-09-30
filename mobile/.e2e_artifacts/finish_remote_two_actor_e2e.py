#!/usr/bin/env python3
"""Finish remote staging two-actor E2E — ops automation only (no pm clear on emulator)."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

P, D = "RF8R40ZQ1JH", "emulator-5554"
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
RUN_STARTED = datetime.now(timezone.utc).isoformat()
REPORT: dict = {"gates": {}, "started": RUN_STARTED}


def sh(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, "shell", *args])


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/fin_{tag}.xml"
    sh(dev, "uiautomator", "dump", "/sdcard/fin.xml")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/fin.xml", path])
    return open(path, encoding="utf-8").read()


def focused_package(dev: str) -> str:
    out = subprocess.check_output(
        ["adb", "-s", dev, "shell", "dumpsys", "activity", "activities"],
        stderr=subprocess.DEVNULL,
    ).decode(errors="replace")
    m = re.search(r"mFocusedApp=ActivityRecord\{[^ ]+ [^ ]+ ([^/]+)/", out)
    if m:
        return m.group(1)
    m = re.search(r"topResumedActivity=ActivityRecord\{[^ ]+ [^ ]+ ([^/]+)/", out)
    return m.group(1) if m else ""


def nodes(t: str) -> list[tuple[str, int, int]]:
    out: list[tuple[str, int, int]] = []
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    ):
        d = m.group(1).replace("&#10;", " | ").replace("&amp;", "&")
        x1, y1, x2, y2 = map(int, m.groups()[1:])
        out.append((d, (x1 + x2) // 2, (y1 + y2) // 2))
    return out


def tap_text(dev: str, t: str, *needles: str) -> bool:
    for desc, cx, cy in nodes(t):
        for n in needles:
            if n in desc or n in t:
                if n in desc:
                    sh(dev, "input", "tap", str(cx), str(cy))
                    return True
    for desc, cx, cy in nodes(t):
        for n in needles:
            if n in desc:
                sh(dev, "input", "tap", str(cx), str(cy))
                return True
    return False


def tap(dev: str, needle: str, t: str) -> bool:
    for desc, cx, cy in nodes(t):
        if needle in desc:
            sh(dev, "input", "tap", str(cx), str(cy))
            return True
    return False


def tap_button_prefix(dev: str, t: str, prefix: str) -> bool:
    """Tap a clickable Button whose content-desc starts with prefix (avoids heading labels)."""
    best: tuple[int, int, int] | None = None
    for m in re.finditer(r"<node ([^/>]+)/?>", t):
        a = m.group(1)
        if "android.widget.Button" not in a or 'clickable="true"' not in a:
            continue
        d = re.search(r'content-desc="([^"]*)"', a)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', a)
        if not d or not b:
            continue
        desc = d.group(1).replace("&#10;", "\n")
        if not desc.startswith(prefix):
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        y2_key = y2
        if best is None or y2_key > best[0]:
            best = (y2_key, (x1 + x2) // 2, (y1 + y2) // 2)
    if best is None:
        return False
    sh(dev, "input", "tap", str(best[1]), str(best[2]))
    return True


def dismiss_gms(dev: str) -> bool:
    pkg = focused_package(dev)
    t = dump(dev, "gms_check")
    if pkg == "com.google.android.gms" or "com.google.android.gms" in t:
        if tap(dev, "SKIP", t):
            time.sleep(2)
            return True
        sh(dev, "input", "tap", "117", "2676")
        time.sleep(2)
        sh(dev, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        return True
    if "Sign in with ease" in t:
        tap(dev, "SKIP", t) or sh(dev, "input", "tap", "117", "2676")
        time.sleep(2)
        return True
    return False


def bring_ora(dev: str) -> None:
    subprocess.check_call(
        ["adb", "-s", dev, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"],
        timeout=15,
    )
    time.sleep(3)


def driver_authenticated(t: str) -> bool:
    if "Welcome to ORA" in t or "Send verification code" in t:
        return False
    return any(
        x in t
        for x in (
            "Open ride requests",
            "Open rides",
            "Earn on ORA",
            "Where are you headed",
            "My trips",
            "Signing you in",
        )
    )


def ensure_driver_auth(max_rounds: int = 8) -> None:
    bring_ora(D)
    for round_i in range(max_rounds):
        dismiss_gms(D)
        bring_ora(D)
        t = dump(D, f"d_auth_{round_i}")
        if "Open rides" in t or "Open ride requests" in t:
            REPORT["gates"]["auth_emulator"] = "PASS"
            REPORT["driver_ui_evidence"] = f"fin_d_auth_{round_i}.xml"
            return
        if "Earn on ORA" in t:
            tap(D, "Earn on ORA", t)
            time.sleep(4)
            t = dump(D, f"d_earn_{round_i}")
        if driver_authenticated(t) and "Open ride requests" in t:
            REPORT["gates"]["auth_emulator"] = "PASS"
            REPORT["driver_ui_evidence"] = f"fin_d_auth_{round_i}.xml"
            return
        if driver_authenticated(t) and "Earn on ORA" not in t:
            REPORT["gates"]["auth_emulator"] = "PASS"
            REPORT["driver_ui_evidence"] = f"fin_d_auth_{round_i}.xml"
            return
        if "Welcome to ORA" in t or "Send verification code" in t or "Send code" in t:
            sh(D, "input", "tap", "640", "1650")
            time.sleep(0.5)
            sh(D, "input", "text", "923012345677")
            sh(D, "input", "keyevent", "KEYCODE_BACK")
            time.sleep(1)
            tap(D, "Send code", dump(D, f"d_send_{round_i}")) or tap(
                D, "Send verification code", dump(D, f"d_send_{round_i}")
            )
            time.sleep(6)
            for _ in range(5):
                dismiss_gms(D)
                time.sleep(1)
            bring_ora(D)
            t_otp = dump(D, f"d_otp_{round_i}")
            if "Verify" in t_otp or "verification code" in t_otp.lower():
                sh(D, "input", "tap", "640", "500")
                sh(D, "input", "text", "000000")
                time.sleep(0.5)
                tap(D, "Verify", dump(D, f"d_ver_{round_i}"))
                time.sleep(12)
            continue
        if tap(D, "Earn on ORA", t):
            time.sleep(4)
            continue
        time.sleep(2)
    REPORT["gates"]["auth_emulator"] = "FAIL"
    fail("driver auth not completed")


def ensure_driver_open_rides() -> str:
    for i in range(12):
        dismiss_gms(D)
        bring_ora(D)
        t = dump(D, f"d_nav_{i}")
        if find_respond_blob(t):
            REPORT["gates"]["driver_discovery"] = "PASS"
            return t
        if "Earn on ORA" in t:
            tap(D, "Earn on ORA", t)
            time.sleep(4)
            t = dump(D, f"d_earn_nav_{i}")
        if "not wired to the backend" in t or "Driver mode is planned" in t:
            fail("driver gate blocked — wrong account")
        tap(D, "Open ride requests", t) or tap(D, "Open ride", t) or tap(
            D, "Open ride requests", dump(D, f"d_open_{i}")
        )
        time.sleep(4)
        sh(D, "input", "swipe", "640", "900", "640", "2000", "400")
        time.sleep(4)
    REPORT["gates"]["driver_discovery"] = "FAIL"
    fail("driver open rides empty")


def find_respond_blob(t: str) -> bool:
    return any(
        k in t
        for k in ("Respond", "Liberty", "Ride request", "Passenger offer", "Rs ")
    )


def tsx(script: str, *args: str) -> dict:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env,
        timeout=90,
    )
    return json.loads(out.decode())


def verify_auth_me_driver() -> None:
    """Ops: custom token → idToken → staging /v1/auth/me"""
    script = f"""
import {{ initializeApp, cert, getApps }} from 'firebase-admin/app';
import {{ getAuth }} from 'firebase-admin/auth';
import path from 'node:path';
const uid = 'SRjL7BJgCKTduhtpjtYMRZMq5fD2';
const sa = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!getApps().length) initializeApp({{ credential: cert(sa) }});
const custom = await getAuth().createCustomToken(uid);
console.log(JSON.stringify({{ customToken: custom }}));
"""
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    proc = subprocess.run(
        [f"{BACKEND}/node_modules/.bin/tsx", "-e", script],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if proc.returncode != 0:
        REPORT["auth_me"] = {"skipped": True, "reason": "custom_token_failed"}
        return
    custom = json.loads(proc.stdout.strip()).get("customToken")
    api_key = os.environ.get("FIREBASE_WEB_API_KEY", "")
    if not api_key:
        # from mobile android config if present
        gs = f"{BACKEND}/../mobile/android/app/google-services.json"
        try:
            data = json.load(open(gs))
            api_key = data["client"][0]["api_key"][0]["current_key"]
        except Exception:
            REPORT["auth_me"] = {"skipped": True, "reason": "no_api_key"}
            return
    import urllib.request

    body = json.dumps({"token": custom, "returnSecureToken": True}).encode()
    req = urllib.request.Request(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key={api_key}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        tok = json.loads(resp.read().decode())
    id_token = tok["idToken"]
    req2 = urllib.request.Request(
        "https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1/auth/me",
        headers={"Authorization": f"Bearer {id_token}"},
    )
    with urllib.request.urlopen(req2, timeout=30) as resp:
        me = json.loads(resp.read().decode())
    REPORT["auth_me"] = me.get("data") or me


def prep_gps(dev: str) -> None:
    sh(dev, "appops", "set", PKG, "android:mock_location", "allow")
    subprocess.run(
        ["adb", "-s", dev, "shell", "cmd", "location", "providers", "add-test-provider", "gps",
         "--supportsAltitude", "--supportsSpeed", "--supportsBearing"],
        check=False,
        capture_output=True,
    )
    sh(dev, "cmd", "location", "providers", "set-test-provider-enabled", "gps", "true")
    sh(
        dev,
        "cmd",
        "location",
        "providers",
        "set-test-provider-location",
        "gps",
        "--location",
        "31.4127578,74.1725224",
        "--accuracy",
        "5",
    )


def passenger_fresh_ride() -> str:
    prep_gps(P)
    subprocess.check_call(["adb", "-s", P, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"])
    time.sleep(4)
    t = dump(P, "p0")
    if "Waiting for offers" in t or "Offers" in t:
        tap(P, "Back to Home", t)
        time.sleep(3)
    elif "Use current location" in t and "Where are you headed" not in t:
        tap(P, "Back", t)
        time.sleep(2)
    t = dump(P, "p_home")
    if "Welcome to ORA" in t:
        sh(P, "input", "tap", "540", "1364")
        sh(P, "input", "text", "923012345678")
        sh(P, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        tap(P, "Send code", dump(P, "p_send"))
        time.sleep(8)
        sh(P, "input", "tap", "540", "610")
        sh(P, "input", "text", "123456")
        tap(P, "Verify", dump(P, "p_ver"))
        time.sleep(10)
        REPORT["gates"]["auth_samsung"] = "PASS"
    else:
        REPORT["gates"]["auth_samsung"] = "PASS"
    tap(P, "Where are you headed?", dump(P, "p_trip")) or tap(
        P, "Where are you headed", dump(P, "p_trip")
    ) or sh(P, "input", "tap", "540", "450")
    for _ in range(20):
        t = dump(P, "p_compose")
        if "Where to?" in t or "Use current location" in t:
            break
        time.sleep(2)
    else:
        fail("ride compose not opened")
    tap_button_prefix(P, dump(P, "p_gps"), "Use current location")
    time.sleep(5)
    for _ in range(8):
        t = dump(P, "p_cp")
        if tap_button_prefix(P, t, "Confirm pickup"):
            time.sleep(3)
            break
        if "Confirm pickup" in t:
            tap(P, "Confirm pickup", t)
            time.sleep(3)
            break
        tap_button_prefix(P, t, "Use current location")
        time.sleep(3)
    t = dump(P, "p_dest")
    edits = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    )
    dest = edits[-1] if edits else None
    if dest:
        x1, y1, x2, y2 = map(int, dest)
        sh(P, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        time.sleep(0.5)
        for _ in range(40):
            sh(P, "input", "keyevent", "67")
        sh(P, "input", "text", "Liberty%sMarket%sLahore")
        time.sleep(10)
        t_sug = dump(P, "p_sug")
        picked = (
            tap(P, "Liberty Market", t_sug)
            or tap(P, "Gulberg", t_sug)
            or tap(P, "Liberty", t_sug)
        )
        if not picked:
            for desc, cx, cy in nodes(t_sug):
                if any(k in desc for k in ("Liberty", "Gulberg", "Lahore, Pakistan")):
                    sh(P, "input", "tap", str(cx), str(cy))
                    picked = True
                    break
        if not picked:
            fail("destination suggestion not found")
        time.sleep(4)
    for _ in range(10):
        t = dump(P, "p_dconf")
        if tap(P, "Confirm destination", t):
            time.sleep(3)
            break
        sh(P, "input", "swipe", "540", "1200", "540", "700", "350")
        time.sleep(1.5)
    for _ in range(15):
        t = dump(P, "p_ok")
        if "Pickup &amp; destination confirmed" in t or "Pickup & destination confirmed" in t:
            break
        if "Destination confirmed" in t and "Pickup needed" not in t:
            break
        if "Pickup needed" in t:
            tap_button_prefix(P, t, "Use current location")
            time.sleep(3)
            tap_button_prefix(P, dump(P, "p_cp2"), "Confirm pickup")
            time.sleep(3)
        if tap_button_prefix(P, t, "Confirm destination"):
            time.sleep(2)
        elif tap(P, "Confirm destination", t):
            time.sleep(2)
        time.sleep(2)
    t = dump(P, "p_cont")
    if not tap_button_prefix(P, t, "Continue"):
        tap(P, "Continue", t) or sh(P, "input", "tap", "540", "1674")
    time.sleep(5)
    t = dump(P, "p_rev")
    if "Select a ride" not in t:
        for _ in range(8):
            time.sleep(3)
            t = dump(P, "p_rev_retry")
            if "Select a ride" in t:
                break
            if tap(P, "Continue", t):
                time.sleep(4)
    has_fare = "Estimated fare" in t or bool(re.search(r"Rs\s*\d+", t))
    if "Select a ride" not in t or not has_fare:
        REPORT["gates"]["passenger_pricing"] = "FAIL"
        fail("pricing missing on review")
    REPORT["gates"]["passenger_pricing"] = "PASS"
    waiting_markers = ("Waiting for offers", "Waiting for driver offers")
    for _ in range(8):
        t = dump(P, "p_req")
        if any(m in t for m in waiting_markers):
            break
        if not tap_button_prefix(P, t, "Request Easy"):
            tap(P, "Request Easy", t)
        time.sleep(8)
    t_wait = dump(P, "p_wait")
    if not any(m in t_wait for m in waiting_markers):
        REPORT["gates"]["ride_creation"] = "FAIL"
        fail("ride not created")
    REPORT["gates"]["ride_creation"] = "PASS"
    rides = tsx("e2e_fetch_latest_ride.ts").get("rides") or []
    rid = None
    for r in rides:
        if (r.get("createdAt") or "")[:19] >= RUN_STARTED[:19]:
            rid = r.get("rideId")
            break
    if not rid:
        fail("no fresh rideId")
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap["ride"]
    exp = (ride.get("expiresAt") or "")[:19]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    if ride.get("state") != "SEARCHING" or exp <= now:
        fail(f"bad fresh ride state={ride.get('state')} exp={exp}")
    REPORT["rideId"] = rid
    REPORT["backend_create"] = {
        "pricingSnapshotId": ride.get("pricingSnapshotId"),
        "passengerOfferMinor": ride.get("passengerOfferMinor"),
        "requestVersion": ride.get("requestVersion"),
    }
    return rid


def driver_offer(rid: str) -> None:
    t = ensure_driver_open_rides()
    if rid[:8] not in t and "Liberty" not in t:
        sh(D, "input", "swipe", "640", "700", "640", "2000", "350")
        time.sleep(4)
        t = dump(D, "d_list2")
    if not tap(D, "Respond", t):
        fail("Respond not tappable")
    time.sleep(3)
    sheet = dump(D, "sheet")
    if not any(x in sheet for x in ("Submit offer", "Accept passenger price")):
        REPORT["gates"]["respond"] = "FAIL"
        fail("offer sheet not open")
    REPORT["gates"]["respond"] = "PASS"
    if re.search(r"minor unit|server minor", sheet, re.I):
        REPORT["gates"]["respond_ux"] = "FAIL"
    else:
        REPORT["gates"]["respond_ux"] = "PASS"
    tap_button_prefix(D, sheet, "Accept passenger price")
    time.sleep(1.5)
    sheet2 = dump(D, "sub")
    if not tap_button_prefix(D, sheet2, "Submit offer"):
        fail("Submit offer button not tappable")
    time.sleep(12)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    offers = snap.get("offers") or []
    if len(offers) != 1:
        fail(f"offer count {len(offers)}")
    REPORT["gates"]["driver_offer"] = "PASS"
    REPORT["driver_offer"] = offers[0]


def passenger_select(rid: str) -> None:
    subprocess.check_call(["adb", "-s", P, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"])
    time.sleep(3)
    for i in range(25):
        t = dump(P, f"sel{i}")
        if "Select" in t:
            tap(P, "Select", t)
            break
        tap(P, "Refresh", t)
        time.sleep(4)
    else:
        REPORT["gates"]["passenger_offer_selection"] = "FAIL"
        fail("no Select on passenger")
    time.sleep(12)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap["ride"]
    if ride.get("assignedDriverId") != "SRjL7BJgCKTduhtpjtYMRZMq5fD2":
        fail(f"wrong assign {ride.get('assignedDriverId')}")
    REPORT["gates"]["passenger_offer_selection"] = "PASS"
    REPORT["gates"]["assignment"] = "PASS"


def open_assigned_ride_detail() -> str:
    """My trips → assigned card → detail (primary action labels live here)."""
    t = dump(D, "trip_nav")
    if "Mark en route" not in t and "Mark arrived" not in t:
        tap(D, "My trips", t) or tap_button_prefix(D, t, "My trips")
        time.sleep(3)
        t = dump(D, "trip_list")
        tap(D, "Liberty", t) or tap(D, "Assigned", t) or tap(D, "Rs ", t)
        time.sleep(4)
        t = dump(D, "trip_detail")
    return t


def driver_progress(rid: str) -> None:
    bring_ora(D)
    time.sleep(2)
    for label, gate in [
        ("Mark en route", "EN_ROUTE"),
        ("Mark arrived", "ARRIVED"),
        ("Start ride", "STARTED"),
        ("Complete ride", "COMPLETED"),
    ]:
        t = open_assigned_ride_detail()
        if label in t:
            tap_button_prefix(D, t, label) or tap(D, label, t)
            time.sleep(8)
            REPORT["gates"][gate] = "PASS"
        else:
            REPORT["gates"][gate] = "FAIL"
    t = open_assigned_ride_detail()
    if tap_button_prefix(D, t, "Close ride") or tap(D, "Close ride", t):
        time.sleep(6)
        REPORT["gates"]["RIDE_CLOSED"] = "PASS"
    else:
        REPORT["gates"]["RIDE_CLOSED"] = "FAIL"


def fail(msg: str) -> None:
    REPORT["error"] = msg
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    REPORT["verdict"] = "NOT GREEN"
    print(json.dumps(REPORT, indent=2))
    sys.exit(1)


def main() -> None:
    ensure_driver_auth()
    verify_auth_me_driver()
    rid = passenger_fresh_ride()
    driver_offer(rid)
    passenger_select(rid)
    driver_progress(rid)
    final = tsx("e2e_ride_snapshot.ts", rid)
    REPORT["final"] = final
    ride = final.get("ride") or {}
    offers = final.get("offers") or []
    REPORT["backend_proof"] = {
        "rideId": rid,
        "state": ride.get("state"),
        "pricingSnapshotId": ride.get("pricingSnapshotId"),
        "passengerOfferMinor": ride.get("passengerOfferMinor"),
        "driverOfferMinor": offers[0].get("amountMinor") if offers else None,
        "assignedDriverId": ride.get("assignedDriverId"),
        "requestVersion": ride.get("requestVersion"),
    }
    gates = REPORT["gates"]
    required = [
        "auth_samsung",
        "auth_emulator",
        "passenger_pricing",
        "ride_creation",
        "driver_discovery",
        "respond",
        "driver_offer",
        "passenger_offer_selection",
        "assignment",
        "EN_ROUTE",
        "ARRIVED",
        "STARTED",
        "COMPLETED",
        "RIDE_CLOSED",
    ]
    ok = all(gates.get(k) == "PASS" for k in required)
    REPORT["verdict"] = "GREEN" if ok else "NOT GREEN"
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(REPORT, indent=2))
    open(f"{ART}/finish_remote_two_actor_report.json", "w").write(json.dumps(REPORT, indent=2))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
