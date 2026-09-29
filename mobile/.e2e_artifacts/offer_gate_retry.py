#!/usr/bin/env python3
"""Targeted driver offer gate — ops only."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

D = "RF8R40ZQ1JH"
P = "emulator-5554"
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
OUT: Dict[str, Any] = {"started": datetime.now(timezone.utc).isoformat()}


def adb(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, *args])


def shell(dev: str, *args: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", dev, "shell", *args], stderr=subprocess.STDOUT
    ).decode("utf-8", errors="replace")


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/og_{tag}.xml"
    for attempt in range(3):
        shell(dev, "uiautomator", "dump", "/sdcard/og_ui.xml")
        subprocess.call(["adb", "-s", dev, "pull", "/sdcard/og_ui.xml", path])
        t = open(path, encoding="utf-8").read()
        if "hierarchy" in t and len(t) > 500:
            return t
        time.sleep(1.5)
    return t


def nodes(t: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for m in re.finditer(
        r'class="([^"]*)"[^>]*'
        r'content-desc="([^"]*)"[^>]*'
        r'clickable="(true|false)"[^>]*'
        r'enabled="(true|false)"[^>]*'
        r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        t,
    ):
        out.append(
            {
                "class": m.group(1),
                "desc": m.group(2).replace("&#10;", "\n"),
                "clickable": m.group(3) == "true",
                "enabled": m.group(4) == "true",
                "bounds": tuple(map(int, m.groups()[4:])),
            }
        )
    # alternate attribute order
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*'
        r'class="([^"]*)"[^>]*'
        r'clickable="(true|false)"[^>]*'
        r'enabled="(true|false)"[^>]*'
        r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        t,
    ):
        out.append(
            {
                "class": m.group(2),
                "desc": m.group(1).replace("&#10;", "\n"),
                "clickable": m.group(3) == "true",
                "enabled": m.group(4) == "true",
                "bounds": tuple(map(int, m.groups()[5:])),
            }
        )
    return out


def center(b: Tuple[int, int, int, int]) -> Tuple[int, int]:
    x1, y1, x2, y2 = b
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap_xy(dev: str, x: int, y: int) -> None:
    shell(dev, "input", "tap", str(x), str(y))


def find_respond_targets(t: str) -> List[Dict[str, Any]]:
    """Prefer small clickable nodes whose label is exactly Respond."""
    cands: List[Dict[str, Any]] = []
    for n in nodes(t):
        desc = n["desc"].strip()
        if not n["clickable"] or not n["enabled"]:
            continue
        lines = [ln.strip() for ln in desc.split("\n") if ln.strip()]
        if desc == "Respond" or lines == ["Respond"] or (
            lines and lines[-1] == "Respond" and len(lines) <= 2
        ):
            cands.append(n)
        elif desc.endswith("\nRespond\nRespond") or desc.endswith("Respond\nRespond"):
            cands.append({**n, "merged_card": True})
    # Smallest area = likely real button not whole card
    def area(n: Dict[str, Any]) -> int:
        x1, y1, x2, y2 = n["bounds"]
        return (x2 - x1) * (y2 - y1)

    cands.sort(key=area)
    return cands


def respond_tap_point(n: Dict[str, Any]) -> Tuple[int, int, str]:
    x1, y1, x2, y2 = n["bounds"]
    if n.get("merged_card") or (y2 - y1) > 400:
        # Bottom band where OraButton sits inside card
        cy = y2 - max(48, (y2 - y1) // 8)
        cx = (x1 + x2) // 2
        return cx, cy, "bottom_band_of_merged_card"
    return center(n["bounds"]) + ("node_center",)


def passenger_min_create() -> None:
    subprocess.call(["adb", "-s", P, "emu", "geo", "fix", "74.3587", "31.5204"])
    adb(P, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)
    t = dump(P, "p0")
    if "Waiting for offers" in t:
        return
    if "Where are you headed" not in t:
        return
    tap_xy(P, 640, 480)
    time.sleep(3)
    t = dump(P, "p1")
    for n in nodes(t):
        if "Use current location" in n["desc"]:
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(4)
    t = dump(P, "p2")
    for n in nodes(t):
        if n["desc"].startswith("Confirm pickup"):
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(2)
    t = dump(P, "p3")
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    )
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        tap_xy(P, (x1 + x2) // 2, (y1 + y2) // 2)
        time.sleep(1)
        for _ in range(40):
            shell(P, "input", "keyevent", "KEYCODE_DEL")
        shell(P, "input", "text", "Liberty%Market%Lahore")
        time.sleep(8)
    t = dump(P, "p4")
    for n in nodes(t):
        if "Liberty Market Gulberg" in n["desc"]:
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(4)
    for _ in range(6):
        t = dump(P, "p5")
        hit = False
        for n in nodes(t):
            if "Confirm destination" in n["desc"]:
                tap_xy(P, *center(n["bounds"]))
                hit = True
                break
        if hit:
            time.sleep(3)
            break
        shell(P, "input", "swipe", "640", "1200", "640", "700", "400")
        time.sleep(1)
    t = dump(P, "p6")
    for n in nodes(t):
        if n["desc"].startswith("Confirm pickup"):
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(2)
    tap_xy(P, 640, 1674)
    time.sleep(4)
    t = dump(P, "p7")
    for n in nodes(t):
        if n["desc"].startswith("Easy") or n["desc"].startswith("Trio"):
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(2)
    t = dump(P, "p8")
    for n in nodes(t):
        if "Retry pricing" in n["desc"]:
            tap_xy(P, *center(n["bounds"]))
            break
    time.sleep(22)
    for _ in range(4):
        t = dump(P, "p9")
        if "Waiting for offers" in t:
            return
        for n in nodes(t):
            if "Request " in n["desc"]:
                tap_xy(P, *center(n["bounds"]))
                time.sleep(5)
                break
        time.sleep(2)


def fetch_latest_ride() -> Optional[str]:
    env = {**dict(subprocess.os.environ), "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/e2e_fetch_latest_ride.ts"],
        cwd=BACKEND,
        env=env,
    )
    rides = json.loads(out.decode()).get("rides") or []
    return rides[0]["rideId"] if rides else None


def ride_snapshot(rid: str) -> Dict[str, Any]:
    env = {**dict(subprocess.os.environ), "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/e2e_ride_snapshot.ts", rid],
        cwd=BACKEND,
        env=env,
    )
    return json.loads(out.decode())


def driver_open_rides() -> str:
    adb(D, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(4)
    t = dump(D, "d0")
    if "Open ride requests" not in t and "Earn on ORA" in t:
        for n in nodes(t):
            if "Earn on ORA" in n["desc"]:
                tap_xy(D, *center(n["bounds"]))
                break
        time.sleep(4)
        t = dump(D, "d1")
    for n in nodes(t):
        if "Open ride requests" in n["desc"]:
            tap_xy(D, *center(n["bounds"]))
            break
    time.sleep(5)
    return dump(D, "d_open")


def main() -> None:
    OUT["previousRideExpired"] = True
    passenger_min_create()
    rid = fetch_latest_ride()
    OUT["rideId"] = rid
    if not rid:
        print(json.dumps(OUT, indent=2))
        sys.exit(1)
    snap = ride_snapshot(rid)
    OUT["pricing"] = {
        "recommendedFareMinor": snap["ride"].get("recommendedFareMinor"),
        "passengerOfferMinor": snap["ride"].get("passengerOfferMinor"),
        "pricingSnapshotId": snap["ride"].get("pricingSnapshotId"),
    }

    shell(D, "logcat", "-c")
    t = driver_open_rides()
    OUT["driverDiscovered"] = "Liberty" in t or "Current location" in t
    open(f"{ART}/og_respond_pre.xml", "w").write(t)

    targets = find_respond_targets(t)
    OUT["respondCandidates"] = [
        {
            "class": c["class"],
            "enabled": c["enabled"],
            "bounds": c["bounds"],
            "descPreview": c["desc"][:120],
            "merged": c.get("merged_card", False),
        }
        for c in targets[:5]
    ]

    sheet_opened = False
    tap_meta: Optional[Dict[str, Any]] = None
    for idx, cand in enumerate(targets[:3]):
        cx, cy, strategy = respond_tap_point(cand)
        tap_meta = {"attempt": idx, "x": cx, "y": cy, "strategy": strategy, "bounds": cand["bounds"]}
        OUT["respondTap"] = tap_meta
        tap_xy(D, cx, cy)
        time.sleep(3)
        t2 = dump(D, f"after_respond_{idx}")
        if any(
            k in t2
            for k in (
                "Submit offer",
                "Accept passenger price",
                "Amount (minor units)",
                "Counteroffer",
            )
        ):
            sheet_opened = True
            open(f"{ART}/og_sheet.xml", "w").write(t2)
            break
        # screencap evidence
        png = subprocess.check_output(["adb", "-s", D, "exec-out", "screencap", "-p"])
        open(f"{ART}/og_after_respond_{idx}.png", "wb").write(png)

    OUT["respondOpenedSheet"] = sheet_opened
    if not sheet_opened:
        log = shell(D, "logcat", "-d", "-t", "120")
        open(f"{ART}/og_logcat_respond.txt", "w").write(log)
        OUT["activity"] = shell(D, "dumpsys", "activity", "activities").splitlines()[-5:]
        print(json.dumps(OUT, indent=2))
        sys.exit(2)

    t2 = open(f"{ART}/og_sheet.xml", encoding="utf-8").read()
    for n in nodes(t2):
        if "Accept passenger price" in n["desc"]:
            tap_xy(D, *center(n["bounds"]))
            break
    time.sleep(2)
    t3 = dump(D, "submit")
    for n in nodes(t3):
        if n["desc"].startswith("Submit offer"):
            tap_xy(D, *center(n["bounds"]))
            break
    time.sleep(8)
    snap2 = ride_snapshot(rid)
    offers = snap2.get("offers") or []
    OUT["offerCount"] = len(offers)
    if offers:
        OUT["offerId"] = offers[0].get("offerId")
        OUT["driverId"] = offers[0].get("driverId")
        OUT["amount"] = offers[0].get("amountMinor")

    # Passenger verify
    adb(P, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(4)
    tp = dump(P, "pass_offers")
    OUT["passengerSelectVisible"] = "Select" in tp
    OUT["passengerSameRide"] = rid[:8] in tp if rid else False

    print(json.dumps(OUT, indent=2))


if __name__ == "__main__":
    main()
