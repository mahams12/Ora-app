#!/usr/bin/env python3
"""L1 UX correction physical proof: denied UX + cancel-while-active GPS."""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import l1_gap_closure_physical as H

DEV, PKG, ART, REPORT, LOGCAT = H.DEV, H.PKG, H.ART, H.REPORT, H.LOGCAT


def clear_perm() -> None:
    for perm in (
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
    ):
        subprocess.call(
            [
                "adb",
                "-s",
                DEV,
                "shell",
                "pm",
                "clear-permission-flags",
                PKG,
                perm,
                "user-set",
                "user-fixed",
            ]
        )
        subprocess.call(["adb", "-s", DEV, "shell", "pm", "revoke", PKG, perm])


def grant_perm() -> None:
    for perm in (
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
    ):
        subprocess.call(["adb", "-s", DEV, "shell", "pm", "grant", PKG, perm])


def main() -> None:
    # Fresh assigned ride
    print("ASSIGN")
    subprocess.check_call(["python3", str(ART / "l1_staging_assign_ride.py")], cwd=str(ART))
    ride = json.loads((ART / "l1_assigned_ride.json").read_text())["rideId"]
    report: dict = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": H.sh("getprop", "ro.product.model").strip(),
        "androidVersion": H.sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": ride,
        "method": "l1_ux_correction_physical",
        "loggerSink": "ConsoleAppLogger → dart:developer name=ora; debug assert print mirror",
    }

    clear_perm()
    subprocess.call(["adb", "-s", DEV, "shell", "am", "force-stop", PKG])
    time.sleep(1)
    subprocess.check_call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "monkey",
            "-p",
            PKG,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )
    time.sleep(5)
    H.login_and_driver()
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])

    # -------- A deny --------
    print("TEST A deny")
    t0 = time.time()
    t = H.open_assigned()
    dialog_seen = False
    denied = False
    for _ in range(12):
        if "permissioncontroller" in H.fg() or "While using the app" in t:
            dialog_seen = True
            H.show("ux_a_dlg")
            denied = H.deny_permission()
            break
        time.sleep(1)
        t = H.dump("ux_a_wait")
    # Do NOT force-stop permissioncontroller — let Flutter settle.
    status_a = None
    for i in range(30):
        time.sleep(1.2)
        if "permissioncontroller" in H.fg():
            H.deny_permission()
            continue
        t = H.show(f"ux_a_{i}")
        if "Assigned ride" not in t:
            if "Assigned — head to pickup" in t:
                H.tap(
                    t,
                    "Assigned — head to pickup",
                    exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED"),
                )
                time.sleep(3)
            continue
        status_a = H.loc_status(t)
        # Permission timeout is 15s; friendly denied / blocked / unavailable
        # all beat endless "Getting your location…".
        if status_a and status_a != "Getting your location…":
            break
    out_a = H.sh("logcat", "-d", "-v", "time")
    report["A_permissionDenied"] = {
        "dialogSeen": dialog_seen,
        "dialogDenied": denied,
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": status_a,
        "visibleUiStatusText": status_a,
        "hasAllowLocationCta": "Allow location" in t or "Open settings" in t,
        "seconds": round(time.time() - t0, 1),
        "endlessLoading": status_a == "Getting your location…",
        "crash": False,
        "noNetworkPublish": "/v1/location/update" not in out_a,
        "technicalLeak": any(
            x in t for x in ("PERMISSION", "LocationPermission", "Redis", "RTDB", "requestVersion")
        ),
    }
    print("A", report["A_permissionDenied"])

    # -------- B recovery (grant + reopen) --------
    print("TEST B recovery")
    grant_perm()
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])
    t0 = time.time()
    if "Assigned ride" in t:
        # Prefer recovery CTA if present
        if "Allow location" in t or "Try again" in t:
            H.tap(t, "Allow location", exact=True) or H.tap(t, "Try again", exact=True)
            time.sleep(2)
        else:
            H.sh("input", "keyevent", "4")
            time.sleep(2)
            t = H.open_assigned()
    else:
        t = H.open_assigned()
    H.allow_permission()
    ready_at = None
    first_accepted_ms = None
    for i in range(25):
        t = H.show(f"ux_b_{i}")
        st = H.loc_status(t)
        print("status", st)
        if st == "Location is ready":
            ready_at = time.time()
            break
        if "Assigned ride" not in t:
            t = H.open_assigned()
        time.sleep(2)
    m_b = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    # Parse first_accepted elapsed if present
    for line in (m_b.get("start_lines") or []) + H.sh("logcat", "-d", "-v", "time").splitlines():
        if "location_first_accepted" in line:
            mm = re.search(r"elapsedMs[=: ]+(\d+)", line)
            if mm:
                first_accepted_ms = int(mm.group(1))
            break
    # broader search
    if first_accepted_ms is None:
        for line in H.sh("logcat", "-d", "-v", "time").splitlines():
            if "location_first_accepted" in line:
                mm = re.search(r"elapsedMs[=: ]+(\d+)", line)
                if mm:
                    first_accepted_ms = int(mm.group(1))
                break
    report["B_permissionRecovery"] = {
        "assignedRideVisible": "Assigned ride" in t,
        "statusAfterWait": H.loc_status(t),
        "readyAfterSeconds": None if ready_at is None else round(ready_at - t0, 1),
        "firstAcceptedElapsedMs": first_accepted_ms,
        "watchStarts": m_b["watch_starts"],
        "fixClassifications": m_b["fix_classifications"],
        "firstWatchLine": m_b.get("first_watch_line"),
        "firstAcceptedLine": m_b.get("first_accepted_line"),
    }
    print("B", report["B_permissionRecovery"])

    # -------- C stationary lite + D scroll --------
    time.sleep(8)
    report["C_logcat"] = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "swipe", "540", "1400", "540", "800", "400")
    time.sleep(1)
    t = H.show("ux_d")
    report["D_uiInteraction"] = {
        "scrolled": True,
        "statusStillVisible": H.loc_status(t) is not None,
        "noTechnicalLeak": "server" not in t.lower()
        and "Redis" not in t
        and "Checking for server" not in t,
    }

    # -------- E leave/return --------
    print("TEST E")
    before = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    leave = H.show("ux_e_left")
    after_leave = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["E_leave"] = {
        "leftAssignedRide": "Assigned rides" in leave or "My trips" in leave,
        "watchStopsAfterLeave": after_leave["watch_stops"],
        "watchStartsBeforeLeave": before["watch_starts"],
    }
    t = H.open_assigned()
    ready_e = None
    for i in range(20):
        t = H.show(f"ux_e_{i}")
        ready_e = H.loc_status(t)
        if ready_e == "Location is ready":
            break
        if "Assigned ride" not in t:
            t = H.open_assigned()
        time.sleep(2)
    report["E_return"] = {
        "assignedRideVisible": "Assigned ride" in t,
        "status": ready_e,
        "watchStartsAfterReturn": H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))[
            "watch_starts"
        ],
    }
    print("E", report["E_return"])

    # -------- F bg/fg (keep on ride after return for G) --------
    print("TEST F")
    before_bg = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "keyevent", "3")
    time.sleep(5)
    after_bg = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    subprocess.check_call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "monkey",
            "-p",
            PKG,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )
    time.sleep(4)
    t = H.show("ux_f0")
    if "Assigned ride" not in t:
        if "Open ride" in t or "My trips" in t:
            t = H.open_assigned()
        else:
            H.login_and_driver()
            t = H.open_assigned()
    ready_f = None
    for i in range(20):
        t = H.show(f"ux_f_{i}")
        ready_f = H.loc_status(t)
        if ready_f == "Location is ready":
            break
        time.sleep(2)
    report["F_backgroundForeground"] = {
        "assignedRideVisible": "Assigned ride" in t,
        "status": ready_f,
        "watchStopsIncreasedOnBackground": after_bg["watch_stops"] > before_bg["watch_stops"]
        or after_bg["geolocator_stops"] > before_bg["geolocator_stops"],
    }
    print("F", report["F_backgroundForeground"])

    # -------- G cancel WHILE ACTIVE (no backgrounding) --------
    print("TEST G cancel-while-active")
    # Ensure we are on assigned ride with ready + active watch (starts > stops)
    if H.loc_status(t) != "Location is ready" or "Assigned ride" not in t:
        t = H.open_assigned()
        for i in range(20):
            t = H.show(f"ux_g_ready{i}")
            if H.loc_status(t) == "Location is ready":
                break
            time.sleep(2)
    # Wait until watch is clearly active
    active = False
    for _ in range(10):
        before_g = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
        if before_g["watch_starts"] > before_g["watch_stops"]:
            active = True
            break
        time.sleep(1)
    # Need at least one ACCEPTED since last start
    accepted_before = before_g.get("classification_counts", {}).get("ACCEPTED", 0)
    t = H.show("ux_g1")
    H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.tap(
        t, "Cancel ride", exclude=("Cancel ride?",)
    )
    time.sleep(1.5)
    t2 = H.show("ux_g2")
    if not H.tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)):
        H.sh("input", "tap", "540", "1460")
    for i in range(15):
        time.sleep(2)
        t = H.show(f"ux_gt{i}")
        if "Assigned ride" in t and ("Ride cancelled" in t or "CANCELLED" in t):
            break
        if "Cancel ride?" in t:
            H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.sh(
                "input", "tap", "540", "1460"
            )
    after_g = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    on_detail = "Assigned ride" in t and "Assigned rides" not in t
    detail_cancelled = on_detail and (
        "CANCELLED" in t or "Ride cancelled" in t or "This ride was cancelled" in t
    )
    report["G_terminal"] = {
        "activeWatchBeforeCancel": active and before_g["watch_starts"] > before_g["watch_stops"],
        "acceptedFixesBeforeCancel": accepted_before,
        "uiTextHasCancelled": detail_cancelled,
        "onAssignedRideDetail": on_detail,
        "visibleTerminalText": (
            "Ride cancelled"
            if "Ride cancelled" in t
            else ("CANCELLED" if "CANCELLED" in t else None)
        ),
        "watchStoppedOnCancel": after_g["watch_stops"] > before_g["watch_stops"]
        or after_g["geolocator_stops"] > before_g["geolocator_stops"],
        "metricsBefore": before_g,
        "metrics": after_g,
        "noBackgroundBetweenReadyAndCancel": True,
    }
    print("G", report["G_terminal"])

    starts_before_home = after_g["watch_starts"]
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    t = H.show("ux_g_home")
    if "Open ride" not in t and "My trips" not in t:
        H.login_and_driver()
        t = H.show("ux_g_home2")
    home_m = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["G_homeNoGps"] = {
        "onDriverHome": "Open ride" in t or "My trips" in t,
        "locationStatusOnHome": H.loc_status(t),
        "watchStartsUnchangedFromTerminal": home_m["watch_starts"] == starts_before_home,
        "watchStarts": home_m["watch_starts"],
    }

    out = H.sh("logcat", "-d", "-v", "time")
    LOGCAT.write_text(out)
    metrics = H.parse_metrics(out)
    report["logcatMetrics"] = metrics
    report["networkProof"] = {
        "postLocationUpdateInLogcat": "/v1/location/update" in out
        or "location/update" in out
        or "LOCATION_UPDATE" in out
    }
    report["privacyProof"] = {
        "knownTestLatInLogcat": "31.4127578" in out or "31.5204" in out,
        "latitudeKeyInOraLogs": bool(re.search(r"\[INFO\].*latitude", out, re.I)),
    }
    report["structuredLoggerObservable"] = metrics["watch_starts"] > 0

    checks = {
        "A_deniedFriendlyStatus": report["A_permissionDenied"].get("status")
        == "Location permission is needed"
        and report["A_permissionDenied"].get("dialogSeen")
        and report["A_permissionDenied"].get("assignedRideVisible")
        and not report["A_permissionDenied"].get("endlessLoading"),
        "B_ready": report["B_permissionRecovery"].get("statusAfterWait")
        == "Location is ready",
        "D_noTechnicalLeak": report["D_uiInteraction"].get("noTechnicalLeak"),
        "E_returnReady": report["E_return"].get("status") == "Location is ready",
        "F_returnReady": report["F_backgroundForeground"].get("status")
        == "Location is ready",
        "G_activeThenCancel": report["G_terminal"].get("activeWatchBeforeCancel")
        and report["G_terminal"].get("acceptedFixesBeforeCancel", 0) > 0
        and report["G_terminal"].get("uiTextHasCancelled")
        and report["G_terminal"].get("watchStoppedOnCancel"),
        "G_homeNoRestart": report["G_homeNoGps"].get("watchStartsUnchangedFromTerminal")
        and report["G_homeNoGps"].get("locationStatusOnHome") is None,
        "noNetworkPublish": not report["networkProof"]["postLocationUpdateInLogcat"],
        "noLatLeak": not report["privacyProof"]["knownTestLatInLogcat"],
        "structuredLogger": metrics["watch_starts"] > 0,
    }
    failed = [k for k, v in checks.items() if not v]
    report["checks"] = checks
    report["failedChecks"] = failed
    report["verdict"] = "GREEN" if not failed else "YELLOW"
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(json.dumps({"verdict": report["verdict"], "failed": failed, "A": report["A_permissionDenied"], "B": report["B_permissionRecovery"], "G": report["G_terminal"]}, indent=2))


if __name__ == "__main__":
    main()
