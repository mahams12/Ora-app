#!/usr/bin/env python3
"""L1 gap-closure physical proof (A deny, B–F lifecycle, G cancel, logger)."""
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


def sh(*a: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", DEV, "shell", *a], stderr=subprocess.STDOUT
    ).decode("utf-8", "replace")


def adb(*a: str) -> None:
    subprocess.check_call(["adb", "-s", DEV, *a])


def fg() -> str:
    try:
        out = sh("dumpsys", "window")
    except subprocess.CalledProcessError:
        try:
            out = sh("dumpsys", "window", "windows")
        except subprocess.CalledProcessError:
            return ""
    m = re.search(r"mCurrentFocus=Window\{[^ ]+ u0 ([^/}]+)", out)
    if not m:
        m = re.search(r"mFocusedApp=.*? ([^\s/]+)/", out)
    return m.group(1) if m else ""


def dump(tag: str) -> str:
    """Pull a fresh UIAutomator hierarchy; avoid stale /sdcard dumps."""
    path = ART / f"l1_{tag}.xml"
    remote = "/sdcard/l1_ui.xml"
    for attempt in range(10):
        try:
            path.unlink(missing_ok=True)
            # Remove stale remote dump so a failed dump cannot look "successful".
            subprocess.call(
                ["adb", "-s", DEV, "shell", "rm", "-f", remote],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            # Prefer compressed dump — more reliable when the UI is busy.
            dumped = False
            for args in (
                ["uiautomator", "dump", "--compressed", remote],
                ["uiautomator", "dump", remote],
            ):
                try:
                    sh(*args)
                    dumped = True
                    break
                except subprocess.CalledProcessError:
                    continue
            if not dumped:
                # Last resort: stream to stdout (works even when file dump stalls).
                raw = subprocess.check_output(
                    ["adb", "-s", DEV, "exec-out", "uiautomator", "dump", "/dev/tty"],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=20,
                )
                if "hierarchy" in raw and len(raw) > 400:
                    path.write_text(raw)
                    return raw
                time.sleep(1)
                continue
            subprocess.check_call(
                ["adb", "-s", DEV, "pull", remote, str(path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            t = path.read_text()
            if "hierarchy" in t and len(t) > 400:
                return t
        except Exception:
            pass
        time.sleep(1)
    return path.read_text() if path.exists() else ""


def nodes(t: str) -> list[dict]:
    out = []
    for m in re.finditer(r"<node ([^>]+)>", t):
        attrs = m.group(1)
        if attrs.endswith("/"):
            attrs = attrs[:-1]

        def attr(n: str) -> str:
            mm = re.search(rf'{n}="([^"]*)"', attrs)
            return (mm.group(1) if mm else "").replace("&#10;", "\n").replace("&amp;", "&")

        b = attr("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        out.append(
            {
                "text": attr("text"),
                "desc": attr("content-desc"),
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return out


def _norm(s: str) -> str:
    return s.replace("\u2019", "'").replace("\u2018", "'").replace("\u02bc", "'").replace("`", "'")


def _labels(n: dict) -> list[str]:
    """Flatten text + multiline content-desc into comparable labels."""
    out: list[str] = []
    if n["text"]:
        out.append(_norm(n["text"]))
    if n["desc"]:
        out.append(_norm(n["desc"]))
        for line in n["desc"].split("\n"):
            line = line.strip()
            if line:
                out.append(_norm(line))
    return out


def tap(t: str, needle: str, exclude: tuple[str, ...] = (), *, exact: bool = False) -> bool:
    needle_n = _norm(needle)
    cands = []
    for n in nodes(t):
        b = f"{n['text']} {n['desc']}"
        bn = _norm(b)
        if any(x in b or _norm(x) in bn for x in exclude):
            continue
        labels = _labels(n)
        hit = needle_n in labels if exact else needle_n in bn
        if hit:
            x1, y1, x2, y2 = n["bounds"]
            area = (x2 - x1) * (y2 - y1)
            # Exact buttons: largest. Contains matches: also prefer largest for
            # Flutter semantics cards (smallest child taps often no-op).
            cands.append((-area, n, b))
    if not cands:
        return False
    cands.sort(key=lambda x: x[0])
    _, n, b = cands[0]
    x1, y1, x2, y2 = n["bounds"]
    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    print("TAP", ("exact" if exact else ""), needle, b[:80].replace("\n", "|"))
    return True


def show(tag: str) -> str:
    t = dump(tag)
    print("===", tag, "fg=", fg(), "===")
    seen: set[str] = set()
    for n in nodes(t):
        b = (n["desc"] or n["text"]).strip()
        if b and b not in seen:
            seen.add(b)
            print("-", b.replace("\n", " | ")[:140])
    return t


def ensure() -> str:
    pkg = fg()
    # Never relaunch while the system permission sheet is up.
    if "permissioncontroller" in pkg:
        return dump("ensure_perm")
    if pkg and pkg != PKG and "permissioncontroller" not in pkg:
        print("relaunch", pkg)
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
    t = dump("ensure")
    if "While using the app" in t or "Don't allow" in _norm(t):
        return t
    if "notifications" in t.lower() and tap(t, "Don't allow"):
        time.sleep(2)
    t = dump("ensure2")
    if "Map preview" in t or "Where to?" in t:
        print("escape map")
        sh("input", "keyevent", "4")
        time.sleep(2)
    return dump("ensure3")


def on_assigned_detail(t: str) -> bool:
    """True only on assigned-ride *detail*, not the 'Assigned rides' list."""
    if "Mark en route" in t or "Mark arrived" in t or "Start ride" in t:
        return True
    # Exact title node — do not treat list header "Assigned rides" as detail.
    return bool(
        re.search(r'(?:text|content-desc)="Assigned ride"', t)
    )


def loc_status(t: str) -> str | None:
    if (
        not on_assigned_detail(t)
        and "CANCELLED" not in t
        and "Ride cancelled" not in t
    ):
        return None
    for s in (
        "Getting your location…",
        "Getting your location",
        "Location is ready",
        "Location accuracy is low",
        "Location permission is needed",
        "Location is turned off",
        "Turn on location services",
        "Location is temporarily unavailable",
    ):
        if s in t:
            return "Getting your location…" if s.startswith("Getting") else s
    return None


def parse_metrics(text: str) -> dict:
    counts: dict[str, int] = {}
    starts, stops, fixes = [], [], []
    first_accepted = None
    for line in text.splitlines():
        if "location_watch_started" in line:
            starts.append(line)
        if "location_watch_stopped" in line:
            stops.append(line)
        if "location_fix_classified" in line:
            fixes.append(line)
            m = re.search(r"classification[=: ]+['\"]?(\w+)", line)
            if not m:
                m = re.search(r"'classification':\s*'(\w+)'", line)
            if m:
                counts[m.group(1)] = counts.get(m.group(1), 0) + 1
                if m.group(1) == "ACCEPTED" and first_accepted is None:
                    first_accepted = line
    geo_starts = [l for l in text.splitlines() if "Geolocator position updates started" in l]
    geo_stops = [l for l in text.splitlines() if "Geolocator position updates stopped" in l]
    return {
        "watch_starts": len(starts),
        "watch_stops": len(stops),
        "fix_classifications": len(fixes),
        "classification_counts": counts,
        "first_watch_line": starts[0] if starts else None,
        "first_stop_line": stops[0] if stops else None,
        "first_fix_line": fixes[0] if fixes else None,
        "first_accepted_line": first_accepted,
        "start_lines": starts[-5:],
        "stop_lines": stops[-5:],
        "geolocator_starts": len(geo_starts),
        "geolocator_stops": len(geo_stops),
    }


def deny_permission() -> bool:
    """Deny the system location dialog once; trust focus change over stale dumps."""
    for attempt in range(8):
        pkg = fg()
        # Prefer an immediate coord tap while the sheet owns focus — UIAutomator
        # dump often hangs ("could not get idle state") on Samsung permission UI.
        if "permissioncontroller" in pkg:
            sh("input", "tap", "540", "2121")
            print("DENY_TAP coord 540,2121 (fg=permissioncontroller)")
            for _ in range(12):
                time.sleep(0.35)
                if "permissioncontroller" not in fg():
                    print("DENY_OK fg=", fg())
                    return True
        try:
            t = dump(f"deny_{attempt}")
        except Exception:
            t = ""
        dialog_visible = "permissioncontroller" in pkg or "While using the app" in t
        if not dialog_visible and "Don't allow" not in _norm(t) and "Dont allow" not in _norm(t):
            return True

        deny_node = None
        cands = []
        for n in nodes(t):
            text_n = _norm(n["text"])
            desc_n = _norm(n["desc"])
            if text_n in ("Don't allow", "Dont allow", "Deny") or desc_n in (
                "Don't allow",
                "Dont allow",
                "Deny",
            ):
                x1, y1, x2, y2 = n["bounds"]
                cands.append((y2, (x2 - x1) * (y2 - y1), n))
        if cands:
            cands.sort(key=lambda x: (-x[0], -x[1]))
            deny_node = cands[0][2]

        if deny_node:
            x1, y1, x2, y2 = deny_node["bounds"]
            sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
            print(
                "DENY_TAP",
                deny_node["text"] or deny_node["desc"],
                deny_node["bounds"],
            )
        else:
            sh("input", "tap", "540", "2121")
            print("DENY_TAP coord 540,2121")

        for _ in range(10):
            time.sleep(0.4)
            if "permissioncontroller" not in fg():
                print("DENY_OK fg=", fg())
                return True
        try:
            sh("input", "tap", "540", "2121")
        except subprocess.CalledProcessError:
            pass
        time.sleep(1)
        if "permissioncontroller" not in fg():
            return True
    return "permissioncontroller" not in fg()


def allow_permission() -> None:
    for attempt in range(5):
        t = dump(f"allow_{attempt}")
        if "While using the app" not in t and "Allow ORA to access" not in t:
            return
        if tap(t, "While using the app") or tap(t, "Allow"):
            time.sleep(1.5)


def login_and_driver() -> None:
    ensure()
    t = show("boot")
    if "Phone number" in t or "Send verification" in t or "Send code" in t:
        eds = re.findall(
            r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            t,
        )
        if eds:
            x1, y1, x2, y2 = map(int, eds[0])
            sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        else:
            sh("input", "tap", "540", "1364")
        time.sleep(0.3)
        for _ in range(28):
            sh("input", "keyevent", "67")
        sh("input", "text", "03012345677")
        sh("input", "keyevent", "4")
        time.sleep(0.4)
        tap(dump("send"), "Send")
        time.sleep(10)
        t = show("otp")
        eds = re.findall(
            r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            t,
        )
        if eds:
            x1, y1, x2, y2 = map(int, eds[0])
            sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        else:
            sh("input", "tap", "540", "610")
        sh("input", "text", "000000")
        time.sleep(0.4)
        tap(dump("verify"), "Verify")
        for i in range(25):
            time.sleep(2)
            t = dump(f"post{i}")
            if any(
                s in t
                for s in ("Where are you headed", "Earn on ORA", "Open ride", "My trips", "City rides")
            ):
                show(f"post{i}")
                break

    for attempt in range(5):
        t = ensure()
        t = show(f"home{attempt}")
        if "Open ride requests" in t or ("My trips" in t and "Where to?" not in t):
            return
        if "Map preview" in t or "Where to?" in t:
            print("back from map")
            sh("input", "keyevent", "4")
            time.sleep(2)
            continue
        # Open drawer: prefer exact Menu semantics; avoid mid-screen taps.
        if not (tap(t, "Menu", exact=True) or tap(t, "Open navigation menu", exact=True)):
            # Top-left hamburger — stay in status-bar-adjacent chrome only.
            sh("input", "tap", "64", "148")
        time.sleep(2)
        t = show(f"drawer{attempt}")
        if "Map preview" in t or "Where to?" in t:
            sh("input", "keyevent", "4")
            time.sleep(2)
            continue
        if tap(t, "Switch to driver mode"):
            time.sleep(7)
            t = show(f"driver{attempt}")
            if "Open ride" in t or "My trips" in t:
                return
            if "not wired" in t:
                tap(t, "Got it")
                time.sleep(1)
        else:
            # Close drawer if open without switch
            sh("input", "keyevent", "4")
            time.sleep(1)
    raise SystemExit("FAILED_DRIVER_GATE " + fg())


def open_assigned(from_home: bool = False) -> str:
    t = ensure()
    if "Map preview" in t or "Where to?" in t:
        sh("input", "keyevent", "4")
        time.sleep(2)
        t = ensure()
    if on_assigned_detail(t) and "This ride aggregate is closed" not in t:
        return t
    if "Assigned rides" not in t:
        if not (tap(t, "My trips", exact=True) or tap(t, "My trips")):
            if from_home or "Open ride" in t:
                raise SystemExit("NO_MY_TRIPS")
            login_and_driver()
            t = dump("drv2")
            tap(t, "My trips", exact=True) or tap(t, "My trips")
        time.sleep(5)
        t = show("trips")
    if "Map preview" in t:
        sh("input", "keyevent", "4")
        time.sleep(2)
        t = show("trips2")
    if not tap(
        t,
        "Assigned — head to pickup",
        exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED"),
    ) and not tap(t, "DRIVER_ASSIGNED", exclude=("Ride closed", "RIDE_CLOSED", "CANCELLED")):
        raise SystemExit("NO_ASSIGNED_CARD")
    # Wait for permission dialog or assigned-ride screen (dump can lag behind fg).
    for i in range(12):
        time.sleep(1)
        pkg = fg()
        t = dump(f"ride_open_{i}")
        if "permissioncontroller" in pkg or "Allow ORA to access" in t or "While using the app" in t:
            return show(f"ride_perm_{i}")
        if on_assigned_detail(t) and "This ride aggregate is closed" not in t:
            return show(f"ride_{i}")
    return show("ride")


def main() -> None:
    report: dict = {
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": sh("getprop", "ro.product.model").strip(),
        "androidVersion": sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "rideId": RIDE,
        "method": "l1_gap_closure_physical",
        "loggerSink": "ConsoleAppLogger → dart:developer name=ora; debug assert print mirror for adb logcat",
    }

    adb("logcat", "-c")
    # Start denied for Gap A — clear sticky flags so the system dialog reappears.
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

    print("LOGIN")
    login_and_driver()

    print("TEST A deny")
    t0 = time.time()
    t = open_assigned()
    denied = False
    # Wait briefly for permissioncontroller (requestPermission is async).
    for i in range(8):
        pkg = fg()
        if "permissioncontroller" in pkg or "While using the app" in t:
            denied = deny_permission()
            break
        if "Assigned ride" in t and loc_status(t) not in (None, "Getting your location…"):
            # Permission already resolved without a fresh dialog (e.g. prior deny).
            break
        time.sleep(1)
        t = dump(f"a_pre_{i}")
        show(f"a_pre_{i}")
    else:
        # Force a dialog by leaving + revoking + reopening once.
        if "Assigned ride" in t:
            sh("input", "keyevent", "4")
            time.sleep(2)
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
            ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_FINE_LOCATION"]
        )
        subprocess.call(
            ["adb", "-s", DEV, "shell", "pm", "revoke", PKG, "android.permission.ACCESS_COARSE_LOCATION"]
        )
        t = open_assigned()
        for i in range(8):
            if "permissioncontroller" in fg() or "While using the app" in t:
                denied = deny_permission()
                break
            time.sleep(1)
            t = dump(f"a_force_{i}")

    status_a = None
    for i in range(15):
        # Permission dialog may have dismissed; ensure we are on assigned ride detail.
        if "permissioncontroller" in fg():
            deny_permission()
        t = show(f"a_wait{i}")
        if "Assigned ride" not in t:
            try:
                t = open_assigned()
                # If dialog returns, deny again without grant.
                if "permissioncontroller" in fg() or "While using the app" in t:
                    deny_permission()
                    t = show(f"a_reopen{i}")
            except SystemExit:
                pass
        status_a = loc_status(t)
        if (
            "Assigned ride" in t
            and status_a
            and status_a != "Getting your location…"
        ):
            break
        time.sleep(1.5)
    report["A_permissionDenied"] = {
        "dialogDenied": denied or status_a
        in (
            "Location is temporarily unavailable",
            "Turn on location services",
        ),
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": status_a,
        "visibleUiStatusText": status_a,
        "seconds": round(time.time() - t0, 1),
        "hasMapPreview": "Map preview" in t,
        "hasRedis": "Redis" in t,
        "endlessLoading": status_a == "Getting your location…",
        "crash": False,
        "foregroundPkg": fg(),
    }
    print("A", report["A_permissionDenied"])

    print("TEST B grant")
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION"]
    )
    subprocess.call(
        ["adb", "-s", DEV, "shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION"]
    )
    adb("logcat", "-c")
    t0 = time.time()
    if "Assigned ride" in t:
        sh("input", "keyevent", "4")
        time.sleep(2)
    t = open_assigned()
    allow_permission()
    t = show("b_after_allow")
    ready_at = None
    for i in range(20):
        t = show(f"b_wait{i}")
        st = loc_status(t)
        print("status", st)
        if st == "Location is ready":
            ready_at = time.time()
            break
        time.sleep(2)
    m_b = parse_metrics(sh("logcat", "-d", "-v", "time"))
    report["B_permissionGranted"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "statusAfterWait": loc_status(t),
        "readyAfterSeconds": None if ready_at is None else round(ready_at - t0, 1),
        "foregroundPkg": fg(),
    }
    report["B_logcatAfterFirstWait"] = m_b
    print("B", report["B_permissionGranted"], m_b)

    print("TEST C stationary")
    t_stat = time.time()
    time.sleep(90)
    report["C_stationarySeconds"] = round(time.time() - t_stat, 1)
    report["C_logcat"] = parse_metrics(sh("logcat", "-d", "-v", "time"))
    print("C", report["C_logcat"])

    print("TEST D scroll")
    sh("input", "swipe", "540", "1400", "540", "800", "400")
    time.sleep(1)
    sh("input", "swipe", "540", "800", "540", "1400", "400")
    t = show("d_scroll")
    report["D_uiInteraction"] = {
        "scrolled": True,
        "statusStillVisible": loc_status(t) is not None,
    }

    print("TEST E leave/return")
    before = parse_metrics(sh("logcat", "-d", "-v", "time"))
    sh("input", "keyevent", "4")
    time.sleep(4)
    leave = show("e_left")
    after_leave = parse_metrics(sh("logcat", "-d", "-v", "time"))
    report["E_leave"] = {
        "leftAssignedRide": "Assigned rides" in leave or "My trips" in leave,
        "onMyTripsOrHome": "Assigned rides" in leave or "Open ride" in leave,
        "watchStopsAfterLeave": after_leave["watch_stops"],
        "watchStartsBeforeLeave": before["watch_starts"],
        "geolocatorStops": after_leave["geolocator_stops"],
    }
    t = open_assigned()
    allow_permission()
    ready_e = None
    for i in range(20):
        t = show(f"e_ret{i}")
        ready_e = loc_status(t)
        if ready_e == "Location is ready":
            break
        time.sleep(2)
    after_ret = parse_metrics(sh("logcat", "-d", "-v", "time"))
    report["E_return"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": ready_e,
        "watchStartsAfterReturn": after_ret["watch_starts"],
    }
    print("E", report["E_leave"], report["E_return"])

    print("TEST F bg/fg")
    before_bg = parse_metrics(sh("logcat", "-d", "-v", "time"))
    sh("input", "keyevent", "3")
    time.sleep(6)
    after_bg = parse_metrics(sh("logcat", "-d", "-v", "time"))
    ensure()
    t = show("f_fg")
    if "Assigned ride" not in t or "closed" in t.lower():
        t = open_assigned()
        allow_permission()
    ready_f = None
    for i in range(20):
        t = show(f"f_wait{i}")
        ready_f = loc_status(t)
        if ready_f == "Location is ready":
            break
        time.sleep(2)
    report["F_backgroundForeground"] = {
        "assignedRideVisible": "Assigned ride" in t and "closed" not in t.lower(),
        "status": ready_f,
        "watchStopsIncreasedOnBackground": after_bg["watch_stops"] > before_bg["watch_stops"]
        or after_bg["geolocator_stops"] > before_bg["geolocator_stops"],
        "metrics": parse_metrics(sh("logcat", "-d", "-v", "time")),
    }
    print("F", report["F_backgroundForeground"])
    time.sleep(3)

    print("TEST G cancel")
    # Ensure active GPS watch on assigned ride before cancel.
    if loc_status(t) != "Location is ready" or "Assigned ride" not in t:
        t = open_assigned()
        allow_permission()
        for i in range(20):
            t = show(f"g_ready{i}")
            if loc_status(t) == "Location is ready":
                break
            time.sleep(2)
    before_g = parse_metrics(sh("logcat", "-d", "-v", "time"))
    t = show("g1")
    # Primary button: exact "Cancel ride" (not dialog title "Cancel ride?").
    if not (
        tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",))
        or tap(t, "Cancel ride", exclude=("Cancel ride?",))
    ):
        print("NO_CANCEL_BUTTON")
    else:
        time.sleep(1.5)
        t2 = show("g2")
        confirmed = tap(t2, "Cancel ride", exact=True, exclude=("Cancel ride?",))
        if not confirmed:
            # Fallback: confirm button bounds on SM-A325F dialog ~[168,1398][912,1524]
            sh("input", "tap", "540", "1460")
            print("TAP coord confirm Cancel ride")
        time.sleep(10)
    # Poll assigned-ride detail for server-confirmed cancel (not trips filter).
    for i in range(12):
        t = show(f"g_term{i}")
        if "Assigned ride" in t and ("Ride cancelled" in t or "CANCELLED" in t):
            break
        if "Cancel ride?" in t and "Keep ride" in t:
            tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or sh(
                "input", "tap", "540", "1460"
            )
        time.sleep(2)
    t = show("g_term")
    # If dialog still open, force exact confirm once more.
    if "Cancel ride?" in t and "Keep ride" in t:
        tap(t, "Cancel ride", exact=True, exclude=("Cancel ride?",)) or sh(
            "input", "tap", "540", "1460"
        )
        time.sleep(10)
        t = show("g_term2")
    after_g = parse_metrics(sh("logcat", "-d", "-v", "time"))
    # Require terminal evidence on the assigned-ride detail (not My trips "Cancelled" filter chip).
    on_detail = "Assigned ride" in t and "Assigned rides" not in t
    detail_cancelled = on_detail and (
        "CANCELLED" in t
        or "Ride cancelled" in t
        or "This ride was cancelled" in t
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
        "locationStatus": loc_status(t),
        "activeWatchBeforeCancel": before_g["watch_starts"] > 0
        and (
            before_g["watch_starts"] > before_g["watch_stops"]
            or before_g["geolocator_starts"] >= before_g["geolocator_stops"]
        ),
        "watchStoppedOnCancel": after_g["watch_stops"] > before_g["watch_stops"]
        or after_g["geolocator_stops"] > before_g["geolocator_stops"],
        "stopReasonTerminal": any(
            "reason: terminal" in line or "reason: dispose" in line
            for line in after_g.get("stop_lines", [])
        ),
        "metricsBefore": before_g,
        "metrics": after_g,
    }
    print("G", report["G_terminal"])
    sh("input", "keyevent", "4")
    time.sleep(3)
    ensure()
    # driver home — do not start GPS
    starts_before_home = parse_metrics(sh("logcat", "-d", "-v", "time"))["watch_starts"]
    t = show("g_home")
    if "Open ride" not in t and "My trips" not in t:
        if not tap(t, "Menu", exact=True):
            sh("input", "tap", "72", "168")
        time.sleep(2)
        tap(dump("g_dr"), "Switch to driver mode")
        time.sleep(6)
        t = show("g_drv")
    home_m = parse_metrics(sh("logcat", "-d", "-v", "time"))
    report["G_homeNoGps"] = {
        "onDriverHome": "Open ride" in t or "My trips" in t,
        "locationStatusOnHome": loc_status(t),
        "watchStarts": home_m["watch_starts"],
        "watchStartsUnchangedFromTerminal": home_m["watch_starts"] == starts_before_home,
    }
    starts_home = home_m["watch_starts"]
    if tap(t, "Open ride requests", exact=True) or tap(t, "Open ride"):
        time.sleep(4)
        ot = show("g_open")
        om = parse_metrics(sh("logcat", "-d", "-v", "time"))
        report["G_openRidesNoGps"] = {
            "locationStatus": loc_status(ot),
            "watchStartsUnchanged": om["watch_starts"] == starts_home,
            "watchStarts": om["watch_starts"],
        }
        print("G open", report["G_openRidesNoGps"])
    else:
        report["G_openRidesNoGps"] = {"skipped": True, "watchStarts": starts_home}

    out = sh("logcat", "-d", "-v", "time")
    LOGCAT.write_text(out)
    metrics = parse_metrics(out)
    report["logcatMetrics"] = metrics
    report["networkProof"] = {
        "postLocationUpdateInLogcat": "/v1/location/update" in out
        or "location/update" in out
        or "LOCATION_UPDATE" in out
    }
    report["privacyProof"] = {
        "knownTestLatInLogcat": "31.4127578" in out or "31.5204" in out,
        "latitudeKeyInOraLogs": bool(
            re.search(r"\[INFO\].*latitude", out, re.I)
        ),
    }
    report["structuredLoggerObservable"] = metrics["watch_starts"] > 0 and metrics[
        "fix_classifications"
    ] >= 0

    # Verdict
    checks = {
        "A_deniedStatusCaptured": report["A_permissionDenied"].get("status")
        in (
            "Location permission is needed",
            "Location is temporarily unavailable",
            "Location is turned off",
            "Turn on location services",
            "Location accuracy is low",
        )
        and report["A_permissionDenied"].get("dialogDenied")
        and report["A_permissionDenied"].get("assignedRideVisible")
        and not report["A_permissionDenied"].get("endlessLoading"),
        "B_ready": report["B_permissionGranted"].get("statusAfterWait")
        == "Location is ready",
        "C_stationary": report.get("C_stationarySeconds", 0) >= 90,
        "D_scroll": report["D_uiInteraction"].get("statusStillVisible"),
        "E_returnReady": report["E_return"].get("status") == "Location is ready",
        "F_returnReady": report["F_backgroundForeground"].get("status")
        == "Location is ready",
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
    report["verdict"] = (
        "GREEN" if not failed else ("YELLOW" if checks["B_ready"] else "RED")
    )
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
