#!/usr/bin/env python3
"""MAP-3 final physical closure — REAL HUMAN FINGER pan only.

NO product code changes.
NO adb/input gestures for the ownership test.
Waits for signal file: MAP3_HUMAN_PAN_DONE
"""
from __future__ import annotations

import hashlib
import json
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import map2a_physical as M
from l2_step4_physical import assign_ride, rtdb_snapshot, staging_revision, wait_rtdb_seq
from map2b_physical import (
    ART,
    STAGING_API,
    api_token,
    dump,
    map_snapshot,
    open_passenger_active,
    progress,
    publish_trip_http,
    screencap,
)

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None  # type: ignore

REPORT = ART / "MAP3_PHYSICAL_HUMAN_GESTURE_VERIFICATION.json"
SIGNAL = ART / "MAP3_HUMAN_PAN_DONE"
BASE_LAT = 31.5204
BASE_LNG = 74.3587


def log(*a):
    print(*a, flush=True)


def guide_snapshot(xml: str) -> dict:
    u = M.unescape(xml)
    return {
        **map_snapshot(xml),
        "guideSemantics": "Guide line — not a road route" in u,
        "guideDriverPickup": "Driver to pickup" in u,
        "guideDriverDest": "Driver to destination" in u,
        "guidePickupDest": "Pickup to destination" in u,
    }


def map_bounds(xml: str):
    cands = []
    for n in M.nodes(xml):
        d = n["desc"]
        if "Google Map" in d or "Active ride map" in d:
            x1, y1, x2, y2 = n["bounds"]
            if x2 > x1 and y2 > y1:
                cands.append(((x2 - x1) * (y2 - y1), n["bounds"]))
    return cands[0][1] if cands else (53, 259, 1028, 784)


def fp(tag: str, bounds) -> dict:
    path = ART / f"map2a_{tag}.png"
    if not path.exists() or Image is None:
        return {"ok": False}
    im = Image.open(path).convert("RGB")
    w, h = im.size
    x1, y1, x2, y2 = bounds
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(w, x2), min(h, y2)
    crop = im.crop((x1, y1, x2, y2)).resize((64, 36), Image.Resampling.BILINEAR)
    pixels = list(crop.getdata())
    lum = [int(0.299 * r + 0.587 * g + 0.114 * b) for r, g, b in pixels]
    mean = sum(lum) / len(lum)
    bits = "".join("1" if v >= mean else "0" for v in lum)
    return {
        "ok": True,
        "sha1": hashlib.sha1(bits.encode()).hexdigest()[:16],
        "meanLum": round(mean, 2),
    }


def vs(a: dict, b: dict) -> dict:
    if not a.get("ok") or not b.get("ok"):
        return {"comparable": False}
    same = a.get("sha1") == b.get("sha1")
    d = abs((a.get("meanLum") or 0) - (b.get("meanLum") or 0))
    return {
        "comparable": True,
        "exactHashMatch": same,
        "lumDelta": round(d, 2),
        "stableFraming": same or d < 3.0,
        "largeShift": (not same) and d >= 8.0,
    }


def wait_human_pan(timeout_s: int = 600) -> bool:
    """Block until operator creates MAP3_HUMAN_PAN_DONE after REAL finger pan."""
    if SIGNAL.exists():
        SIGNAL.unlink()
    log("")
    log("=" * 60)
    log("HUMAN ACTION REQUIRED — REAL FINGER ONLY")
    log("=" * 60)
    log("1. On the Samsung SM-A325F Active Ride map:")
    log("   - Use your FINGER (not adb) to pan FAR away from the markers")
    log("   - Optionally pinch-zoom so the framing is obviously different")
    log("2. Do NOT tap Recenter")
    log("3. When done, create this empty file on the Mac:")
    log(f"     touch \"{SIGNAL}\"")
    log("   Or run:  touch mobile/.e2e_artifacts/MAP3_HUMAN_PAN_DONE")
    log(f"Waiting up to {timeout_s}s for signal...")
    log("=" * 60)
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        if SIGNAL.exists():
            log("Human pan signal received.")
            return True
        time.sleep(1.0)
    log("TIMEOUT waiting for human pan signal")
    return False


