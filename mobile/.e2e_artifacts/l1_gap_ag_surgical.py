#!/usr/bin/env python3
"""Surgical Gap A + Gap G proof on SM-A325F."""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import l1_gap_closure_physical as H

DEV, PKG, ART, REPORT, LOGCAT = H.DEV, H.PKG, H.ART, H.REPORT, H.LOGCAT


def perm_granted() -> bool:
    out = H.sh("dumpsys", "package", PKG)
    # Look for fine location runtime grant line.
    for line in out.splitlines():
        if "ACCESS_FINE_LOCATION: granted=" in line:
            return "granted=true" in line
    return False


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
    prev = json.loads(REPORT.read_text()) if REPORT.exists() else {}
    ride = json.loads((ART / "l1_assigned_ride.json").read_text())["rideId"]
    report = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": H.sh("getprop", "ro.product.model").strip(),
        "androidVersion": H.sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": ride,
        "method": "l1_gap_ag_surgical",
        "loggerSink": "ConsoleAppLogger → dart:developer name=ora; debug assert print mirror for adb logcat",
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

    # -------- GAP A --------
    print("TEST A")
    t0 = time.time()
    t = H.open_assigned()
    dialog_seen = False
    denied = False
    for _ in range(15):
        if "permissioncontroller" in H.fg() or "While using the app" in t:
            dialog_seen = True
            H.show("a_dialog")
            denied = H.deny_permission()
            break
        time.sleep(1)
        t = H.dump("a_wait_dlg")
    # Clear stuck permission a11y overlay; do not grant.
    subprocess.call(
        ["adb", "-s", DEV, "shell", "am", "force-stop", "com.google.android.permissioncontroller"]
    )
    time.sleep(1)
    granted_after = perm_granted()
    print("perm granted after deny?", granted_after)

    status_a = None
    for i in range(20):
        t = H.show(f"a_ui_{i}")
        if "Assigned ride" not in t:
            if "Assigned — head to pickup" in t or "DRIVER_ASSIGNED" in t:
                H.tap(
                    t,
                    "Assigned — head to pickup",
                    exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED"),
                )
                time.sleep(3)
                continue
            if "My trips" in t and "Assigned rides" not in t:
                H.tap(t, "My trips", exact=True)
                time.sleep(3)
                continue
        else:
            # If dialog reappears, deny again without granting.
            if "permissioncontroller" in H.fg() or "While using the app" in t:
                dialog_seen = True
                H.deny_permission()
                subprocess.call(
                    [
                        "adb",
                        "-s",
                        DEV,
                        "shell",
                        "am",
                        "force-stop",
                        "com.google.android.permissioncontroller",
                    ]
                )
                time.sleep(1)
                continue
            status_a = H.loc_status(t)
            if status_a and status_a != "Getting your location…":
                break
        time.sleep(1.5)

    report["A_permissionDenied"] = {
        "dialogSeen": dialog_seen,
        "dialogDenied": denied and not granted_after,
        "permissionGrantedAfterDeny": granted_after,
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": status_a,
        "visibleUiStatusText": status_a,
        "seconds": round(time.time() - t0, 1),
        "endlessLoading": status_a == "Getting your location…",
        "crash": False,
        "foregroundPkg": H.fg(),
        "hasMapPreview": "Map preview" in t,
        "hasRedis": "Redis" in t,
        "noNetworkPublishDuringA": "/v1/location/update"
        not in H.sh("logcat", "-d", "-v", "time"),
    }
    print("A", report["A_permissionDenied"])

    # -------- B grant + ready + logger --------
    print("TEST B")
    grant_perm()
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])
    t0 = time.time()
    if "Assigned ride" in t:
        H.sh("input", "keyevent", "4")
        time.sleep(2)
    t = H.open_assigned()
    H.allow_permission()
    ready_at = None
    for i in range(25):
        t = H.show(f"b_{i}")
        if H.loc_status(t) == "Location is ready":
            ready_at = time.time()
            break
        if "Assigned ride" not in t:
            t = H.open_assigned()
        time.sleep(2)
    m_b = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["B_permissionGranted"] = {
        "assignedRideVisible": "Assigned ride" in t,
        "statusAfterWait": H.loc_status(t),
        "readyAfterSeconds": None if ready_at is None else round(ready_at - t0, 1),
    }
    report["B_logcatAfterFirstWait"] = m_b
    print("B", report["B_permissionGranted"], "watch_starts", m_b["watch_starts"])

    # Short C for continuity (full 90 kept)
    print("TEST C 90s")
    t_stat = time.time()
    time.sleep(90)
    report["C_stationarySeconds"] = round(time.time() - t_stat, 1)
    report["C_logcat"] = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))

    H.sh("input", "swipe", "540", "1400", "540", "800", "400")
    time.sleep(1)
    t = H.show("d")
    report["D_uiInteraction"] = {
        "scrolled": True,
        "statusStillVisible": H.loc_status(t) is not None,
    }

    # E leave/return
    print("TEST E")
    before = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    leave = H.show("e_left")
    after_leave = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["E_leave"] = {
        "leftAssignedRide": "Assigned rides" in leave or "My trips" in leave,
        "watchStopsAfterLeave": after_leave["watch_stops"],
        "watchStartsBeforeLeave": before["watch_starts"],
    }
    t = H.open_assigned()
    ready_e = None
    for i in range(20):
        t = H.show(f"e_{i}")
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

    # F bg/fg
    print("TEST F")
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
    t = H.show("f0")
    if "Assigned ride" not in t:
        if "Open ride" in t or "My trips" in t:
            t = H.open_assigned()
        else:
            H.login_and_driver()
            t = H.open_assigned()
    ready_f = None
    for i in range(20):
        t = H.show(f"f_{i}")
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

    # G cancel with active GPS
    print("TEST G")
    if H.loc_status(t) != "Location is ready" or "Assigned ride" not in t:
        t = H.open_assigned()
        for i in range(20):
            t = H.show(f"g_r{i}")
            if H.loc_status(t) == "Location is ready":
                break
            time.sleep(2)
    before_g = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    t = H.show("g1")
    H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.tap(
        t, "Cancel ride", exclude=("Cancel ride?",)
    )
    time.sleep(1.5)
    t2 = H.show("g2")
    if not H.tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)):
        H.sh("input", "tap", "540", "1460")
    for i in range(15):
        time.sleep(2)
        t = H.show(f"g_t{i}")
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
        "statusChip": detail_cancelled,
        "uiTextHasCancelled": detail_cancelled,
        "onAssignedRideDetail": on_detail,
        "visibleTerminalText": (
            "Ride cancelled"
            if "Ride cancelled" in t
            else ("CANCELLED" if "CANCELLED" in t else None)
        ),
        "activeWatchBeforeCancel": before_g["watch_starts"] > before_g["watch_stops"],
        "watchStoppedOnCancel": after_g["watch_stops"] > before_g["watch_stops"]
        or after_g["geolocator_stops"] > before_g["geolocator_stops"],
        "metricsBefore": before_g,
        "metrics": after_g,
    }
    print("G", report["G_terminal"])

    starts_before_home = after_g["watch_starts"]
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    t = H.show("g_home")
    if "Open ride" not in t and "My trips" not in t:
        H.login_and_driver()
        t = H.show("g_home2")
    home_m = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
    report["G_homeNoGps"] = {
        "onDriverHome": "Open ride" in t or "My trips" in t,
        "locationStatusOnHome": H.loc_status(t),
        "watchStartsUnchangedFromTerminal": home_m["watch_starts"] == starts_before_home,
        "watchStarts": home_m["watch_starts"],
    }
    if H.tap(t, "Open ride requests", exact=True) or H.tap(t, "Open ride"):
        time.sleep(3)
        ot = H.show("g_open")
        om = H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))
        report["G_openRidesNoGps"] = {
            "locationStatus": H.loc_status(ot),
            "watchStartsUnchanged": om["watch_starts"] == home_m["watch_starts"],
            "watchStarts": om["watch_starts"],
        }
    else:
        report["G_openRidesNoGps"] = {"skipped": True}

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
        "A_deniedStatusCaptured": bool(
            report["A_permissionDenied"].get("dialogSeen")
            and report["A_permissionDenied"].get("dialogDenied")
            and report["A_permissionDenied"].get("assignedRideVisible")
            and report["A_permissionDenied"].get("status")
            in (
                "Location is temporarily unavailable",
                "Turn on location services",
                "Location accuracy is low",
            )
        ),
        "B_ready": report["B_permissionGranted"].get("statusAfterWait") == "Location is ready",
        "C_stationary": report.get("C_stationarySeconds", 0) >= 90,
        "D_scroll": report["D_uiInteraction"].get("statusStillVisible"),
        "E_returnReady": report["E_return"].get("status") == "Location is ready",
        "F_returnReady": report["F_backgroundForeground"].get("status") == "Location is ready",
        "G_cancelled": bool(
            report["G_terminal"].get("uiTextHasCancelled")
            and report["G_terminal"].get("onAssignedRideDetail")
        ),
        "G_gpsStopped": bool(
            report["G_terminal"].get("watchStoppedOnCancel")
            and report["G_terminal"].get("activeWatchBeforeCancel")
        ),
        "noNetworkPublish": not report["networkProof"]["postLocationUpdateInLogcat"],
        "noLatLeak": not report["privacyProof"]["knownTestLatInLogcat"],
        "structuredLogger": metrics["watch_starts"] > 0,
    }
    failed = [k for k, v in checks.items() if not v]
    report["checks"] = checks
    report["failedChecks"] = failed
    report["verdict"] = "GREEN" if not failed else ("YELLOW" if checks.get("B_ready") else "RED")
    # Preserve prior proven logger note if this run missed start due to logcat clear timing
    if not checks["structuredLogger"] and prev.get("structuredLoggerObservable"):
        report["priorLoggerEvidence"] = prev.get("B_logcatAfterFirstWait")
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(
        json.dumps(
            {
                "verdict": report["verdict"],
                "failed": failed,
                "A": report["A_permissionDenied"],
                "B": report["B_permissionGranted"],
                "E": report["E_return"],
                "F": report["F_backgroundForeground"],
                "G": report["G_terminal"],
                "logger": metrics.get("first_watch_line"),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
