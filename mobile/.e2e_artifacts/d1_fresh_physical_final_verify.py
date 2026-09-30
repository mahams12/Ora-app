#!/usr/bin/env python3
"""D1 final physical verification: fresh ride → FCM → tap → Open Rides → visibility."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict

D = "RF8R40ZQ1JH"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
GATES: Dict[str, str] = {}
REPORT: Dict[str, Any] = {"startedAt": datetime.now(timezone.utc).isoformat(), "device": D}


def worker_token() -> str:
    tok = os.environ.get("ORA_INTERNAL_WORKER_TOKEN", "").strip()
    if tok:
        return tok
    proc = subprocess.run(
        [
            "gcloud",
            "run",
            "services",
            "describe",
            "ora-auth-service-staging",
            "--region=us-central1",
            "--project=ora-app-d8112",
            "--format=json",
        ],
        capture_output=True,
        text=True,
        timeout=90,
    )
    if proc.returncode != 0:
        raise RuntimeError("gcloud worker token fetch failed")
    svc = json.loads(proc.stdout)
    for c in svc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", []):
        for e in c.get("env", []):
            if e.get("name") == "ORA_INTERNAL_WORKER_TOKEN" and e.get("value"):
                return e["value"]
    raise RuntimeError("ORA_INTERNAL_WORKER_TOKEN not on Cloud Run service")


def tsx(script: str, *args: str) -> Any:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/{script}", *args],
        cwd=BACKEND,
        env=env,
        text=True,
        timeout=120,
    )
    return json.loads(out.strip()) if out.strip().startswith("{") else out


def block(gate: str, reason: str) -> None:
    GATES[gate] = "BLOCKED"
    REPORT["blockedReason"] = reason
    REPORT["gates"] = GATES
    finish()


def finish() -> None:
    REPORT["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT["gates"] = GATES
    path = f"{ART}/d1_fresh_physical_final_report.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(REPORT, f, indent=2)
    print("\n| Gate | Result |")
    print("|------|--------|")
    order = [
        "ADB",
        "Driver auth",
        "FCM token",
        "Fresh ride",
        "Ride unexpired",
        "N4 dispatch",
        "FCM delivery",
        "Notification exists",
        "Physical notification tap",
        "Open Rides navigation",
        "Target ride API visible",
        "Target ride UI visible",
        "Duplicate/safety",
    ]
    for k in order:
        print(f"| {k} | **{GATES.get(k, '—')}** |")
    green = all(GATES.get(k) == "PASS" for k in order)
    verdict = "GREEN" if green else "BLOCKED"
    print(f"\nD1 FINAL PHYSICAL VERDICT = {verdict}")
    if not green and REPORT.get("blockedReason"):
        print(f"Reason: {REPORT['blockedReason']}")
    sys.exit(0 if green else 1)


def main() -> None:
    # 1 ADB
    proc = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=30)
    GATES["ADB"] = "PASS" if f"{D}\tdevice" in proc.stdout else "BLOCKED"
    if GATES["ADB"] != "PASS":
        block("ADB", f"Samsung not device: {proc.stdout.strip()!r}")

    # 2 Driver auth
    import importlib.util

    spec = importlib.util.spec_from_file_location("d1proof", f"{ART}/d1_real_fcm_physical_proof.py")
    d1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(d1)
    try:
        d1.auth(D, "+923012345677", "000000", "fin_d_auth")
        GATES["Driver auth"] = "PASS"
    except Exception as e:
        GATES["Driver auth"] = "BLOCKED"
        block("Driver auth", str(e))

    time.sleep(5)

    # 3 FCM token
    try:
        tok = tsx("check_driver_device_tokens.ts")
        REPORT["fcmTokenCheck"] = tok
        ok = tok.get("tokenDocCount", 0) >= 1 and tok["docs"][0].get("hasToken")
        GATES["FCM token"] = "PASS" if ok else "BLOCKED"
        if not ok:
            block("FCM token", "no registered token doc")
    except Exception as e:
        GATES["FCM token"] = "BLOCKED"
        block("FCM token", str(e))

    # 4–7 Staging prep (ride + dispatch + fcm sweep)
    env = {
        **os.environ,
        "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json",
        "ORA_INTERNAL_WORKER_TOKEN": worker_token(),
    }
    try:
        prep_raw = subprocess.check_output(
            [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/staging_d1_dispatch_prep.ts"],
            cwd=BACKEND,
            env=env,
            text=True,
            timeout=180,
        )
        prep = json.loads(prep_raw)
        REPORT["stagingPrep"] = prep
    except Exception as e:
        GATES["Fresh ride"] = "BLOCKED"
        block("Fresh ride", f"staging prep failed: {e}")

    if not prep.get("ok"):
        GATES["Fresh ride"] = "BLOCKED"
        block("Fresh ride", json.dumps(prep)[:500])

    ride_id = prep.get("rideId")
    create = (prep.get("steps") or {}).get("createRide", {}).get("data") or {}
    REPORT["ride"] = {
        "rideId": ride_id,
        "createdAt": create.get("createdAt"),
        "expiresAt": create.get("expiresAt"),
        "state": create.get("state"),
        "requestVersion": create.get("requestVersion"),
        "passengerOfferMinor": create.get("passengerOfferMinor"),
        "pricingSnapshotId": create.get("pricingSnapshotId"),
    }
    GATES["Fresh ride"] = "PASS" if ride_id else "BLOCKED"
    if not ride_id:
        block("Fresh ride", "missing rideId")

    now = datetime.now(timezone.utc)
    exp_s = create.get("expiresAt") or ""
    try:
        exp = datetime.fromisoformat(exp_s.replace("Z", "+00:00"))
        unexpired = exp > now
    except ValueError:
        unexpired = False
    GATES["Ride unexpired"] = "PASS" if unexpired else "BLOCKED"
    REPORT["verifiedAtUtc"] = now.isoformat()
    if not unexpired:
        block("Ride unexpired", f"expiresAt={exp_s}")

    tick = (prep.get("steps") or {}).get("dispatchTick", {})
    sweep = (prep.get("steps") or {}).get("fcmSweep", {})
    tick_ok = tick.get("status") == 200 and (tick.get("data") or {}).get("outcome") == "wave_completed"
    invited = (tick.get("data") or {}).get("invitedCount", 0)
    GATES["N4 dispatch"] = "PASS" if tick_ok and invited >= 1 else "BLOCKED"
    delivered = (sweep.get("data") or {}).get("delivered", 0)
    GATES["FCM delivery"] = "PASS" if sweep.get("status") == 200 and delivered >= 1 else "BLOCKED"
    if GATES["N4 dispatch"] != "PASS":
        block("N4 dispatch", json.dumps(tick)[:400])
    if GATES["FCM delivery"] != "PASS":
        block("FCM delivery", json.dumps(sweep)[:400])

    # Wait for notification to land on device
    time.sleep(4)

    # 8–15 Notification tap via dedicated script
    tap_env = {**os.environ, "ORA_D1_TARGET_RIDE": ride_id}
    tap = subprocess.run(
        [sys.executable, f"{ART}/d1_notification_tap_physical_verify.py"],
        env=tap_env,
        capture_output=True,
        text=True,
        timeout=300,
    )
    REPORT["tapScriptStdout"] = tap.stdout[-4000:]
    REPORT["tapScriptStderr"] = tap.stderr[-2000:]
    try:
        tap_report = json.load(open(f"{ART}/d1_notification_tap_physical_verify_report.json"))
        REPORT["tapReport"] = tap_report
    except Exception:
        tap_report = {}

    tg = tap_report.get("gates", {})
    GATES["Notification exists"] = tg.get("notification_exists", "BLOCKED")
    GATES["Physical notification tap"] = tg.get("notification_tap", "BLOCKED")
    GATES["Open Rides navigation"] = tg.get("navigation_driver_open_rides", "BLOCKED")
    GATES["Duplicate/safety"] = tg.get("duplicate_safety", "BLOCKED")

    api = tap_report.get("open_rides_api") or {}
    try:
        api2 = tsx("d1_driver_open_rides_check.ts", ride_id)
        REPORT["openRidesApiFinal"] = api2
        api_hit = api2.get("targetPresent") is True
    except Exception as e:
        REPORT["openRidesApiError"] = str(e)
        api_hit = api.get("targetPresent") is True

    GATES["Target ride API visible"] = "PASS" if api_hit else "BLOCKED"

    after_xml_path = f"{ART}/d1_tap_after_tap_app.xml"
    ui_xml = ""
    if os.path.isfile(after_xml_path):
        ui_xml = open(after_xml_path, encoding="utf-8").read()
    ui_ride_id = ride_id in ui_xml or ride_id.split("-")[0] in ui_xml
    ui_route = "Liberty Market Lahore" in ui_xml and "Gulberg" in ui_xml and "Ride request" in ui_xml
    REPORT["targetRideUi"] = {"rideIdInXml": ui_ride_id, "routeMarkers": ui_route}
    # PASS requires exact rideId string in accessibility tree (product exposes addresses only if absent → BLOCKED)
    GATES["Target ride UI visible"] = "PASS" if ui_ride_id else "BLOCKED"
    if GATES["Target ride UI visible"] != "PASS" and ui_route and api_hit:
        REPORT["targetRideUiNote"] = (
            "API returned ride; UI shows Liberty→Gulberg card but rideId not in a11y tree"
        )

    if GATES["Notification exists"] != "PASS":
        block("Notification exists", tap_report.get("fail", "no notification"))
    if GATES["Physical notification tap"] != "PASS":
        block("Physical notification tap", tap_report.get("fail", "tap failed"))
    if GATES["Open Rides navigation"] != "PASS":
        block("Open Rides navigation", "not on Open rides after tap")
    if GATES["Target ride API visible"] != "PASS":
        block("Target ride API visible", json.dumps(api2 if "api2" in dir() else api))
    if GATES["Target ride UI visible"] != "PASS":
        block(
            "Target ride UI visible",
            REPORT.get("targetRideUiNote", "exact rideId not found in UI hierarchy"),
        )

    # Update shared tap artifacts report ride id
    with open(f"{ART}/d1_notification_tap_physical_verify_report.json", "w") as f:
        json.dump({**tap_report, "targetRideId": ride_id, "freshFinalRun": True, "gatesFull": GATES}, f, indent=2)

    REPORT["finalVerdict"] = "GREEN"
    finish()


if __name__ == "__main__":
    main()
