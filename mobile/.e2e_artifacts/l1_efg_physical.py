#!/usr/bin/env python3
"""L1 physical gap closure: E leave/return, F bg/fg, G cancel-while-active.

Assumes permission-denied UX (A) and recovery (B) already proven. Grants
location up front and focuses on watch lifecycle + cancel.
"""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import l1_gap_closure_physical as H

DEV, PKG, ART, LOGCAT = H.DEV, H.PKG, H.ART, H.LOGCAT
REPORT = ART / "L1_PHYSICAL_VERIFICATION_REPORT.json"


def grant_perm() -> None:
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
        subprocess.call(["adb", "-s", DEV, "shell", "pm", "grant", PKG, perm])


def wait_ready(tag: str, rounds: int = 25) -> tuple[str, str | None]:
    t = ""
    st = None
    for i in range(rounds):
        t = H.show(f"{tag}_{i}")
        if "permissioncontroller" in H.fg() or "While using the app" in t:
            H.allow_permission()
            time.sleep(1)
            continue
        if not H.on_assigned_detail(t):
            if "Assigned — head to pickup" in t or "DRIVER_ASSIGNED" in t:
                H.tap(
                    t,
                    "Assigned — head to pickup",
                    exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED"),
                ) or H.tap(t, "DRIVER_ASSIGNED", exclude=("CANCELLED",))
                time.sleep(2)
                continue
            t = H.open_assigned()
            continue
        st = H.loc_status(t)
        print("status", st)
        if st == "Location is ready":
            return t, st
        time.sleep(2)
    return t, st


def metrics() -> dict:
    return H.parse_metrics(H.sh("logcat", "-d", "-v", "time"))


def cancel_active_ride(t: str) -> str:
    """Open cancel dialog and confirm; wait until polling is not blocking."""
    for _ in range(12):
        t = H.show("g_wait_idle")
        if "Cancel ride" in t and "Updating ride" not in t:
            break
        time.sleep(1.5)
    H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.tap(
        t, "Cancel ride", exclude=("Cancel ride?",)
    )
    time.sleep(1.5)
    t2 = H.show("g_dialog")
    if "Cancel ride?" in t2 or "Keep ride" in t2:
        if not H.tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)):
            # Dialog confirm is the lower primary action on SM-A325F.
            H.sh("input", "tap", "540", "1460")
    else:
        H.tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.sh(
            "input", "tap", "540", "1460"
        )
    for i in range(20):
        time.sleep(2)
        t = H.show(f"g_term_{i}")
        if "Cancel ride?" in t:
            H.tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or H.sh(
                "input", "tap", "540", "1460"
            )
            continue
        if "Assigned ride" in t and (
            "Ride cancelled" in t or "CANCELLED" in t or "This ride was cancelled" in t
        ):
            return t
        if "Ride cancelled" in t or "CANCELLED" in t:
            return t
    return t


