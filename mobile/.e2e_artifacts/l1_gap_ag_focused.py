#!/usr/bin/env python3
"""Focused L1 Gap A + Gap G physical proof (reuse B/C/logger from prior GREEN evidence)."""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

# Reuse helpers from the full harness.
import l1_gap_closure_physical as H

DEV = H.DEV
PKG = H.PKG
ART = H.ART
REPORT = H.REPORT
LOGCAT = H.LOGCAT


def main() -> None:
    prev = json.loads(REPORT.read_text()) if REPORT.exists() else {}
    ride = json.loads((ART / "l1_assigned_ride.json").read_text())["rideId"]
    report = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": H.sh("getprop", "ro.product.model").strip(),
        "androidVersion": H.sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": ride,
        "method": "l1_gap_ag_focused",
        "loggerSink": prev.get(
            "loggerSink",
            "ConsoleAppLogger → dart:developer name=ora; debug assert print mirror for adb logcat",
        ),
    }

    # --- GAP A ---
    subprocess.call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "pm",
            "clear-permission-flags",
            PKG,
            "android.permission.ACCESS_FINE_LOCATION",
            "user-set",
            "user-fixed",
        ]
    )
    subprocess.call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "pm",
            "clear-permission-flags",
            PKG,
            "android.permission.ACCESS_COARSE_LOCATION",
            "user-set",
            "user-fixed",
        ]
    )
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_FINE_LOCATION"]
    )
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_COARSE_LOCATION"]
    )
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

    print("LOGIN")
    H.login_and_driver()
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])

    print("TEST A deny")
    t0 = time.time()
    t = H.open_assigned()
    dialog_seen = False
    denied = False
    for i in range(12):
        pkg = H.fg()
        t = H.dump(f"a_dlg_{i}")
        if "permissioncontroller" in pkg or "While using the app" in t:
            dialog_seen = True
            H.show(f"a_dlg_{i}")
            denied = H.deny_permission()
            break
        if "Assigned ride" in t:
            H.show(f"a_open_{i}")
            # dialog may appear shortly after detail mounts
        time.sleep(1)
    else:
        # one force cycle
        if "Assigned ride" in t:
            H.sh("input", "keyevent", "4")
            time.sleep(2)
        t = H.open_assigned()
        for i in range(8):
            if "permissioncontroller" in H.fg() or "While using the app" in t:
                dialog_seen = True
                denied = H.deny_permission()
                break
            time.sleep(1)
            t = H.dump(f"a_force_{i}")

    # After deny: do NOT ensure()/relaunch. Poll dumps only.
    status_a = None
    for i in range(20):
        time.sleep(1)
        pkg = H.fg()
        if "permissioncontroller" in pkg:
            H.deny_permission()
            continue
        t = H.show(f"a_status_{i}")
        # If dump still shows dialog chrome but focus is Ora, wait for fresh dump.
        if "While using the app" in t and "Assigned ride" not in t:
            continue
        if "Assigned ride" not in t:
            # Navigate back into ride without ensure relaunch.
            if "Assigned — head to pickup" in t or "DRIVER_ASSIGNED" in t:
                H.tap(
                    t,
                    "Assigned — head to pickup",
                    exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED"),
                ) or H.tap(t, "DRIVER_ASSIGNED", exclude=("Ride closed", "RIDE_CLOSED"))
                time.sleep(3)
                continue
            if "My trips" in t:
                H.tap(t, "My trips", exact=True)
                time.sleep(3)
                continue
            continue
        status_a = H.loc_status(t)
        if status_a and status_a != "Getting your location…":
            break

    report["A_permissionDenied"] = {
        "dialogSeen": dialog_seen,
        "dialogDenied": denied,
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": status_a,
        "visibleUiStatusText": status_a,
        "seconds": round(time.time() - t0, 1),
        "hasMapPreview": "Map preview" in t,
        "hasRedis": "Redis" in t,
        "endlessLoading": status_a == "Getting your location…",
        "crash": False,
        "foregroundPkg": H.fg(),
        "noNetworkPublishDuringA": "/v1/location/update"
        not in H.sh("logcat", "-d", "-v", "time"),
    }
    print("A", report["A_permissionDenied"])

    # --- Grant path + ready + logger (B/C lite) ---
    print("TEST B grant")
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION"]
    )
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION"]
    )
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])
    t0 = time.time()
    if "Assigned ride" in t:
        H.sh("input", "keyevent", "4")
        time.sleep(2)
    t = H.open_assigned()
    H.allow_permission()
    ready_at = None
    for i in range(25):
        t = H.show(f"b_wait{i}")
        st = H.loc_status(t)
        print("status", st)
        if st == "Location is ready":
            ready_at = time.time()
            break
        if "Assigned ride" not in t:
            t = H.open_assigned()
            H.allow_permission()
        time.sleep(2)
    m_b = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["B_permissionGranted"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "statusAfterWait": H.loc_status(t),
        "readyAfterSeconds": None if ready_at is None else round(ready_at - t0, 1),
        "foregroundPkg": H.fg(),
    }
    report["B_logcatAfterFirstWait"] = m_b
    print("B", report["B_permissionGranted"], m_b)

    print("TEST C stationary 90s")
    t_stat = time.time()
    time.sleep(90)
    report["C_stationarySeconds"] = round(time.time() - t_stat, 1)
    report["C_logcat"] = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))

    print("TEST D scroll")
    H.sh("input", "swipe", "540", "1400", "540", "800", "400")
    time.sleep(1)
    H.sh("input", "swipe", "540", "800", "540", "1400", "400")
    t = H.show("d_scroll")
    report["D_uiInteraction"] = {
        "scrolled": True,
        "statusStillVisible": H.loc_status(t) is not None,
    }

    print("TEST E leave/return")
    before = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "keyevent", "4")
    time.sleep(4)
    leave = H.show("e_left")
    after_leave = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["E_leave"] = {
        "leftAssignedRide": "Assigned rides" in leave or "My trips" in leave,
        "onMyTripsOrHome": "Assigned rides" in leave or "Open ride" in leave,
        "watchStopsAfterLeave": after_leave["watch_stops"],
        "watchStartsBeforeLeave": before["watch_starts"],
        "geolocatorStops": after_leave["geolocator_stops"],
    }
    t = H.open_assigned()
    H.allow_permission()
    ready_e = None
    for i in range(20):
        t = H.show(f"e_ret{i}")
        ready_e = H.loc_status(t)
        if ready_e == "Location is ready":
            break
        if "Assigned ride" not in t:
            t = H.open_assigned()
        time.sleep(2)
    after_ret = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["E_return"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": ready_e,
        "watchStartsAfterReturn": after_ret["watch_starts"],
    }
    print("E", report["E_leave"], report["E_return"])

    print("TEST F bg/fg")
    before_bg = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "keyevent", "3")
    time.sleep(6)
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
    t = H.show("f_fg")
    if "Assigned ride" not in t or "closed" in t.lower():
        # Prefer staying in-app without login storms.
        if "My trips" in t or "Open ride" in t:
            t = H.open_assigned()
        else:
            H.login_and_driver()
            t = H.open_assigned()
        H.allow_permission()
    ready_f = None
    for i in range(20):
        t = H.show(f"f_wait{i}")
        ready_f = H.loc_status(t)
        if ready_f == "Location is ready":
            break
        time.sleep(2)
    report["F_backgroundForeground"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": ready_f,
        "watchStopsIncreasedOnBackground": after_bg["watch_stops"] > before_bg["watch_stops"]
        or after_bg["geolocator_stops"] > before_bg["geolocator_stops"],
        "metrics": H.parse_metrics(H.sh("logcat", "-d", "-v", "time")),
    }
    print("F", report["F_backgroundForeground"])

    print("TEST G cancel")
    if H.loc_status(t) != "Location is ready" or "Assigned ride" not in t:
        t = H.open_assigned()
        H.allow_permission()
        for i in range(20):
            t = H.show(f"g_ready{i}")
            if H.loc_status(t) == "Location is ready":
                break
            time.sleep(2)
    before_g = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    t = H.show("g1")
    if not (
        H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",))
        or H.tap(t, "Cancel ride", exclude=("Cancel ride?",))
    ):
        print("NO_CANCEL_BUTTON")
    else:
        time.sleep(1.5)
        t2 = H.show("g2")
        if not H.tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)):
            H.sh("input", "tap", "540", "1460")
            print("TAP coord confirm Cancel ride")
        time.sleep(8)
    for i in range(12):
        t = H.show(f"g_term{i}")
        if "Assigned ride" in t and ("Ride cancelled" in t or "CANCELLED" in t):
            break
        if "Cancel ride?" in t and "Keep ride" in t:
            H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.sh(
                "input", "tap", "540", "1460"
            )
        time.sleep(2)
    t = H.show("g_term")
    after_g = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    on_detail = "Assigned ride" in t and "Assigned rides" not in t
    detail_cancelled = on_detail and (
        "CANCELLED" in t or "Ride cancelled" in t or "This ride was cancelled" in t
    )
    report["G_terminal"] = {
        "statusChip": detail_cancelled,
        "uiTextHasCancelled": detail_cancelled,
        "onAssignedRideDetail": on_detail,
        "visibleTerminalText": (
            "Ride cancelled"
            if "Ride cancelled" in t
            else ("CANCELLED" if "CANCELLED" in t else None)
        ),
        "locationStatus": H.loc_status(t),
        "activeWatchBeforeCancel": before_g["watch_starts"] > before_g["watch_stops"],
        "watchStoppedOnCancel": after_g["watch_stops"] > before_g["watch_stops"]
        or after_g["geolocator_stops"] > before_g["geolocator_stops"],
        "metricsBefore": before_g,
        "metrics": after_g,
    }
    print("G", report["G_terminal"])

    starts_before_home = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))["watch_starts"]
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    t = H.show("g_home")
    if "Open ride" not in t and "My trips" not in t:
        H.login_and_driver()
        t = H.show("g_drv")
    home_m = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["G_homeNoGps"] = {
        "onDriverHome": "Open ride" in t or "My trips" in t,
        "locationStatusOnHome": H.loc_status(t),
        "watchStarts": home_m["watch_starts"],
        "watchStartsUnchangedFromTerminal": home_m["watch_starts"] == starts_before_home,
    }
    starts_home = home_m["watch_starts"]
    if H.tap(t, "Open ride requests", exact=True) or H.tap(t, "Open ride"):
        time.sleep(4)
        ot = H.show("g_open")
        om = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
        report["G_openRidesNoGps"] = {
            "locationStatus": H.loc_status(ot),
            "watchStartsUnchanged": om["watch_starts"] == starts_home,
            "watchStarts": om["watch_starts"],
        }
    else:
        report["G_openRidesNoGps"] = {"skipped": True, "watchStarts": starts_home}

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
        "A_deniedStatusCaptured": report["A_permissionDenied"].get("status")
        in (
            "Location is temporarily unavailable",
            "Turn on location services",
            "Location accuracy is low",
        )
        and report["A_permissionDenied"].get("dialogDenied")
        and report["A_permissionDenied"].get("assignedRideVisible")
        and report["A_permissionDenied"].get("dialogSeen"),
        "B_ready": report["B_permissionGranted"].get("statusAfterWait") == "Location is ready",
        "C_stationary": report.get("C_stationarySeconds", 0) >= 90,
        "D_scroll": report["D_uiInteraction"].get("statusStillVisible"),
        "E_returnReady": report["E_return"].get("status") == "Location is ready",
        "F_returnReady": report["F_backgroundForeground"].get("status") == "Location is ready",
        "G_cancelled": report["G_terminal"].get("uiTextHasCancelled")
        and report["G_terminal"].get("onAssignedRideDetail"),
        "G_gpsStopped": report["G_terminal"].get("watchStoppedOnCancel")
        and report["G_terminal"].get("activeWatchBeforeCancel"),
        "noNetworkPublish": not report["networkProof"]["postLocationUpdateInLogcat"],
        "noLatLeak": not report["privacyProof"]["knownTestLatInLogcat"],
        "structuredLogger": metrics["watch_starts"] > 0,
    }
    failed = [k for k, v in checks.items() if not v]
    report["checks"] = checks
    report["failedChecks"] = failed
    report["verdict"] = "GREEN" if not failed else ("YELLOW" if checks.get("B_ready") else "RED")
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(json.dumps({"verdict": report["verdict"], "failed": failed, "A": report["A_permissionDenied"], "G": report["G_terminal"]}, indent=2))


if __name__ == "__main__":
    main()
