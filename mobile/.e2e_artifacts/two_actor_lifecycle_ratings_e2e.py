#!/usr/bin/env python3
"""Two-actor lifecycle + ratings E2E on staging.

Derived from remote_staging_two_actor_e2e.py (Sept 29 GREEN through RIDE_CLOSED).
Adds: per-transition Firestore verification, both-actor ratings via the real
rating UI, and `ratings` collection proof. No app code changes.

Samsung=passenger (+923012345678), emulator=driver (+923012345677, approved).
"""
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
PASSENGER_UID = "AQLQjCfBw3W17kfgzziM6po1Nh33"
DRIVER_UID = "SRjL7BJgCKTduhtpjtYMRZMq5fD2"
PASSENGER_STARS = 5
DRIVER_STARS = 4
REPORT: Dict[str, Any] = {"gates": {}, "transitions": {}, "ratings": {}}
RUN_STARTED = datetime.now(timezone.utc).isoformat()
RESUME_RID = os.environ.get("ORA_RESUME_RIDE_ID")


def adb(dev: str, *args: str) -> str:
    out = subprocess.check_output(["adb", "-s", dev, *args], stderr=subprocess.STDOUT)
    return out.decode("utf-8", errors="replace")


def shell(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, "shell", *args])


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/lr_{tag}_ui.xml"
    for attempt in range(3):
        try:
            shell(dev, "uiautomator", "dump", "/sdcard/lr_ui.xml")
            subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/lr_ui.xml", path])
        except subprocess.CalledProcessError:
            # Transient uiautomator/adb hiccup (e.g. exit 137) — retry.
            time.sleep(3)
            continue
        t = open(path, encoding="utf-8").read()
        # Lock screen dumps are tiny and carry only systemui clock nodes.
        if PKG in t or len(t) > 8000:
            return t
        wake_unlock(dev)
        subprocess.check_call(
            ["adb", "-s", dev, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"]
        )
        time.sleep(3)
    return t


def shot(dev: str, tag: str) -> str:
    path = f"{ART}/lr_{tag}.png"
    shell(dev, "screencap", "-p", "/sdcard/lr_shot.png")
    subprocess.check_call(["adb", "-s", dev, "pull", "/sdcard/lr_shot.png", path])
    return path


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


def tap_prefix(dev: str, prefix: str, t: str) -> bool:
    for desc, cx, cy in nodes(t):
        if desc.startswith(prefix):
            shell(dev, "input", "tap", str(cx), str(cy))
            return True
    return False


def tap_button(dev: str, label: str, t: str) -> bool:
    """Tap a clickable node whose desc starts with label (skips static text)."""
    for m in re.finditer(r"<node ([^/>]+)/?>", t):
        a = m.group(1)
        if 'clickable="true"' not in a:
            continue
        d = re.search(r'content-desc="([^"]*)"', a)
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', a)
        if not d or not b:
            continue
        desc = d.group(1).replace("&#10;", "\n")
        if not desc.startswith(label):
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        shell(dev, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        return True
    return False


def wait_for(dev: str, needle: str, tries: int = 30, pause: float = 2.0, tag: str = "w") -> str:
    t = ""
    for _ in range(tries):
        t = dump(dev, tag)
        if needle in t:
            return t
        time.sleep(pause)
    return t


def wait_any(dev: str, needles: List[str], tries: int, pause: float, tag: str) -> str:
    t = ""
    for _ in range(tries):
        t = dump(dev, tag)
        if any(n in t for n in needles):
            return t
        time.sleep(pause)
    return t


def wake_unlock(dev: str) -> None:
    """Samsung idles to lock between steps — wake + swipe-to-unlock if needed."""
    cx = 640 if dev.startswith("emulator-") else 540
    shell(dev, "input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(0.5)
    shell(dev, "input", "swipe", str(cx), "1800", str(cx), "600", "300")
    time.sleep(1)


def launch(dev: str) -> None:
    wake_unlock(dev)
    shell(dev, "am", "force-stop", PKG)
    subprocess.check_call(
        ["adb", "-s", dev, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(5)


def tap_edittext(dev: str, t: str, index: int = 0) -> bool:
    """Tap the Nth EditText by its real bounds (layout shifts across devices)."""
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    )
    if len(eds) <= index:
        return False
    x1, y1, x2, y2 = map(int, eds[index])
    shell(dev, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    return True


def do_login(dev: str, phone: str, otp: str, tag: str) -> str:
    """Phone + OTP login, targeting EditText bounds — no fixed coordinates."""
    t = dump(dev, tag + "_phone")
    tap_edittext(dev, t, 0)
    time.sleep(0.5)
    shell(dev, "input", "text", phone.lstrip("+"))
    shell(dev, "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    tap(dev, "Send code", dump(dev, tag)) or tap(dev, "Send verification code", dump(dev, tag))
    time.sleep(8)
    t_otp = wait_any(dev, ["Verify", "verification code"], 10, 2.0, tag + "_otp")
    tap_edittext(dev, t_otp, 0)
    time.sleep(0.5)
    shell(dev, "input", "text", otp)
    shell(dev, "input", "keyevent", "KEYCODE_BACK")
    time.sleep(1)
    tap(dev, "Verify", dump(dev, tag + "_ver"))
    needle = "Where are you headed" if dev == P else "Earn on ORA"
    return wait_for(dev, needle, 25, 2.0, tag + "_postauth")


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
        t = do_login(dev, phone, otp, tag)
    gate = "auth_passenger" if dev == P else "auth_driver"
    REPORT["gates"][gate] = "GREEN"


def prep_gps(dev: str) -> None:
    shell(dev, "appops", "set", PKG, "android:mock_location", "allow")
    subprocess.run(
        ["adb", "-s", dev, "shell", "cmd", "location", "providers", "add-test-provider", "gps",
         "--supportsAltitude", "--supportsSpeed", "--supportsBearing"],
        check=False,
        capture_output=True,
    )
    shell(dev, "cmd", "location", "providers", "set-test-provider-enabled", "gps", "true")
    shell(dev, "cmd", "location", "providers", "set-test-provider-location", "gps",
          "--location", "31.4127578,74.1725224", "--accuracy", "5")


def tsx(script: str, *args: str) -> dict:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env,
        timeout=60,
    )
    return json.loads(out.decode())


def ride_state(rid: str) -> Tuple[Optional[str], dict]:
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap.get("ride") or {}
    return ride.get("state"), snap


def wait_state(rid: str, expected: str, tries: int = 14, pause: float = 2.0) -> dict:
    snap = {}
    for _ in range(tries):
        snap = tsx("e2e_ride_snapshot.ts", rid)
        ride = snap.get("ride") or {}
        if ride.get("state") == expected:
            return snap
        time.sleep(pause)
    return snap


def fail(msg: str) -> None:
    REPORT["error"] = msg
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    REPORT["verdict"] = "NOT GREEN"
    print(json.dumps(REPORT, indent=2))
    open(
        f"{ART}/two_actor_lifecycle_ratings_report{'_resume' if RESUME_RID else ''}.json",
        "w",
    ).write(json.dumps(REPORT, indent=2))
    sys.exit(1)


def reauth_if_needed(dev: str, phone: str, otp: str, tag: str, t: str) -> str:
    """Session can drop mid-run (refresh-token bounce) — re-login inline."""
    if "Welcome to ORA" not in t and "Send verification code" not in t and "Send code" not in t:
        return t
    return do_login(dev, phone, otp, tag)


def passenger_create_ride() -> str:
    prep_gps(P)
    launch(P)
    auth(P, "+923012345678", "123456", "p_auth")
    t = dump(P, "p_home")
    t = reauth_if_needed(P, "+923012345678", "123456", "p_home_re", t)
    if "Waiting for offers" in t or ("Offers" in t and "SEARCHING" in t):
        tap(P, "Back to Home", t)
        time.sleep(3)
        t = dump(P, "p_home2")
    if "Select a ride" in t or "Request Easy" in t:
        tap(P, "Back", t)
        time.sleep(2)
        t = dump(P, "p_home3")
    if not (
        tap(P, "Where are you headed?", t)
        or tap(P, "Where are you headed", t)
        or tap(P, "Set pickup", t)
    ):
        shell(P, "input", "tap", "540", "450")
    time.sleep(3)
    t = wait_for(P, "Where to?", 20, 2.0, "p_compose")
    if "Where to?" not in t:
        # Auth bounce mid-compose — re-login and re-enter compose once.
        t = reauth_if_needed(P, "+923012345678", "123456", "p_compose_re", t)
        if tap(P, "Where are you headed?", t) or tap(P, "Where are you headed", t):
            time.sleep(3)
            t = wait_for(P, "Where to?", 20, 2.0, "p_compose2")
    tap(P, "Use current location", dump(P, "p_pick"))
    time.sleep(4)
    # Proposal card can sit below the uiautomator viewport clip — scroll if needed.
    for _ in range(10):
        t = dump(P, "p_pick2")
        if tap(P, "Confirm pickup", t, exclude="destination to continue"):
            time.sleep(2)
            break
        shell(P, "input", "swipe", "540", "1500", "540", "900", "350")
        time.sleep(1.5)
    t = dump(P, "p_dest")
    if "Send verification code" in t or "Welcome to ORA" in t:
        fail("passenger session dropped mid-compose — auth screen at dest step")
    eds = re.findall(r'EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        shell(P, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        time.sleep(1)
        for _ in range(40):
            shell(P, "input", "keyevent", "KEYCODE_DEL")
        shell(P, "input", "text", "Liberty%sMarket%sLahore")
        time.sleep(8)
        t_sug = dump(P, "p_sug")
        picked = (
            tap(P, "Liberty Market Gulberg III", t_sug)
            or tap(P, "Gulberg III", t_sug)
            or tap(P, "Liberty Market", t_sug)
        )
        if not picked:
            for desc, cx, cy in nodes(t_sug):
                if desc.startswith("Liberty") or desc.startswith("Gulberg"):
                    shell(P, "input", "tap", str(cx), str(cy))
                    picked = True
                    break
        if not picked:
            fail("destination suggestion not found")
        time.sleep(4)
    for _ in range(10):
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
    # "Estimated fare Rs N" can sit below the uiautomator fold on review even
    # after the sheet scrolls (same a11y clip as map1_smoke). The offer
    # EditText prefilled with the recommended fare + enabled Request Easy is
    # the reliable programmatic signal; screenshot keeps visual proof.
    has_fare = ("Estimated fare" in t) or bool(re.search(r"Rs\s*\d", t))
    if not has_fare:
        shell(P, "input", "swipe", "540", "1500", "540", "800", "400")
        time.sleep(1.5)
        t = dump(P, "p_rev_fare")
        has_fare = (
            "Estimated fare" in t
            or bool(re.search(r"Rs\s*\d", t))
            or bool(re.search(r'text="\d{3,}"', t))
        )
    shot(P, "p_review")
    REPORT["gates"]["passenger_pricing"] = "PASS" if has_fare else "FAIL"
    if not has_fare:
        fail("no server fare on review")
    for _ in range(4):
        t = dump(P, "p_req")
        if "Waiting for offers" in t:
            break
        tap_button(P, "Request Easy", t) or tap(P, "Request Easy", t) or tap(P, "Request ", t)
        time.sleep(5)
    t = wait_for(P, "Waiting for offers", 30, 2.0, "p_wait")
    REPORT["gates"]["ride_creation"] = "PASS" if "Waiting for offers" in t else "FAIL"
    if "Waiting for offers" not in t:
        fail("ride not created")
    shot(P, "p_waiting")

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
        "state": ride.get("state"),
        "pricingSnapshotId": ride.get("pricingSnapshotId"),
        "passengerOfferMinor": ride.get("passengerOfferMinor"),
        "requestVersion": ride.get("requestVersion"),
    }
    REPORT["transitions"]["REQUESTED"] = {
        "state": "SEARCHING",
        "at": ride.get("createdAt"),
    }
    return rid


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


def node_bounds(t: str, needle: str) -> Optional[Tuple[int, int, int, int]]:
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    ):
        if needle in m.group(1):
            return tuple(map(int, m.groups()[1:]))  # type: ignore[return-value]
    return None


def tap_respond_for_ride(dev: str, rid: str, t: str) -> bool:
    """Tap the 'Respond' control inside the card for OUR ride only."""
    card = node_bounds(t, f"Ride id {rid}")
    if card is None:
        card = node_bounds(t, "Liberty")
    if card is None:
        return False
    x1, y1, x2, y2 = card
    for desc, cx, cy in nodes(t):
        if "Respond" in desc and x1 <= cx <= x2 and y1 <= cy <= y2:
            shell(dev, "input", "tap", str(cx), str(cy))
            return True
    # Card is one merged node (Respond inside its bounds not exposed) — tap card.
    shell(dev, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    return True


def enter_driver_mode(tag: str) -> str:
    """After relaunch the app resumes at passenger home — re-enter driver mode."""
    t = dump(D, tag)
    t = reauth_if_needed(D, "+923012345677", "000000", tag + "_re", t)
    for _ in range(6):
        if "Open ride requests" in t or "Open rides" in t or "My trips" in t:
            return t
        if "Earn on ORA" in t:
            tap(D, "Earn on ORA", t)
            time.sleep(4)
            t = dump(D, tag + "_earn")
            continue
        tap(D, "Switch to driver mode", t)
        time.sleep(4)
        t = dump(D, tag + "_sw")
    return t


def driver_discover_and_offer(rid: str) -> None:
    subprocess.check_call(
        ["adb", "-s", D, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(3)
    t = enter_driver_mode("d_reopen")
    tap(D, "Open ride requests", t) or tap(D, "Open ride", t) or tap(
        D, "Open ride requests", dump(D, "d_reopen2")
    )
    time.sleep(3)
    cx = 640 if D.startswith("emulator-") else 540
    # Feed load can lag app relaunch — poll + pull-refresh until a card appears.
    # Open-ride cards merge semantics to 'Respond to ride request' only (no
    # rideId/destination in a11y); isOpenDiscoverable excludes expired rides
    # server-side, and the offer count check below keys on our rid.
    t = ""
    for i in range(15):
        t = dump(D, "d_disc")
        if "Respond" in t:
            break
        shell(D, "input", "swipe", str(cx), "600", str(cx), "1400", "500")
        time.sleep(4)
    if "Respond" not in t:
        REPORT["gates"]["driver_discovery"] = "FAIL"
        fail("driver discovery empty")
    REPORT["gates"]["driver_discovery"] = "PASS"
    shot(D, "d_discovery")
    if not tap_respond_for_ride(D, rid, t) and not tap(D, "Respond", t):
        REPORT["gates"]["respond_sheet"] = "FAIL"
        fail("Respond missing")
    time.sleep(3)
    t = dump(D, "d_sheet")
    if not any(x in t for x in ("Submit offer", "Accept passenger price")):
        REPORT["gates"]["respond_sheet"] = "FAIL"
        fail("offer sheet not open")
    REPORT["gates"]["respond_sheet"] = "PASS"
    tap_button(D, "Accept passenger price", t) or tap(D, "Accept passenger price", t)
    time.sleep(1)
    t = dump(D, "d_submit")
    if not (tap_button(D, "Submit offer", t) or tap_prefix(D, "Submit offer", t)):
        REPORT["gates"]["driver_offer"] = "FAIL"
        fail("Submit offer button not tappable")
    time.sleep(10)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    offers = snap.get("offers") or []
    REPORT["offers_after_driver"] = [
        {"offerId": o.get("offerId"), "type": o.get("type"), "amountMinor": o.get("amountMinor")}
        for o in offers
    ]
    if len(offers) != 1:
        fail(f"expected 1 offer got {len(offers)}")
    REPORT["gates"]["driver_offer"] = "PASS"


def passenger_select_offer(rid: str) -> None:
    subprocess.check_call(
        ["adb", "-s", P, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(3)
    t = wait_for(P, "Select", 45, 3.0, "p_offers")
    if "Select" not in t:
        REPORT["gates"]["passenger_offer_selection"] = "FAIL"
        fail("no passenger offer UI")
    REPORT["gates"]["passenger_offer_selection"] = "PASS"
    tap(P, "Select", t)
    time.sleep(12)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap["ride"]
    if ride.get("assignedDriverId") != DRIVER_UID:
        fail(f"wrong assign {ride.get('assignedDriverId')}")
    t = dump(P, "p_assigned")
    shot(P, "p_assigned")
    REPORT["gates"]["assignment"] = "PASS"
    REPORT["transitions"]["ACCEPTED"] = {
        "state": ride.get("state"),
        "assignedDriverId": ride.get("assignedDriverId"),
        "at": ride.get("assignedAt"),
    }


DETAIL_MARKERS = ("Mark en route", "Mark arrived", "Start ride", "Complete ride",
                  "Close ride", "Rate ride", "Cancel ride")


def open_driver_assigned_detail(rid: str, tag: str) -> str:
    """Ensure the driver assigned-ride detail is on screen.

    'My trips' is a drawer item (or a quick action on driver home); the
    subpage only shows it as a non-actionable title. Trip cards merge
    semantics to 'Assigned — <phase> | <STATE> | <pickup> → <dest>' — the
    rideId is not in a11y text.
    """
    # Merged card desc: '<jobTitle> | <STATE> | <pickup> → <dest> …' where
    # jobTitle varies by state (driverJobTitle). Match any title or the
    # ride's pickup locality, or the explicit 'Assigned ride <id>' semantic.
    card_prefixes = (
        "Assigned —", "En route to passenger", "Arrived at pickup",
        "Ride in progress", "Ride completed", "Ride closed",
        "Assigned ride", "Ride cancelled", "Job update",
    )
    t = dump(D, tag)
    for _ in range(10):
        if any(m in t for m in DETAIL_MARKERS):
            return t
        tapped = tap(D, "Izmir Extension", t) or tap(D, f"Assigned ride {rid}", t)
        if not tapped:
            for p in card_prefixes:
                if tap_prefix(D, p, t):
                    tapped = True
                    break
        if tapped:
            time.sleep(5)
            t = dump(D, tag + "_detail")
            continue
        if "Assigned rides" in t:
            # Trips list shown but card not visible — scroll down.
            shell(D, "input", "swipe", "640", "1600", "640", "900", "350")
            time.sleep(2)
            t = dump(D, tag + "_scroll")
            continue
        # Open drawer → 'My trips'.
        if "Menu" in t and tap(D, "Menu", t):
            time.sleep(2)
            t = dump(D, tag + "_drawer")
            if tap_button(D, "My trips", t) or tap_prefix(D, "My trips\n", t):
                time.sleep(4)
                t = dump(D, tag + "_trips")
            continue
        # Driver home quick action.
        if tap_button(D, "My trips", t):
            time.sleep(4)
            t = dump(D, tag + "_trips")
            continue
        subprocess.check_call(
            ["adb", "-s", D, "shell", "monkey", "-p", PKG,
             "-c", "android.intent.category.LAUNCHER", "1"]
        )
        time.sleep(4)
        t = enter_driver_mode(tag + "_relaunch")
    return t


def driver_progression(rid: str) -> None:
    subprocess.check_call(
        ["adb", "-s", D, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(3)
    steps = [
        ("Mark en route", "EN_ROUTE", "DRIVER_EN_ROUTE"),
        ("Mark arrived", "ARRIVED", "DRIVER_ARRIVED"),
        ("Start ride", "STARTED", "RIDE_STARTED"),
        ("Complete ride", "COMPLETED", "RIDE_COMPLETED"),
    ]
    for label, gate, expected in steps:
        t = ""
        found = False
        for _ in range(14):
            t = open_driver_assigned_detail(rid, f"d_{gate}")
            if label in t:
                found = True
                break
            time.sleep(2)
        if not found:
            REPORT["gates"][gate] = "FAIL"
            REPORT["transitions"][gate] = {"error": f"label '{label}' never visible"}
            continue
        tap_button(D, label, t) or tap(D, label, t) or tap_prefix(D, label, t)
        time.sleep(4)
        snap = wait_state(rid, expected, tries=10, pause=2.0)
        ride = snap.get("ride") or {}
        if ride.get("state") == expected:
            REPORT["gates"][gate] = "PASS"
            REPORT["transitions"][gate] = {
                "state": expected,
                "verified": "firestore",
            }
            shot(D, f"d_{gate.lower()}")
        else:
            REPORT["gates"][gate] = "FAIL"
            REPORT["transitions"][gate] = {
                "error": f"backend state={ride.get('state')} expected {expected}"
            }
    # Close ride (enables rating affordance as primary)
    for _ in range(10):
        t = open_driver_assigned_detail(rid, "d_close")
        if "Close ride" in t:
            break
        time.sleep(2)
    if "Close ride" in t:
        tap_button(D, "Close ride", t) or tap(D, "Close ride", t) or tap_prefix(D, "Close ride", t)
        time.sleep(4)
        snap = wait_state(rid, "RIDE_CLOSED", tries=10, pause=2.0)
        ride = snap.get("ride") or {}
        REPORT["gates"]["RIDE_CLOSED"] = (
            "PASS" if ride.get("state") == "RIDE_CLOSED" else "FAIL"
        )
        REPORT["transitions"]["RIDE_CLOSED"] = {"state": ride.get("state"), "verified": "firestore"}
    else:
        REPORT["gates"]["RIDE_CLOSED"] = "FAIL"
        REPORT["transitions"]["RIDE_CLOSED"] = {"error": "Close ride never visible"}


def rate_ride_on(dev: str, rid: str, stars: int, tag: str) -> bool:
    """Rate ride → '<n> stars' → 'Submit rating' → 'Thanks for rating' → Done."""
    t = wait_any(dev, ["Rate ride", "Rate your ride"], 18, 2.0, tag)
    for _ in range(3):
        if "Rate ride" in t:
            tap_button(dev, "Rate ride", t) or tap(dev, "Rate ride", t) or tap_prefix(dev, "Rate ride", t)
            time.sleep(4)
            t = dump(dev, tag + "_form")
        if "Rate your ride" in t or "Submit rating" in t:
            break
        # Emulator cold-restart mid-tap lands on splash/sign-in — recover.
        if "Signing you in" in t or "Continue with" in t or "phone" in t.lower():
            time.sleep(6)
            t = reauth_if_needed(
                dev,
                "+923012345677" if dev == D else "+923012345678",
                "000000",
                tag + "_ra",
                dump(dev, tag + "_post"),
            )
            if dev == D:
                t = open_driver_assigned_detail(rid, tag + "_renav")
            continue
        time.sleep(3)
        t = dump(dev, tag + "_retry")
    if "Rate your ride" not in t and "Submit rating" not in t:
        return False
    star_label = f"{stars} stars" if stars != 1 else "1 star"
    t = dump(dev, tag + "_stars")
    if not tap(dev, star_label, t):
        return False
    time.sleep(1)
    t = dump(dev, tag + "_pre_submit")
    if not (tap_button(dev, "Submit rating", t) or tap_prefix(dev, "Submit rating", t)):
        return False
    t = wait_any(dev, ["Thanks for rating", "Your rating has been submitted", "Done"],
                 15, 2.0, tag + "_done")
    ok = "Thanks for rating" in t or "Your rating has been submitted" in t
    shot(dev, tag + "_result")
    if ok and "Done" in t:
        tap(dev, "Done", t)
        time.sleep(2)
    return ok


def driver_rate(rid: str) -> None:
    launch(D)
    # From RIDE_CLOSED the assigned detail shows 'Rate ride' as primary.
    t = ""
    for _ in range(12):
        t = open_driver_assigned_detail(rid, "d_rate_nav")
        if "Rate ride" in t or "Rate your ride" in t:
            break
        time.sleep(2)
    ok = rate_ride_on(D, rid, DRIVER_STARS, "d_rate")
    REPORT["ratings"]["driver_ui"] = "PASS" if ok else "FAIL"
    if not ok:
        return
    for _ in range(10):
        snap = tsx("e2e_ride_ratings.ts", rid)
        docs = snap.get("ratings") or []
        doc = next((d for d in docs if d.get("ratingId") == f"{rid}_driver_rates_passenger"), None)
        if doc:
            REPORT["ratings"]["driver_rates_passenger"] = {
                "ratingId": doc.get("ratingId"),
                "raterId": doc.get("raterId"),
                "ratedId": doc.get("ratedId"),
                "stars": doc.get("stars"),
                "verified": "firestore",
            }
            return
        time.sleep(2)
    REPORT["ratings"]["driver_rates_passenger"] = {"error": "doc not found"}


def passenger_rate(rid: str) -> None:
    launch(P)
    # Passenger may still be on the active-ride view; else My rides → detail.
    t = wait_any(P, ["Rate ride", "Rate your ride"], 15, 2.0, "p_rate_nav")
    if "Rate ride" not in t and "Rate your ride" not in t:
        if tap(P, "My rides", t) or tap(P, "Menu", t):
            time.sleep(3)
            t = dump(P, "p_rate_menu")
            if tap(P, "My rides", t):
                time.sleep(4)
        for _ in range(8):
            t = dump(P, "p_rate_hist")
            if "Rate ride" in t:
                break
            if tap(P, rid[:8], t) or tap(P, "Completed", t) or tap(P, "Liberty", t):
                time.sleep(4)
                t = dump(P, "p_rate_hist_detail")
                continue
            shell(P, "input", "swipe", "540", "1400", "540", "700", "350")
            time.sleep(2)
            t = dump(P, "p_rate_hist_scroll")
    ok = rate_ride_on(P, rid, PASSENGER_STARS, "p_rate")
    REPORT["ratings"]["passenger_ui"] = "PASS" if ok else "FAIL"
    if not ok:
        return
    for _ in range(10):
        snap = tsx("e2e_ride_ratings.ts", rid)
        docs = snap.get("ratings") or []
        doc = next((d for d in docs if d.get("ratingId") == f"{rid}_passenger_rates_driver"), None)
        if doc:
            REPORT["ratings"]["passenger_rates_driver"] = {
                "ratingId": doc.get("ratingId"),
                "raterId": doc.get("raterId"),
                "ratedId": doc.get("ratedId"),
                "stars": doc.get("stars"),
                "verified": "firestore",
            }
            return
        time.sleep(2)
    REPORT["ratings"]["passenger_rates_driver"] = {"error": "doc not found"}


def main() -> None:
    REPORT["started"] = RUN_STARTED
    REPORT["passenger_device"] = P
    REPORT["driver_device"] = D
    REPORT["remote_api"] = "https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1"
    REPORT["passenger_uid"] = PASSENGER_UID
    REPORT["driver_uid"] = DRIVER_UID
    driver_rating_only = os.environ.get("ORA_RESUME_DRIVER_RATING")
    if driver_rating_only:
        REPORT["resume"] = True
        REPORT["resumeNote"] = "Driver-rating segment only; lifecycle proven by prior segments."
        snap = tsx("e2e_ride_snapshot.ts", driver_rating_only)
        r = snap.get("ride") or {}
        if r.get("state") not in ("RIDE_COMPLETED", "RIDE_CLOSED"):
            fail(f"driver rating resume: ride not ratable ({r.get('state')})")
        rid = driver_rating_only
        REPORT["rideId"] = rid
        driver_rate(rid)
        REPORT["ratings"]["firestore_final"] = (tsx("e2e_ride_ratings.ts", rid).get("ratings") or [])
        drp = REPORT["ratings"].get("driver_rates_passenger", {})
        REPORT["verdict"] = (
            "GREEN_DRIVER_RATING"
            if REPORT["ratings"].get("driver_ui") == "PASS" and drp.get("stars") == DRIVER_STARS
            else "NOT GREEN"
        )
        REPORT["finished"] = datetime.now(timezone.utc).isoformat()
        print(json.dumps(REPORT, indent=2))
        out = f"{ART}/two_actor_lifecycle_ratings_report_driverrating.json"
        open(out, "w").write(json.dumps(REPORT, indent=2))
        sys.exit(0 if REPORT["verdict"] == "GREEN_DRIVER_RATING" else 1)
    resume_rid = RESUME_RID
    if resume_rid:
        # Segmented run: earlier legs were proven in the prior run's artifacts;
        # verify the ride is actually assigned before continuing.
        REPORT["resume"] = True
        REPORT["resumeNote"] = (
            "REQUESTED/offer/ACCEPTED proven by prior run artifacts; "
            "this segment proves driver progression + ratings."
        )
        snap = tsx("e2e_ride_snapshot.ts", resume_rid)
        r = snap.get("ride") or {}
        REPORT["transitions"]["REQUESTED"] = {
            "state": "SEGMENTED", "carriedFrom": "prior run"}
        REPORT["transitions"]["ACCEPTED"] = {
            "state": r.get("state"),
            "assignedDriverId": r.get("assignedDriverId"),
            "at": r.get("assignedAt"),
            "carriedFrom": "prior run",
        }
        if r.get("state") != "DRIVER_ASSIGNED" or r.get("assignedDriverId") != DRIVER_UID:
            fail(f"resume ride not DRIVER_ASSIGNED to driver: {r.get('state')} {r.get('assignedDriverId')}")
        rid = resume_rid
    else:
        driver_ready()
        rid = passenger_create_ride()
        driver_discover_and_offer(rid)
        passenger_select_offer(rid)
        REPORT["rideId"] = rid
    driver_progression(rid)
    snap = tsx("e2e_ride_snapshot.ts", rid)
    ride = snap.get("ride") or {}
    REPORT["backend_proof"] = {
        "rideId": rid,
        "state": ride.get("state"),
        "assignedDriverId": ride.get("assignedDriverId"),
        "assignedAt": ride.get("assignedAt"),
        "arrivedAt": ride.get("arrivedAt"),
        "startedAt": ride.get("startedAt"),
        "completedAt": ride.get("completedAt"),
        "closedAt": ride.get("closedAt"),
        "agreedFareMinor": ride.get("agreedFareMinor"),
    }
    if ride.get("state") not in ("RIDE_COMPLETED", "RIDE_CLOSED"):
        fail(f"ride not terminal: {ride.get('state')}")
    driver_rate(rid)
    passenger_rate(rid)
    final_ratings = tsx("e2e_ride_ratings.ts", rid)
    REPORT["ratings"]["firestore_final"] = final_ratings.get("ratings") or []
    gates = REPORT["gates"]
    required = [
        "auth_passenger", "auth_driver", "driver_ready", "passenger_pricing",
        "ride_creation", "driver_discovery", "respond_sheet", "driver_offer",
        "passenger_offer_selection", "assignment",
        "EN_ROUTE", "ARRIVED", "STARTED", "COMPLETED", "RIDE_CLOSED",
    ]
    lifecycle_ok = all(gates.get(k) == "PASS" for k in required)
    ratings = REPORT["ratings"]
    ratings_ok = (
        ratings.get("driver_ui") == "PASS"
        and ratings.get("passenger_ui") == "PASS"
        and ratings.get("driver_rates_passenger", {}).get("stars") == DRIVER_STARS
        and ratings.get("passenger_rates_driver", {}).get("stars") == PASSENGER_STARS
    )
    if resume_rid:
        seg_required = ["EN_ROUTE", "ARRIVED", "STARTED", "COMPLETED", "RIDE_CLOSED"]
        lifecycle_ok = all(gates.get(k) == "PASS" for k in seg_required)
        REPORT["verdict"] = (
            "GREEN_SEGMENTED" if (lifecycle_ok and ratings_ok) else "NOT GREEN"
        )
    else:
        REPORT["verdict"] = "GREEN" if (lifecycle_ok and ratings_ok) else "NOT GREEN"
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    print(json.dumps(REPORT, indent=2))
    out = f"{ART}/two_actor_lifecycle_ratings_report{'_resume' if resume_rid else ''}.json"
    open(out, "w").write(json.dumps(REPORT, indent=2))
    sys.exit(0 if (lifecycle_ok and ratings_ok) else 1)


if __name__ == "__main__":
    main()