def main() -> None:
    import os

    if os.environ.get("L1_SKIP_ASSIGN") == "1":
        print("SKIP_ASSIGN using existing l1_assigned_ride.json")
    else:
        print("ASSIGN")
        subprocess.check_call(
            ["python3", str(ART / "l1_staging_assign_ride.py")], cwd=str(ART)
        )
    ride = json.loads((ART / "l1_assigned_ride.json").read_text())["rideId"]
    report: dict = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": H.sh("getprop", "ro.product.model").strip(),
        "androidVersion": H.sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": ride,
        "method": "l1_efg_physical",
        "loggerSink": "ConsoleAppLogger → dart:developer name=ora; debug assert print mirror",
        "priorProven": {
            "A_denyUx": "GREEN (prior run)",
            "B_recovery": "GREEN (prior run)",
        },
        "doNotStartL2": True,
    }

    grant_perm()
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

    print("BASELINE ready")
    t = H.open_assigned()
    H.allow_permission()
    t, ready = wait_ready("base")
    base = metrics()
    report["baseline"] = {
        "assignedRideVisible": H.on_assigned_detail(t),
        "status": ready,
        "metrics": base,
    }
    if ready != "Location is ready":
        report["verdict"] = "YELLOW"
        report["failedChecks"] = ["baseline_ready"]
        report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        REPORT.write_text(json.dumps(report, indent=2))
        print(json.dumps({"verdict": "YELLOW", "failed": ["baseline_ready"]}, indent=2))
        return

    # -------- E leave / return --------
    print("TEST E")
    before_e = metrics()
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    leave = H.show("e_left")
    after_leave = metrics()
    left = "Assigned rides" in leave or "My trips" in leave
    stopped = after_leave["watch_stops"] > before_e["watch_stops"] or (
        after_leave["geolocator_stops"] > before_e["geolocator_stops"]
    )
    report["E_leave"] = {
        "leftAssignedRide": left,
        "watchStopsIncreased": stopped,
        "watchStopsAfterLeave": after_leave["watch_stops"],
        "watchStartsBeforeLeave": before_e["watch_starts"],
        "metricsAfterLeave": after_leave,
    }
    t = H.open_assigned()
    t, ready_e = wait_ready("e_ret")
    after_return = metrics()
    report["E_return"] = {
        "assignedRideVisible": H.on_assigned_detail(t),
        "status": ready_e,
        "watchStartsAfterReturn": after_return["watch_starts"],
        "watchStartedAgain": after_return["watch_starts"] > before_e["watch_starts"],
        "metrics": after_return,
    }
    print("E", report["E_leave"], report["E_return"])

    # -------- F background / foreground --------
    print("TEST F")
    # Ensure ready on ride before bg
    if H.loc_status(t) != "Location is ready":
        t, _ = wait_ready("f_prep")
    before_bg = metrics()
    H.sh("input", "keyevent", "3")  # HOME
    time.sleep(6)
    after_bg = metrics()
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
    if not H.on_assigned_detail(t):
        if "Open ride" in t or "My trips" in t or "Assigned rides" in t:
            t = H.open_assigned()
        else:
            H.login_and_driver()
            t = H.open_assigned()
    t, ready_f = wait_ready("f_ret")
    after_fg = metrics()
    report["F_backgroundForeground"] = {
        "assignedRideVisible": H.on_assigned_detail(t),
        "status": ready_f,
        "watchStopsIncreasedOnBackground": after_bg["watch_stops"] > before_bg["watch_stops"]
        or after_bg["geolocator_stops"] > before_bg["geolocator_stops"],
        "noDuplicateWatchers": after_fg["watch_starts"]
        <= before_bg["watch_starts"] + 2,  # stop+one restart is expected
        "metricsBeforeBg": before_bg,
        "metricsAfterBg": after_bg,
        "metricsAfterFg": after_fg,
    }
    print("F", report["F_backgroundForeground"])

    # -------- G cancel while active --------
    print("TEST G cancel-while-active")
    if H.loc_status(t) != "Location is ready" or not H.on_assigned_detail(t):
        t = H.open_assigned()
        t, _ = wait_ready("g_ready")
    active = False
    before_g = metrics()
    for _ in range(15):
        before_g = metrics()
        accepted = before_g.get("classification_counts", {}).get("ACCEPTED", 0)
        if before_g["watch_starts"] > before_g["watch_stops"] and accepted > 0:
            active = True
            break
        time.sleep(1)
    accepted_before = before_g.get("classification_counts", {}).get("ACCEPTED", 0)
    t = H.show("g1")
    t = cancel_active_ride(t)
    after_g = metrics()
    on_detail = H.on_assigned_detail(t)
    detail_cancelled = (
        "CANCELLED" in t or "Ride cancelled" in t or "This ride was cancelled" in t
    )
    # Prefer cancelled confirmation on detail; also accept if still on detail with chip.
    report["G_terminal"] = {
        "activeWatchBeforeCancel": active,
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
        "noFurtherAcceptedGrowth": after_g.get("classification_counts", {}).get(
            "ACCEPTED", 0
        )
        <= accepted_before + 2,  # allow in-flight callbacks already queued
        "metricsBefore": before_g,
        "metrics": after_g,
        "noBackgroundBetweenReadyAndCancel": True,
    }
    print("G", report["G_terminal"])

    starts_before_home = after_g["watch_starts"]
    H.sh("input", "keyevent", "4")
    time.sleep(3)
    t = H.show("g_home")
    if "Open ride" not in t and "My trips" not in t:
        H.login_and_driver()
        t = H.show("g_home2")
    home_m = metrics()
    report["G_homeNoGps"] = {
        "onDriverHome": "Open ride" in t or "My trips" in t,
        "locationStatusOnHome": H.loc_status(t),
        "watchStartsUnchangedFromTerminal": home_m["watch_starts"] == starts_before_home,
        "watchStarts": home_m["watch_starts"],
    }

    out = H.sh("logcat", "-d", "-v", "time")
    LOGCAT.write_text(out)
    m = H.parse_metrics(out)
    report["logcatMetrics"] = m
    report["networkProof"] = {
        "postLocationUpdateInLogcat": "/v1/location/update" in out
        or "location/update" in out
        or "LOCATION_UPDATE" in out
    }
    report["privacyProof"] = {
        "knownTestLatInLogcat": "31.4127578" in out or "31.5204" in out,
        "latitudeKeyInOraLogs": bool(re.search(r"\[INFO\].*latitude", out, re.I)),
    }

    checks = {
        "E_leaveStopsWatch": report["E_leave"].get("leftAssignedRide")
        and report["E_leave"].get("watchStopsIncreased"),
        "E_returnReady": report["E_return"].get("status") == "Location is ready"
        and report["E_return"].get("watchStartedAgain"),
        "F_bgStopsWatch": report["F_backgroundForeground"].get(
            "watchStopsIncreasedOnBackground"
        ),
        "F_returnReady": report["F_backgroundForeground"].get("status")
        == "Location is ready",
        "F_noDuplicateWatchers": report["F_backgroundForeground"].get(
            "noDuplicateWatchers"
        ),
        "G_activeThenCancel": report["G_terminal"].get("activeWatchBeforeCancel")
        and report["G_terminal"].get("acceptedFixesBeforeCancel", 0) > 0
        and report["G_terminal"].get("uiTextHasCancelled")
        and report["G_terminal"].get("watchStoppedOnCancel"),
        "G_homeNoRestart": report["G_homeNoGps"].get("watchStartsUnchangedFromTerminal")
        and report["G_homeNoGps"].get("locationStatusOnHome") is None,
        "noNetworkPublish": not report["networkProof"]["postLocationUpdateInLogcat"],
        "noLatLeak": not report["privacyProof"]["knownTestLatInLogcat"],
    }
    failed = [k for k, v in checks.items() if not v]
    report["checks"] = checks
    report["failedChecks"] = failed
    report["verdict"] = "GREEN" if not failed else "YELLOW"
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(
        json.dumps(
            {
                "verdict": report["verdict"],
                "failed": failed,
                "E": {"leave": report["E_leave"], "return": report["E_return"]},
                "F": report["F_backgroundForeground"],
                "G": report["G_terminal"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