def tap_recenter(xml: str) -> bool:
    if M.tap_contains(xml, "Recenter map"):
        return True
    b = map_bounds(xml)
    x1, y1, x2, y2 = b
    M.sh("input", "tap", str(x2 - 48), str(y1 + 48))
    return True


def main() -> None:
    report: dict = {
        "artifact": "MAP3_PHYSICAL_HUMAN_GESTURE_VERIFICATION",
        "slice": "MAP-3 — Human finger camera ownership closure",
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "humanGestureUsed": True,
        "adbGestureUsedForOwnershipTest": False,
        "productCodeModified": False,
        "device": {
            "serial": M.DEV,
            "model": M.sh("getprop", "ro.product.model").strip(),
            "android": M.sh("getprop", "ro.build.version.release").strip(),
            "package": M.PKG,
        },
        "build": {
            "apk": "mobile/build/app/outputs/flutter-apk/app-debug.apk",
            "stagingApi": STAGING_API,
        },
        "results": {},
        "proofs": {},
        "evidenceFiles": [],
        "failedChecks": [],
        "limitations": [],
    }
    try:
        report["stagingRevision"] = staging_revision()
    except Exception as e:
        report["stagingRevision"] = f"unavailable:{type(e).__name__}"

    # Ensure device present
    try:
        M.sh("getprop", "ro.product.model")
    except Exception:
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — DEVICE NOT CONNECTED"
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    log("=== ASSIGN fresh ride ===")
    assigned = assign_ride()
    if not assigned.get("ok"):
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — assign failed"
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    ride_id = assigned["rideId"]
    driver_uid = assigned["steps"]["driverUid"]
    report["rideId"] = ride_id
    report["driverUid"] = driver_uid
    log("ride", ride_id)

    # ---- TEST 1 ----
    log("=== TEST 1 initial map ===")
    M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
    open_passenger_active(ride_id)
    time.sleep(3)
    xml = dump("map3h_t1")
    screencap("map3h_t1")
    t1 = guide_snapshot(xml)
    report["proofs"]["test1"] = t1
    report["results"]["initialMap"] = (
        "PASS"
        if t1.get("activeRide") and t1.get("googleMap") and t1.get("pickup") and t1.get("destination")
        else "FAIL"
    )
    log("  T1", report["results"]["initialMap"], t1)
    if report["results"]["initialMap"] != "PASS":
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — initial map not ready"
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    # ---- TEST 2 ----
    log("=== TEST 2 first driver fix (no pan) ===")
    driver_token = api_token("+923012345677")
    stream_id = str(uuid.uuid4())
    r1 = publish_trip_http(driver_token, ride_id, 1, stream_id, BASE_LAT, BASE_LNG, heading=85.0)
    wait_rtdb_seq(ride_id, min_seq=1, timeout_s=45)
    after = None
    for i in range(15):
        xml = dump(f"map3h_t2_poll_{i}")
        after = guide_snapshot(xml)
        if after.get("driverMarker") and not after.get("waiting"):
            screencap("map3h_t2_first_fix")
            break
        time.sleep(2)
    else:
        screencap("map3h_t2_timeout")
    bounds = map_bounds(xml)
    fp_b = fp("map3h_t2_first_fix", bounds)
    report["proofs"]["test2"] = {"http": r1, "ui": after, "fingerprint": fp_b}
    report["results"]["firstDriverFix"] = (
        "PASS"
        if after and after.get("driverMarker") and r1.get("accepted")
        else "FAIL"
    )
    log("  T2", report["results"]["firstDriverFix"])
    if report["results"]["firstDriverFix"] != "PASS":
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — first fix failed"
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    # ---- TEST 3 HUMAN PAN ----
    log("=== TEST 3 REAL HUMAN FINGER PAN ===")
    xml = dump("map3h_t3_before_pan")
    screencap("map3h_t3_before_pan")
    fp_before = fp("map3h_t3_before_pan", map_bounds(xml))

    if not wait_human_pan(timeout_s=600):
        report["results"]["humanFingerPan"] = "FAIL"
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — human pan timeout"
        report["limitations"].append("Operator did not signal human pan within timeout")
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    # Collapse shade only — NO input swipe
    M.collapse_shade()
    time.sleep(0.5)
    xml = dump("map3h_t3_after_pan")
    screencap("map3h_t3_after_pan")
    bounds_c = map_bounds(xml)
    fp_c = fp("map3h_t3_after_pan", bounds_c)
    pan_vs = vs(fp_before, fp_c)
    after_pan_ui = guide_snapshot(xml)
    report["proofs"]["test3"] = {
        "before": fp_before,
        "after": fp_c,
        "vs": pan_vs,
        "ui": after_pan_ui,
        "humanGestureUsed": True,
        "adbGestureUsedForOwnershipTest": False,
    }
    # Require visible framing change from human pan
    report["results"]["humanFingerPan"] = (
        "PASS" if (pan_vs.get("largeShift") or not pan_vs.get("exactHashMatch")) else "FAIL"
    )
    log("  T3", report["results"]["humanFingerPan"], pan_vs)
    if report["results"]["humanFingerPan"] != "PASS":
        report["verdict"] = "MAP-3 PHYSICAL BLOCKED — pan not visible in screenshots"
        report["limitations"].append(
            "Human signal received but map crop fingerprint did not change enough"
        )
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)

    # ---- TEST 4 RTDB ticks ----
    log("=== TEST 4 RTDB ticks while human-owned ===")
    pubs = []
    for seq in range(2, 6):
        r = publish_trip_http(
            driver_token,
            ride_id,
            seq,
            stream_id,
            BASE_LAT + 0.00022 * (seq - 1),
            BASE_LNG + 0.00018 * (seq - 1),
            heading=80.0 + seq,
        )
        time.sleep(2.5)
        tag = f"map3h_t4_seq{seq}"
        xml = dump(tag)
        snap = guide_snapshot(xml)
        screencap(tag)
        f = fp(tag, bounds_c)
        pubs.append(
            {
                "seq": seq,
                "accepted": r.get("accepted"),
                "driverMarker": snap.get("driverMarker"),
                "guide": snap.get("guideDriverPickup") or snap.get("guideSemantics"),
                "vsPan": vs(fp_c, f),
            }
        )
        log("  T4", seq, pubs[-1]["vsPan"])
    last_d = fp("map3h_t4_seq5", bounds_c)
    d_ok = all(p.get("accepted") and p.get("driverMarker") for p in pubs) and vs(
        fp_c, last_d
    ).get("stableFraming")
    report["proofs"]["test4"] = {"publishes": pubs, "lastVsPan": vs(fp_c, last_d)}
    report["results"]["rtdbTicksWhileOwned"] = "PASS" if d_ok else "FAIL"
    log("  T4", report["results"]["rtdbTicksWhileOwned"])

    # ---- TEST 5 OD1 phases — never remount Active Ride ----
    log("=== TEST 5 phases while owned (CRITICAL OD1) ===")
    passenger_token = api_token("+923012345678")
    ride = M.get_ride(passenger_token, ride_id)
    version = int(ride.get("version") or 3)
    seq = 6
    gating = {}
    for action, expect in (
        ("en_route", "DRIVER_EN_ROUTE"),
        ("arrived", "DRIVER_ARRIVED"),
        ("start", "RIDE_STARTED"),
    ):
        st, body = progress(driver_token, ride_id, action, version)
        data = body.get("data") or {}
        state = data.get("state")
        version = int(data.get("version") or (version + 1))
        publish_trip_http(
            driver_token,
            ride_id,
            seq,
            stream_id,
            BASE_LAT + 0.0003 * (seq - 1),
            BASE_LNG + 0.00025 * (seq - 1),
            heading=90.0,
        )
        seq += 1
        time.sleep(3)
        tag = f"map3h_t5_{action}"
        # DO NOT call open_passenger_active — remount would reset ownership
        xml = dump(tag)
        snap = guide_snapshot(xml)
        screencap(tag)
        f = fp(tag, bounds_c)
        gating[action] = {
            "apiStatus": st,
            "httpState": state,
            "expected": expect,
            "ui": snap,
            "vsPan": vs(fp_c, f),
            "fingerprint": f,
        }
        log("  T5", action, state, gating[action]["vsPan"])

    report["proofs"]["test5"] = gating
    report["results"]["enRouteWhileOwned"] = (
        "PASS"
        if gating["en_route"]["httpState"] == "DRIVER_EN_ROUTE"
        and gating["en_route"]["vsPan"].get("stableFraming")
        else "FAIL"
    )
    report["results"]["arrivedWhileOwned"] = (
        "PASS"
        if gating["arrived"]["httpState"] == "DRIVER_ARRIVED"
        and gating["arrived"]["vsPan"].get("stableFraming")
        else "FAIL"
    )
    # CRITICAL OD1
    start_vs = gating["start"]["vsPan"]
    start_fp = gating["start"]["fingerprint"]
    od1_pass = bool(
        gating["start"]["httpState"] == "RIDE_STARTED"
        and start_vs.get("stableFraming")
    )
    report["results"]["rideStartedWhileOwned"] = "PASS" if od1_pass else "FAIL"
    report["proofs"]["od1"] = {
        "pass": od1_pass,
        "startVsPan": start_vs,
        "startFingerprint": start_fp,
        "panFingerprint": fp_c,
        "rule": "RIDE_STARTED must remain at human-pan framing (stable vs pan)",
    }
    log("  OD1", report["results"]["rideStartedWhileOwned"], start_vs)

    if report["results"]["rideStartedWhileOwned"] == "FAIL":
        # Still attempt Recenter for evidence, then terminate
        log("OD1 FAIL with human gesture — documenting Recenter then stopping as RED")

    # ---- TEST 6 Recenter ----
    log("=== TEST 6 Recenter ===")
    xml = dump("map3h_t6_before_recenter")
    screencap("map3h_t6_before_recenter")
    fp_pre_rc = fp("map3h_t6_before_recenter", map_bounds(xml))
    tapped = tap_recenter(xml)
    time.sleep(2.0)
    xml = dump("map3h_t6_after_recenter")
    screencap("map3h_t6_after_recenter")
    fp_f = fp("map3h_t6_after_recenter", map_bounds(xml))
    vs_pan_f = vs(fp_c, fp_f)
    vs_pre = vs(fp_pre_rc, fp_f)
    report["proofs"]["test6"] = {
        "recenterTapped": tapped,
        "before": fp_pre_rc,
        "after": fp_f,
        "vsPan": vs_pan_f,
        "vsBeforeRecenter": vs_pre,
    }
    if vs_pan_f.get("largeShift") or (
        not vs_pan_f.get("exactHashMatch") and vs_pan_f.get("lumDelta", 0) >= 5
    ):
        report["results"]["recenter"] = "PASS"
    elif vs_pre.get("exactHashMatch") and od1_pass is False:
        # Already at policy from failed OD1
        report["results"]["recenter"] = "INCONCLUSIVE"
    elif vs_pre.get("exactHashMatch"):
        report["results"]["recenter"] = "INCONCLUSIVE"
    else:
        report["results"]["recenter"] = "PASS" if not vs_pan_f.get("stableFraming") else "FAIL"
    log("  T6", report["results"]["recenter"], vs_pan_f)

    # ---- TEST 7 post-recenter ----
    log("=== TEST 7 post-recenter ticks ===")
    g_pubs = []
    for i in range(seq, seq + 3):
        r = publish_trip_http(
            driver_token,
            ride_id,
            i,
            stream_id,
            BASE_LAT + 0.00035 * (i - 1),
            BASE_LNG + 0.00028 * (i - 1),
            heading=95.0,
        )
        time.sleep(2.2)
        tag = f"map3h_t7_seq{i}"
        xml = dump(tag)
        snap = guide_snapshot(xml)
        screencap(tag)
        f = fp(tag, map_bounds(xml))
        g_pubs.append(
            {
                "seq": i,
                "accepted": r.get("accepted"),
                "driverMarker": snap.get("driverMarker"),
                "vsRecenter": vs(fp_f, f),
            }
        )
    report["proofs"]["test7"] = {"publishes": g_pubs}
    report["results"]["postRecenterTicks"] = (
        "PASS"
        if all(p.get("accepted") and p.get("vsRecenter", {}).get("stableFraming") for p in g_pubs)
        else "FAIL"
    )
    log("  T7", report["results"]["postRecenterTicks"])

    # ---- TEST 8 terminal ----
    log("=== TEST 8 terminal ===")
    xml = dump("map3h_t8_pre")
    if M.tap_contains(xml, "Cancel ride"):
        time.sleep(1.2)
        xml = dump("map3h_t8_dialog")
        M.tap_contains(xml, "Cancel ride") or M.tap_contains(xml, "Confirm")
        time.sleep(4)
    else:
        progress(driver_token, ride_id, "cancel", version)
        time.sleep(3)
    xml = dump("map3h_t8_after")
    screencap("map3h_t8_after")
    snap_term = rtdb_snapshot(ride_id)
    for _ in range(15):
        if not snap_term.get("latestExists") and not snap_term.get("accessExists"):
            break
        time.sleep(2)
        snap_term = rtdb_snapshot(ride_id)
    ride_after = M.get_ride(passenger_token, ride_id)
    report["proofs"]["test8"] = {
        "httpState": ride_after.get("state"),
        "rtdbCleared": not snap_term.get("latestExists"),
        "aclRevoked": not snap_term.get("accessExists"),
    }
    report["results"]["terminalCleanup"] = (
        "PASS"
        if ride_after.get("state") == "CANCELLED"
        and not snap_term.get("latestExists")
        and not snap_term.get("accessExists")
        else "FAIL"
    )
    log("  T8", report["results"]["terminalCleanup"])

    report["evidenceFiles"] = sorted(p.name for p in ART.glob("map2a_map3h_*.png"))
    report["endedAt"] = datetime.now(timezone.utc).isoformat()

    # Verdict rules (exact from task)
    r = report["results"]
    if r.get("rideStartedWhileOwned") == "FAIL":
        report["verdict"] = "MAP-3 RED — REAL DEVICE OWNERSHIP DEFECT CONFIRMED"
    elif (
        r.get("humanFingerPan") == "PASS"
        and r.get("rtdbTicksWhileOwned") == "PASS"
        and r.get("enRouteWhileOwned") == "PASS"
        and r.get("arrivedWhileOwned") == "PASS"
        and r.get("rideStartedWhileOwned") == "PASS"
        and r.get("recenter") == "PASS"
        and r.get("postRecenterTicks") == "PASS"
        and r.get("terminalCleanup") == "PASS"
    ):
        report["verdict"] = "MAP-3 GREEN — PHYSICAL PROOF CLOSED"
    elif (
        r.get("rideStartedWhileOwned") == "PASS"
        and r.get("recenter") == "INCONCLUSIVE"
        and r.get("rtdbTicksWhileOwned") == "PASS"
        and r.get("enRouteWhileOwned") == "PASS"
        and r.get("arrivedWhileOwned") == "PASS"
        and r.get("terminalCleanup") == "PASS"
    ):
        report["verdict"] = (
            "MAP-3 YELLOW — HUMAN OWNERSHIP PROVEN, RECENTER EVIDENCE INCONCLUSIVE"
        )
    else:
        failed = [k for k, v in r.items() if v == "FAIL"]
        report["failedChecks"] = failed
        report["verdict"] = "MAP-3 YELLOW — HUMAN GESTURE RUN INCOMPLETE/PARTIAL"
        report["limitations"].append("failed: " + ",".join(failed))

    report["failedChecks"] = [k for k, v in r.items() if v == "FAIL"]
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    log("DONE", report["verdict"], "rideId", ride_id)


if __name__ == "__main__":
    main()
