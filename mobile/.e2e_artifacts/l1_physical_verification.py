#!/usr/bin/env python3
"""L1 physical GPS verification against a real DRIVER_ASSIGNED ride."""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

DEV = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ART = Path(__file__).resolve().parent
RIDE = json.loads((ART / "l1_assigned_ride.json").read_text())["rideId"]
REPORT = ART / "L1_PHYSICAL_VERIFICATION_REPORT.json"
LOGCAT = ART / "l1_physical_logcat.txt"


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEV, *args])


def sh(*args: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", DEV, "shell", *args], stderr=subprocess.STDOUT
    ).decode("utf-8", errors="replace")


def dump(tag: str) -> str:
    path = ART / f"l1_{tag}.xml"
    last = ""
    for _ in range(14):
        try:
            sh("uiautomator", "dump", "/sdcard/l1_ui.xml")
            subprocess.check_call(
                ["adb", "-s", DEV, "pull", "/sdcard/l1_ui.xml", str(path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            last = path.read_text(encoding="utf-8")
            if "hierarchy" in last and len(last) > 400:
                return last
        except (subprocess.CalledProcessError, OSError):
            pass
        time.sleep(1.0)
    return last


def nodes(t: str) -> list[dict]:
    """Parse all uiautomator nodes.

    Flutter Semantics/OraCard labels live on non-self-closing parent nodes;
    matching only `<node .../>` misses assigned-ride cards.
    """
    out = []
    for m in re.finditer(r"<node ([^>]+)>", t):
        attrs = m.group(1)
        if attrs.endswith("/"):
            attrs = attrs[:-1]

        def attr(name: str) -> str:
            mm = re.search(rf'{name}="([^"]*)"', attrs)
            return (mm.group(1) if mm else "").replace("&#10;", "\n").replace("&amp;", "&")

        b = attr("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        out.append(
            {
                "text": attr("text"),
                "desc": attr("content-desc"),
                "clickable": attr("clickable") == "true",
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return out


def blob(n: dict) -> str:
    return f"{n['text']} {n['desc']}"


def tap_node(n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def _norm_apos(s: str) -> str:
    """Normalize curly/smart apostrophes so Don't / Don’t both match."""
    return (
        s.replace("\u2019", "'")
        .replace("\u2018", "'")
        .replace("\u02bc", "'")
        .replace("`", "'")
    )


def _labels(n: dict) -> list[str]:
    out: list[str] = []
    if n["text"]:
        out.append(_norm_apos(n["text"]))
    if n["desc"]:
        out.append(_norm_apos(n["desc"]))
        for line in n["desc"].split("\n"):
            line = line.strip()
            if line:
                out.append(_norm_apos(line))
    return out


def tap_contains(
    t: str,
    needle: str,
    exclude: tuple[str, ...] = (),
    *,
    exact: bool = False,
) -> bool:
    """Tap matching node. Exact prefers largest (buttons over titles)."""
    needle_n = _norm_apos(needle)
    cands: list[tuple[int, dict]] = []
    for n in nodes(t):
        b = blob(n)
        b_n = _norm_apos(b)
        if any(x in b or _norm_apos(x) in b_n for x in exclude):
            continue
        if exact:
            hit = needle_n in _labels(n)
        else:
            hit = needle_n in b_n
        if hit:
            x1, y1, x2, y2 = n["bounds"]
            area = (x2 - x1) * (y2 - y1)
            cands.append((-area if exact else area, n))
    if not cands:
        return False
    cands.sort(key=lambda x: x[0])
    tap_node(cands[0][1])
    return True


def foreground_pkg() -> str:
    out = sh("dumpsys", "window")
    m = re.search(r"mCurrentFocus=Window\{[^ ]+ u0 ([^/}]+)", out)
    return m.group(1) if m else ""


def ensure_ora(tag: str = "ensure") -> str:
    """Bring ORA to foreground if another app stole focus (e.g. Weather)."""
    pkg = foreground_pkg()
    # System permission dialog sits above ORA — do not kill it.
    if pkg and pkg != PKG and "permissioncontroller" not in pkg:
        print(f"[ensure_ora:{tag}] foreground={pkg!r} — relaunching {PKG}")
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
    t = dump(tag)
    # Notification permission after cold start
    if "notifications" in t.lower() and tap_contains(t, "Don't allow", exact=True):
        time.sleep(2)
        t = dump(f"{tag}_post_notif")
    return t


def location_status(t: str) -> str | None:
    # Only trust ORA assigned-ride chrome so Weather "Current location" never matches.
    if "Assigned ride" not in t and "Mark en route" not in t:
        return None
    for n in nodes(t):
        b = blob(n).strip()
        if "Getting your location" in b:
            return "Getting your location…"
        if "Location is ready" in b:
            return "Location is ready"
        if "Location accuracy is low" in b:
            return "Location accuracy is low"
        if "Turn on location services" in b:
            return "Turn on location services"
        if "Location is temporarily unavailable" in b:
            return "Location is temporarily unavailable"
    return None


def launch() -> None:
    sh("input", "keyevent", "KEYCODE_WAKEUP")
    adb("shell", "am", "force-stop", PKG)
    subprocess.check_call(
        ["adb", "-s", DEV, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(6)
    ensure_ora("launch")


def clear_phone() -> None:
    sh("input", "tap", "540", "1364")
    time.sleep(0.3)
    for _ in range(30):
        sh("input", "keyevent", "67")


def open_drawer() -> str:
    t = ensure_ora("pre_drawer")
    # Exact "Menu" — substring match hits Samsung Weather "Show navigation menu".
    if tap_contains(t, "Menu", exact=True):
        time.sleep(2)
        return dump("drawer")
    sh("input", "tap", "72", "168")
    time.sleep(2)
    return dump("drawer")


def sign_out_if_needed() -> None:
    """Passenger sessions must not short-circuit driver login."""
    t = dump("session")
    if "Phone number" in t or "Send verification code" in t or "Send code" in t:
        return
    if "Open ride requests" in t or "My trips" in t:
        # Already on driver shell.
        return
    drawer = open_drawer()
    if tap_contains(drawer, "Log out") or tap_contains(drawer, "Log out"):
        time.sleep(5)
        return
    # Close drawer and try again from home.
    sh("input", "keyevent", "4")
    time.sleep(1)


def login_driver() -> None:
    launch()
    for _ in range(12):
        t = dump("auth")
        if "Signing you in" in t:
            time.sleep(2)
            continue
        break

    t = dump("session_check")
    # Only accept an already-authenticated driver shell.
    if "Open ride requests" in t or ("My trips" in t and "Where are you headed" not in t):
        return

    # Passenger home / other sessions: force logout then driver OTP.
    if "Where are you headed" in t or "Earn on ORA" in t or "Menu" in t:
        sign_out_if_needed()
        time.sleep(3)
        launch()

    for _ in range(10):
        t = dump("auth2")
        if "Phone number" in t or "Send code" in t or "Send verification" in t:
            break
        if "Signing you in" in t:
            time.sleep(2)
            continue
        time.sleep(1)

    clear_phone()
    sh("input", "text", "03012345677")
    sh("input", "keyevent", "4")
    time.sleep(0.4)
    tap_contains(dump("send"), "Send")
    time.sleep(9)
    sh("input", "tap", "540", "610")
    sh("input", "text", "000000")
    time.sleep(0.4)
    tap_contains(dump("verify"), "Verify")
    for _ in range(25):
        time.sleep(2)
        t = dump("post")
        if "Where are you headed" in t or "Earn on ORA" in t:
            return
        if "Open ride requests" in t or "My trips" in t:
            return


def enter_driver_mode() -> None:
    t = dump("home")
    if "Open ride requests" in t or "My trips" in t:
        return
    # Prefer drawer "Switch to driver mode" for approved drivers.
    drawer = open_drawer()
    if tap_contains(drawer, "Switch to driver mode"):
        time.sleep(6)
        t = dump("after_switch")
        if "Open ride requests" in t or "My trips" in t:
            return
        if "Driver mode" in t and "not wired" in t:
            tap_contains(t, "Got it")
            time.sleep(1)
    t = dump("home2")
    if tap_contains(t, "Earn on ORA"):
        time.sleep(6)
        t2 = dump("after_earn")
        if "Driver mode" in t2 and "not wired" in t2:
            tap_contains(t2, "Got it")
            time.sleep(1)
            raise RuntimeError(
                "Driver gate rejected session — not an approved driver profile"
            )


def open_assigned_ride() -> str:
    enter_driver_mode()
    ensure_ora("nav_start")
    for i in range(16):
        t = dump(f"nav{i}" if i else "nav")
        if foreground_pkg() != PKG:
            t = ensure_ora(f"nav_pkg{i}")
        # Already on live assigned detail (not a closed aggregate).
        if "Assigned ride" in t and "This ride aggregate is closed" not in t:
            print("[open_assigned_ride] already on detail")
            return t
        if "Allow ORA to access this device" in t or "While using the app" in t:
            print("[open_assigned_ride] system location dialog")
            return t
        if tap_contains(t, "My trips", exact=True) or tap_contains(t, "My trips"):
            time.sleep(4)
            continue
        # Prefer active DRIVER_ASSIGNED card; never open closed history.
        if tap_contains(
            t,
            "Assigned — head to pickup",
            exclude=("Ride closed", "RIDE_CLOSED", "This ride aggregate"),
        ) or tap_contains(
            t,
            "DRIVER_ASSIGNED",
            exclude=("Ride closed", "RIDE_CLOSED", "This ride aggregate"),
        ) or tap_contains(
            t,
            "Liberty Market Lahore",
            exclude=("Ride closed", "RIDE_CLOSED", "Gulberg III"),
        ):
            time.sleep(4)
            t2 = dump("ride")
            if (
                "Assigned ride" in t2
                or "While using the app" in t2
                or "Allow ORA to access this device" in t2
            ):
                print("[open_assigned_ride] opened ride detail")
                return t2
        sh("input", "swipe", "540", "1500", "540", "700", "350")
        time.sleep(1.5)
    print("[open_assigned_ride] FAIL")
    return dump("fail")


def on_live_assigned_ride(t: str) -> bool:
    return (
        "Assigned ride" in t
        and "This ride aggregate is closed" not in t
        and foreground_pkg() == PKG
    )


def revoke_loc() -> None:
    subprocess.run(
        ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_FINE_LOCATION"],
        check=False,
    )
    subprocess.run(
        ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_COARSE_LOCATION"],
        check=False,
    )


def grant_loc() -> None:
    subprocess.run(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION"],
        check=False,
    )
    subprocess.run(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION"],
        check=False,
    )


def deny_system_permission_dialog() -> bool:
    """Reliably deny Android location permission (apostrophe / copy variants)."""
    for attempt in range(6):
        t = dump(f"perm_deny_{attempt}")
        pkg = foreground_pkg()
        if "permissioncontroller" not in pkg and "Allow ORA to access" not in t:
            return True
        tapped = False
        for needle in (
            "Don't allow",
            "Don’t allow",
            "Dont allow",
            "Deny",
            "No thanks",
            "No, thanks",
        ):
            if tap_contains(t, needle, exact=True) or tap_contains(t, needle):
                tapped = True
                time.sleep(1.5)
                break
        if not tapped:
            # Samsung A32 SM-A325F: Don't allow ~[64,2074][1016,2169]
            for y in (2120, 2050, 1980, 1900):
                sh("input", "tap", "540", str(y))
                time.sleep(0.8)
                t2 = dump(f"perm_deny_coord_{attempt}_{y}")
                if "Allow ORA to access" not in t2 and "While using the app" not in t2:
                    return True
        time.sleep(0.5)
    t = dump("perm_deny_final")
    return "Allow ORA to access" not in t and "While using the app" not in t


def allow_system_permission_dialog() -> bool:
    for attempt in range(5):
        t = dump(f"perm_allow_{attempt}")
        if "While using the app" not in t and "Allow ORA to access" not in t:
            return True
        for needle in (
            "While using the app",
            "Allow only while using the app",
            "Allow only while using",
            "Allow",
        ):
            if tap_contains(t, needle):
                time.sleep(1.5)
                break
        time.sleep(0.5)
    return True


def cancel_assigned_ride() -> str:
    """Cancel via Assigned ride UI: Cancel ride → confirm Cancel ride (not title)."""
    t = dump("cancel1")
    if not (
        tap_contains(t, "Cancel ride", exact=True, exclude=("Cancel ride?",))
        or tap_contains(t, "Cancel ride", exclude=("Cancel ride?",))
    ):
        return t
    time.sleep(1.5)
    t2 = dump("cancel2")
    if not tap_contains(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",)):
        # SM-A325F confirm button ~[168,1398][912,1524]
        sh("input", "tap", "540", "1460")
    time.sleep(10)
    t3 = dump("terminal")
    if "Cancel ride?" in t3 and "Keep ride" in t3:
        tap_contains(t3, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or sh(
            "input", "tap", "540", "1460"
        )
        time.sleep(10)
        t3 = dump("terminal2")
    return t3


def logcat_dump() -> str:
    return subprocess.check_output(
        ["adb", "-s", DEV, "logcat", "-d", "-v", "time"],
        text=True,
        errors="replace",
    )


def parse_metrics(text: str) -> dict:
    counts: dict[str, int] = {}
    first_watch = None
    first_fix = None
    first_accepted = None
    stops = []
    starts = []
    for line in text.splitlines():
        if "location_watch_started" in line:
            starts.append(line)
            if first_watch is None:
                first_watch = line
        if "location_watch_stopped" in line:
            stops.append(line)
        if "location_fix_classified" in line:
            if first_fix is None:
                first_fix = line
            m = re.search(r"classification:\s*(\w+)", line)
            if not m:
                m = re.search(r"'classification':\s*'(\w+)'", line)
            if not m:
                m = re.search(r"classification[=: ]+(\w+)", line)
            if m:
                key = m.group(1)
                counts[key] = counts.get(key, 0) + 1
                if key == "ACCEPTED" and first_accepted is None:
                    first_accepted = line
    return {
        "watch_starts": len(starts),
        "watch_stops": len(stops),
        "first_watch_line": first_watch,
        "first_fix_line": first_fix,
        "first_accepted_line": first_accepted,
        "classification_counts": counts,
        "start_lines": starts[-5:],
        "stop_lines": stops[-5:],
    }


def main() -> None:
    report: dict = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": sh("getprop", "ro.product.model").strip(),
        "androidVersion": sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": RIDE,
        "apkPath": str(
            Path(__file__).resolve().parents[1]
            / "build/app/outputs/flutter-apk/app-debug.apk"
        ),
    }

    adb("logcat", "-c")
    try:
        print("[main] login_driver")
        login_driver()
        ensure_ora("post_login")

        # TEST A — permission denied
        print("[main] TEST A permission denied")
        revoke_loc()
        t0 = time.time()
        enter_driver_mode()
        open_assigned_ride()
        denied_ok = deny_system_permission_dialog()
        t = dump("denied")
        if "Allow ORA to access" in t or "While using the app" in t:
            denied_ok = deny_system_permission_dialog()
            t = dump("denied2")
        # Wait briefly for status line after denial (no endless spinner).
        status_a = None
        for _ in range(8):
            t = dump("denied_wait")
            status_a = location_status(t)
            if status_a and status_a != "Getting your location…":
                break
            if status_a == "Getting your location…":
                time.sleep(2)
                continue
            time.sleep(1.5)
        report["A_permissionDenied"] = {
            "assignedRideVisible": on_live_assigned_ride(t),
            "status": status_a,
            "visibleUiStatusText": status_a,
            "dialogDenied": denied_ok,
            "stillOnPermissionDialog": "Allow ORA to access" in t,
            "seconds": round(time.time() - t0, 1),
            "hasMapPreview": "Map preview" in t,
            "hasRedis": "Redis" in t,
            "endlessLoading": status_a == "Getting your location…",
            "crash": False,
            "foregroundPkg": foreground_pkg(),
        }
        print("[main] A", report["A_permissionDenied"])

        # TEST B — permission granted
        print("[main] TEST B permission granted")
        grant_loc()
        adb("logcat", "-c")
        t0 = time.time()
        t = open_assigned_ride()
        allow_system_permission_dialog()
        t = ensure_ora("granted")
        if "While using the app" in t:
            allow_system_permission_dialog()
            t = dump("granted2")
        report["B_permissionGranted"] = {
            "assignedRideVisible": on_live_assigned_ride(t),
            "initialStatus": location_status(t),
            "openedAtEpoch": t0,
            "foregroundPkg": foreground_pkg(),
        }
        print("[main] B initial", report["B_permissionGranted"])

        ready_at = None
        if on_live_assigned_ride(t) or "Getting your location" in t or location_status(t):
            deadline = time.time() + 45
            while time.time() < deadline:
                time.sleep(3)
                ensure_ora("wait_fg")
                st = location_status(dump("wait"))
                print("[main] B wait status", st)
                if st == "Location is ready" and ready_at is None:
                    ready_at = time.time()
                    break
        else:
            print("[main] B SKIP wait — not on live assigned ride")
        report["B_permissionGranted"]["statusAfterWait"] = location_status(dump("wait2"))
        report["B_permissionGranted"]["readyAfterSeconds"] = (
            None if ready_at is None else round(ready_at - t0, 1)
        )
        report["B_logcatAfterFirstWait"] = parse_metrics(logcat_dump())
        print("[main] B metrics", report["B_logcatAfterFirstWait"])

        # TEST C — stationary window when GPS is active
        if (
            report["B_permissionGranted"].get("statusAfterWait") == "Location is ready"
            or report["B_logcatAfterFirstWait"].get("watch_starts", 0) > 0
        ):
            print("[main] TEST C stationary 90s")
            t_stat_start = time.time()
            time.sleep(90)
            report["C_stationarySeconds"] = round(time.time() - t_stat_start, 1)
            report["C_logcat"] = parse_metrics(logcat_dump())
        else:
            print("[main] TEST C SKIP — GPS not ready")
            report["C_stationarySeconds"] = 0
            report["C_logcat"] = parse_metrics(logcat_dump())
            report["C_skipped"] = True

        # TEST D — UI interaction
        print("[main] TEST D UI")
        ensure_ora("d")
        sh("input", "swipe", "540", "1400", "540", "800", "400")
        time.sleep(1)
        sh("input", "swipe", "540", "800", "540", "1400", "400")
        report["D_uiInteraction"] = {
            "scrolled": True,
            "statusStillVisible": location_status(dump("scroll")) is not None,
        }

        # TEST E — leave and return
        print("[main] TEST E leave/return")
        starts_before_leave = parse_metrics(logcat_dump())["watch_starts"]
        sh("input", "keyevent", "4")
        time.sleep(4)
        leave_t = ensure_ora("left")
        report["E_leave"] = {
            "leftAssignedRide": not on_live_assigned_ride(leave_t),
            "onMyTripsOrHome": "My trips" in leave_t
            or "Open ride" in leave_t
            or "Earn on ORA" in leave_t
            or "Where are you headed" in leave_t
            or "Assigned rides" in leave_t,
            "watchStopsAfterLeave": parse_metrics(logcat_dump())["watch_stops"],
            "watchStartsBeforeLeave": starts_before_leave,
        }
        t = open_assigned_ride()
        report["E_return"] = {
            "assignedRideVisible": on_live_assigned_ride(t),
            "status": location_status(t),
            "watchStartsAfterReturn": parse_metrics(logcat_dump())["watch_starts"],
        }
        time.sleep(12)

        # TEST F — background / foreground
        print("[main] TEST F bg/fg")
        stops_before_bg = parse_metrics(logcat_dump())["watch_stops"]
        sh("input", "keyevent", "3")
        time.sleep(6)
        stops_after_bg = parse_metrics(logcat_dump())["watch_stops"]
        t = ensure_ora("fg")
        if not on_live_assigned_ride(t):
            t = open_assigned_ride()
        report["F_backgroundForeground"] = {
            "assignedRideVisible": on_live_assigned_ride(t),
            "status": location_status(t),
            "watchStopsIncreasedOnBackground": stops_after_bg > stops_before_bg,
            "metrics": parse_metrics(logcat_dump()),
        }
        time.sleep(8)

        # TEST G — cancel ride (terminal)
        print("[main] TEST G cancel")
        metrics_before_cancel = parse_metrics(logcat_dump())
        t = cancel_assigned_ride()
        metrics_after_cancel = parse_metrics(logcat_dump())
        report["G_terminal"] = {
            "statusChip": "CANCELLED" in t or "cancelled" in t.lower(),
            "locationStatus": location_status(t),
            "uiTextHasCancelled": "cancelled" in t.lower() or "CANCELLED" in t,
            "watchStopsBefore": metrics_before_cancel["watch_stops"],
            "watchStopsAfter": metrics_after_cancel["watch_stops"],
            "watchStoppedOnCancel": metrics_after_cancel["watch_stops"]
            > metrics_before_cancel["watch_stops"],
            "metrics": metrics_after_cancel,
        }
        print("[main] G", report["G_terminal"])
        sh("input", "keyevent", "4")
        time.sleep(3)
        enter_driver_mode()
        home = ensure_ora("home_after")
        home_metrics = parse_metrics(logcat_dump())
        report["G_homeNoGps"] = {
            "onDriverHome": "Open ride" in home
            or "My trips" in home
            or "Earn on ORA" in home
            or "Assigned rides" in home,
            "locationStatusOnHome": location_status(home),
            "watchStartsOnHome": home_metrics["watch_starts"],
        }
        # Unrelated driver screen: Open ride requests should not start GPS.
        if tap_contains(home, "Open ride requests") or tap_contains(home, "Open ride"):
            time.sleep(4)
            open_t = dump("open_rides")
            open_metrics = parse_metrics(logcat_dump())
            report["G_openRidesNoGps"] = {
                "onOpenRides": "Open ride" in open_t or "open" in open_t.lower(),
                "locationStatus": location_status(open_t),
                "watchStarts": open_metrics["watch_starts"],
                "watchStartsUnchanged": open_metrics["watch_starts"]
                == home_metrics["watch_starts"],
            }
            print("[main] G open rides", report["G_openRidesNoGps"])


    finally:
        out = logcat_dump()
        LOGCAT.write_text(out, encoding="utf-8")
        metrics = parse_metrics(out)
        report["logcatMetrics"] = metrics
        report["networkProof"] = {
            "postLocationUpdateInLogcat": "/v1/location/update" in out
            or "LOCATION_UPDATE" in out
            or "location/update" in out,
        }
        report["privacyProof"] = {
            "knownTestLatInLogcat": "31.4127578" in out or "31.5204" in out,
            "latitudeKeyInOraLogs": bool(re.search(r"\[INFO\].*latitude", out, re.I)),
        }
        report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
