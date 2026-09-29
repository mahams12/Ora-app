#!/usr/bin/env python3
"""Driver offer gate only — ops script."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

P = "emulator-5554"
D = "RF8R40ZQ1JH"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
R: dict = {"started": datetime.now(timezone.utc).isoformat()}


def env():
    return {
        **dict(subprocess.os.environ),
        "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json",
    }


def sh(dev: str, *args: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", dev, "shell", *args], stderr=subprocess.STDOUT
    ).decode("utf-8", errors="replace")


def pull(dev: str, path: str) -> str:
    for _ in range(10):
        try:
            sh(dev, "uiautomator", "dump", "/sdcard/og_u.xml")
            subprocess.check_call(
                ["adb", "-s", dev, "pull", "/sdcard/og_u.xml", path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            text = open(path, encoding="utf-8").read()
            if "hierarchy" in text and len(text) > 400:
                return text
        except subprocess.CalledProcessError:
            pass
        time.sleep(1.5)
    raise RuntimeError(f"UI dump failed: {dev}")


def parse_nodes(t: str) -> list[dict]:
    nodes: list[dict] = []
    for m in re.finditer(r"<node ([^/]+)/>", t):
        attrs = m.group(1)

        def attr(name: str) -> str:
            mm = re.search(rf'{name}="([^"]*)"', attrs)
            return mm.group(1) if mm else ""

        b = attr("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        nodes.append(
            {
                "desc": attr("content-desc").replace("&#10;", "\n"),
                "class": attr("class"),
                "clickable": attr("clickable") == "true",
                "enabled": attr("enabled") == "true",
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return nodes


def tap(dev: str, x: int, y: int) -> None:
    sh(dev, "input", "tap", str(x), str(y))


def tap_node(dev: str, n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    tap(dev, (x1 + x2) // 2, (y1 + y2) // 2)


def tsx(script: str, *args: str) -> dict:
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env(),
    )
    return json.loads(out.decode())


def create_passenger_ride() -> str:
    subprocess.call(["adb", "-s", P, "emu", "geo", "fix", "74.3587", "31.5204"])
    subprocess.call(["adb", "-s", P, "shell", "am", "force-stop", "com.ora.ora"])
    subprocess.call(
        ["adb", "-s", P, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(8)
    t = pull(P, f"{ART}/og_pass_0.xml")
    if "Phone number" in t or "Send verification code" in t:
        tap(P, 640, 1200)
        sh(P, "input", "text", "923012345678")
        sh(P, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        for n in parse_nodes(pull(P, f"{ART}/og_pass_auth.xml")):
            if "Send code" in n["desc"] or "Send verification code" in n["desc"]:
                tap_node(P, n)
                break
        time.sleep(8)
        tap(P, 640, 500)
        sh(P, "input", "text", "123456")
        time.sleep(1)
        for n in parse_nodes(pull(P, f"{ART}/og_pass_verify.xml")):
            if n["desc"].startswith("Verify"):
                tap_node(P, n)
                break
        time.sleep(12)

    t = pull(P, f"{ART}/og_pass_home.xml")
    if "Waiting for offers" in t or ("Ride request" in t and "SEARCHING" in t):
        for n in parse_nodes(t):
            if "Back to Home" in n["desc"]:
                tap_node(P, n)
                break
        time.sleep(3)
        t = pull(P, f"{ART}/og_pass_home2.xml")

    for n in parse_nodes(pull(P, f"{ART}/og_pass_trip.xml")):
        if "Where are you headed" in n["desc"]:
            tap_node(P, n)
            break
    time.sleep(3)

    for n in parse_nodes(pull(P, f"{ART}/og_pass_pick.xml")):
        if "Use current location" in n["desc"]:
            tap_node(P, n)
            break
    time.sleep(4)
    for n in parse_nodes(pull(P, f"{ART}/og_pass_pick2.xml")):
        if n["desc"].startswith("Confirm pickup"):
            tap_node(P, n)
            break
    time.sleep(2)

    t = pull(P, f"{ART}/og_pass_dest.xml")
    eds = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    )
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        tap(P, (x1 + x2) // 2, (y1 + y2) // 2)
        time.sleep(1)
        for _ in range(40):
            sh(P, "input", "keyevent", "KEYCODE_DEL")
        sh(P, "input", "text", "Liberty%Market%Lahore")
    time.sleep(8)
    for n in parse_nodes(pull(P, f"{ART}/og_pass_sug.xml")):
        if "Liberty Market Gulberg" in n["desc"]:
            tap_node(P, n)
            break
    time.sleep(4)
    for _ in range(7):
        t = pull(P, f"{ART}/og_pass_conf.xml")
        hit = False
        for n in parse_nodes(t):
            if "Confirm destination" in n["desc"]:
                tap_node(P, n)
                hit = True
                break
        if hit:
            time.sleep(3)
            break
        sh(P, "input", "swipe", "640", "1200", "640", "700", "400")
        time.sleep(1)
    for n in parse_nodes(pull(P, f"{ART}/og_pass_pick3.xml")):
        if n["desc"].startswith("Confirm pickup"):
            tap_node(P, n)
            break
    time.sleep(2)
    for n in parse_nodes(pull(P, f"{ART}/og_pass_cont.xml")):
        if n["desc"].startswith("Continue") and n["enabled"]:
            tap_node(P, n)
            break
    time.sleep(5)

    for n in parse_nodes(pull(P, f"{ART}/og_pass_rev.xml")):
        if n["desc"].startswith("Easy,"):
            tap_node(P, n)
            break
    time.sleep(2)
    for _ in range(8):
        t = pull(P, f"{ART}/og_pass_retry.xml")
        for n in parse_nodes(t):
            if "Retry pricing" in n["desc"]:
                tap_node(P, n)
                break
        else:
            sh(P, "input", "swipe", "640", "2300", "640", "900", "450")
            time.sleep(1)
            continue
        break
    time.sleep(26)
    t = pull(P, f"{ART}/og_pass_price.xml")
    if "Waiting for offers" in t:
        return tsx("e2e_fetch_latest_ride.ts")["rides"][0]["rideId"]
    if "Rs " not in t and "Request Easy" not in t and "Request Trio" not in t:
        raise RuntimeError("pricing not loaded on passenger review")
    for n in parse_nodes(t):
        if n["desc"].startswith("Request Easy"):
            tap_node(P, n)
            break
    time.sleep(10)
    if "Waiting for offers" not in pull(P, f"{ART}/og_pass_wait.xml"):
        raise RuntimeError("passenger not on waiting for offers")
    return tsx("e2e_fetch_latest_ride.ts")["rides"][0]["rideId"]


def driver_open_rides_screen() -> str:
    subprocess.call(["adb", "-s", D, "shell", "input", "keyevent", "KEYCODE_WAKEUP"])
    subprocess.call(["adb", "-s", D, "shell", "am", "force-stop", "com.ora.ora"])
    subprocess.call(
        ["adb", "-s", D, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(6)
    for _ in range(8):
        t = pull(D, f"{ART}/og_drv_nav.xml")
        if "Open rides" in t and ("Liberty" in t or "Current location" in t):
            return t
        if "Earn on ORA" in t:
            for n in parse_nodes(t):
                if "Earn on ORA" in n["desc"]:
                    tap_node(D, n)
                    break
            time.sleep(4)
            continue
        if "Open ride requests" in t:
            for n in parse_nodes(t):
                if n["desc"].startswith("Open ride requests"):
                    tap_node(D, n)
                    break
            time.sleep(5)
            continue
        sh(D, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(2)
    return pull(D, f"{ART}/og_drv_open.xml")


def try_open_offer_sheet(t: str) -> tuple[bool, dict]:
    cards = [
        n
        for n in parse_nodes(t)
        if n["clickable"] and n["enabled"] and "Respond" in n["desc"]
    ]
    if not cards:
        return False, {"error": "no_respond_node"}
    card = min(cards, key=lambda n: (n["bounds"][2] - n["bounds"][0]) * (n["bounds"][3] - n["bounds"][1]))
    x1, y1, x2, y2 = card["bounds"]
    attempts = [
        ("bottom_band", (x1 + x2) // 2, y2 - 45),
        ("center", (x1 + x2) // 2, (y1 + y2) // 2),
        ("lower_third", (x1 + x2) // 2, y1 + (y2 - y1) * 2 // 3),
    ]
    meta = {"card_bounds": card["bounds"], "attempts": []}
    sh(D, "logcat", "-c")
    for name, cx, cy in attempts:
        tap(D, cx, cy)
        time.sleep(3.5)
        t2 = pull(D, f"{ART}/og_sheet_{name}.xml")
        opened = any(
            s in t2
            for s in ("Submit offer", "Accept passenger price", "Amount (minor units)")
        )
        meta["attempts"].append({"name": name, "tap": [cx, cy], "opened": opened})
        if opened:
            meta["winning"] = name
            open(f"{ART}/og_offer_sheet.xml", "w").write(t2)
            return True, meta
    meta["logcat"] = sh(D, "logcat", "-d", "-t", "200")
    png = subprocess.check_output(["adb", "-s", D, "exec-out", "screencap", "-p"])
    open(f"{ART}/og_respond_fail.png", "wb").write(png)
    return False, meta


def submit_offer() -> None:
    t = open(f"{ART}/og_offer_sheet.xml", encoding="utf-8").read()
    for n in parse_nodes(t):
        if "Accept passenger price" in n["desc"]:
            tap_node(D, n)
            break
    time.sleep(2)
    for n in parse_nodes(pull(D, f"{ART}/og_submit.xml")):
        if n["desc"].startswith("Submit offer"):
            tap_node(D, n)
            break
    time.sleep(8)


def main() -> None:
    before = tsx("e2e_fetch_latest_ride.ts")["rides"][0]["createdAt"]
    rid = create_passenger_ride()
    ride = tsx("e2e_fetch_latest_ride.ts")["rides"][0]
    R["rideId"] = rid
    R["rideCreatedAt"] = ride["createdAt"]
    R["freshRide"] = ride["createdAt"] > before
    R["pricingSnapshotId"] = ride.get("pricingSnapshotId") if isinstance(ride, dict) else None

    snap = tsx("e2e_ride_snapshot.ts", rid)
    R["passengerOfferMinor"] = snap["ride"].get("passengerOfferMinor")
    R["recommendedFareMinor"] = snap["ride"].get("recommendedFareMinor")

    t = driver_open_rides_screen()
    R["driverDiscovered"] = "Liberty" in t or "Current location" in t
    open(f"{ART}/og_driver_open_final.xml", "w").write(t)
    if not R["driverDiscovered"]:
        R["verdict"] = "BLOCKED"
        print(json.dumps(R, indent=2))
        sys.exit(2)

    opened, meta = try_open_offer_sheet(t)
    R["respondMeta"] = meta
    R["respondOpenedSheet"] = opened
    if not opened:
        R["verdict"] = "RED"
        R["rootCause"] = "AUTOMATION+UI"
        print(json.dumps(R, indent=2))
        sys.exit(3)

    submit_offer()
    snap2 = tsx("e2e_ride_snapshot.ts", rid)
    offers = snap2.get("offers") or []
    R["offerCount"] = len(offers)
    if offers:
        R["offerId"] = offers[0].get("offerId")
        R["driverId"] = offers[0].get("driverId")
        R["amountMinor"] = offers[0].get("amountMinor")
        R["requestVersion"] = snap2["ride"].get("requestVersion")

    subprocess.call(
        ["adb", "-s", P, "shell", "am", "start", "-n", "com.ora.ora/.MainActivity"]
    )
    time.sleep(4)
    tp = pull(P, f"{ART}/og_passenger_offers.xml")
    R["passengerSelectVisible"] = "Select" in tp

    R["verdict"] = "GREEN" if R["offerCount"] == 1 and R["passengerSelectVisible"] else (
        "RED" if R["offerCount"] == 0 else "YELLOW"
    )
    print(json.dumps(R, indent=2))


if __name__ == "__main__":
    main()
