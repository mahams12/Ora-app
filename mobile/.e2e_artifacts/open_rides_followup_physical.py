#!/usr/bin/env python3
"""Open Rides redesign follow-up — My Rides metrics, Open Rides capture, jank, Accept."""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import map2a_physical as M

DEV, PKG, ART = M.DEV, M.PKG, M.ART
PREFIX = "open_rides_followup"


def log(*a):
    print(*a, flush=True)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def screencap(tag: str) -> Path:
    name = f"{PREFIX}_{tag}.png"
    remote = f"/sdcard/{name}"
    path = ART / name
    M.sh("screencap", "-p", remote)
    M.adb("pull", remote, str(path))
    return path


def dump(tag: str) -> str:
    xml = M.dump(f"{PREFIX}_{tag}")
    (ART / f"{PREFIX}_{tag}.xml").write_text(xml)
    return xml


def texts(xml: str) -> str:
    return M.unescape(xml)


def has(xml: str, *needles: str) -> bool:
    u = texts(xml)
    return all(n in u for n in needles)


def gfxinfo_reset() -> None:
    M.sh("dumpsys", "gfxinfo", PKG, "reset")


def gfxinfo_dump(tag: str) -> dict:
    raw = subprocess.check_output(
        ["adb", "-s", DEV, "shell", "dumpsys", "gfxinfo", PKG],
        text=True,
        stderr=subprocess.STDOUT,
    )
    (ART / f"{PREFIX}_gfxinfo_{tag}.txt").write_text(raw)
    out: dict = {"tag": tag, "rawPath": f".e2e_artifacts/{PREFIX}_gfxinfo_{tag}.txt"}
    # Parse summary lines when present (Profile GPU rendering / FrameStats).
    m = re.search(r"Total frames rendered:\s*(\d+)", raw)
    if m:
        out["totalFramesRendered"] = int(m.group(1))
    m = re.search(r"Janky frames:\s*(\d+)\s*\(([\d.]+)%\)", raw)
    if m:
        out["jankyFrames"] = int(m.group(1))
        out["jankyPercent"] = float(m.group(2))
    m = re.search(r"50th percentile:\s*(\d+)ms", raw)
    if m:
        out["p50Ms"] = int(m.group(1))
    m = re.search(r"90th percentile:\s*(\d+)ms", raw)
    if m:
        out["p90Ms"] = int(m.group(1))
    m = re.search(r"95th percentile:\s*(\d+)ms", raw)
    if m:
        out["p95Ms"] = int(m.group(1))
    m = re.search(r"99th percentile:\s*(\d+)ms", raw)
    if m:
        out["p99Ms"] = int(m.group(1))
    # Legacy Histogram / Profile data presence
    out["hasProfileData"] = "Profile data in ms" in raw or "HISTOGRAM" in raw.upper()
    return out


def swipe_scroll(times: int = 6) -> None:
    for _ in range(times):
        M.sh("input", "swipe", "540", "1700", "540", "700", "350")
        time.sleep(0.35)


def open_my_rides(xml: str) -> str:
    if has(xml, "My rides"):
        M.tap_contains(xml, "My rides")
        time.sleep(2.0)
        return dump("my_rides")
    # Drawer path
    if M.tap_contains(xml, "Menu", exact=True) or M.tap_contains(xml, "Open navigation"):
        time.sleep(1.0)
        xml = dump("drawer")
    if M.tap_contains(xml, "My rides") or M.tap_contains(xml, "My trips"):
        time.sleep(2.0)
        return dump("my_rides")
    # Bottom tab heuristic
    M.sh("input", "tap", "540", "2200")
    time.sleep(2.0)
    return dump("my_rides_tab")


def ensure_driver_open_rides(xml: str) -> str:
    if has(xml, "Open rides") or has(xml, "Open ride"):
        if not has(xml, "Accept") and not has(xml, "Decline"):
            # May already be on list
            pass
        if M.tap_contains(xml, "Open rides") or M.tap_contains(xml, "Open ride requests"):
            time.sleep(2.0)
            return dump("open_rides")
        return dump("open_rides")

    # Passenger → Earn on ORA → driver shell
    if M.tap_contains(xml, "Earn on ORA") or M.tap_contains(xml, "Earn"):
        time.sleep(2.5)
        xml = dump("earn")
    if M.tap_contains(xml, "Open rides") or M.tap_contains(xml, "Open ride"):
        time.sleep(2.0)
        return dump("open_rides")
    # Bottom Open tab
    M.sh("input", "tap", "216", "2200")
    time.sleep(2.0)
    return dump("open_rides")


def main() -> int:
    t0 = time.time()
    M.sh("logcat", "-c")
    results: dict = {
        "startedAt": now_iso(),
        "device": DEV,
        "package": PKG,
        "checks": {},
        "shots": {},
        "gfx": {},
        "acceptLifecycle": {},
    }

    M.adb("shell", "am", "force-stop", PKG)
    time.sleep(0.4)
    M.adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    time.sleep(4.0)
    xml = dump("boot")
    results["shots"]["boot"] = str(screencap("boot").name)

    if has(xml, "Send OTP") or has(xml, "Phone number") or has(xml, "Verify"):
        log("auth — force passenger login first for My Rides")
        xml = M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
        dump("after_login_pax")
        results["checks"]["login"] = "PASS"
    else:
        results["checks"]["login"] = "ALREADY"

    # --- My Rides metrics visibility ---
    xml = open_my_rides(xml)
    results["shots"]["my_rides"] = str(screencap("my_rides").name)
    u = texts(xml)
    results["checks"]["my_rides_screen"] = "PASS" if "My rides" in u else "FAIL"
    # Distance value: look for "km" near Distance caption; em dash for duration.
    has_km = bool(re.search(r"\d+(\.\d+)?\s*km", u, re.I)) or "km" in u
    has_emdash = "—" in u or "\u2014" in u or "–" in u
    has_cancelled = "Cancelled" in u
    has_distance_label = "Distance" in u
    has_duration_label = "Duration" in u
    results["checks"]["my_rides_cancelled_visible"] = "PASS" if has_cancelled else "PARTIAL"
    results["checks"]["my_rides_distance_value"] = "PASS" if has_km else "FAIL"
    results["checks"]["my_rides_duration_placeholder"] = "PASS" if has_emdash else "PARTIAL"
    results["checks"]["my_rides_distance_label"] = "PASS" if has_distance_label else "FAIL"
    results["checks"]["my_rides_duration_label"] = "PASS" if has_duration_label else "FAIL"
    results["myRidesTextSample"] = {
        "hasKm": has_km,
        "hasEmdash": has_emdash,
        "hasCancelled": has_cancelled,
        "kmMatches": re.findall(r"\d+(?:\.\d+)?\s*km", u, re.I)[:8],
    }

    # --- Switch to driver Open Rides ---
    # Re-login as driver for clean Open Rides + Accept path
    xml = M.force_login(M.DRIVER_PHONE_UI, M.DRIVER_OTP, want_passenger=False)
    dump("driver_home")
    xml = ensure_driver_open_rides(xml)
    results["shots"]["open_rides"] = str(screencap("open_rides").name)
    results["checks"]["open_rides_screen"] = (
        "PASS" if ("Open rides" in texts(xml) or "Open ride" in texts(xml)) else "FAIL"
    )

    # Frame jank sample during scroll
    gfxinfo_reset()
    scroll_start = time.time()
    swipe_scroll(8)
    scroll_ms = int((time.time() - scroll_start) * 1000)
    results["gfx"]["scroll"] = gfxinfo_dump("scroll")
    results["gfx"]["scroll"]["sampleDurationMs"] = scroll_ms
    results["gfx"]["method"] = "adb shell dumpsys gfxinfo com.ora.ora after ListView swipes"
    results["shots"]["open_rides_after_scroll"] = str(screencap("open_rides_after_scroll").name)

    # Accept → offer sheet (if card present)
    u = texts(xml)
    if "Accept" in u and M.tap_contains(xml, "Accept"):
        time.sleep(2.0)
        xml = dump("accept_sheet")
        results["shots"]["accept_sheet"] = str(screencap("accept_sheet").name)
        su = texts(xml)
        results["acceptLifecycle"]["sheetOpened"] = (
            "PASS"
            if ("Counteroffer" in su or "Submit" in su or "passenger" in su.lower())
            else "PARTIAL"
        )
        # Tap counteroffer chip if present (do not submit yet — lifecycle handled by API script)
        if "Counteroffer" in su:
            M.tap_contains(xml, "Counteroffer")
            time.sleep(1.0)
            xml = dump("counteroffer")
            results["shots"]["counteroffer"] = str(screencap("counteroffer").name)
            results["acceptLifecycle"]["counterofferChip"] = "PASS"
        # Cancel sheet to avoid consuming unless server-side submit script ran
        if M.tap_contains(xml, "Cancel") or M.tap_contains(xml, "Close"):
            time.sleep(1.0)
            results["acceptLifecycle"]["sheetCancelledWithoutSubmit"] = True
    else:
        results["acceptLifecycle"]["sheetOpened"] = "SKIP_NO_CARD"

    results["elapsedMs"] = int((time.time() - t0) * 1000)
    results["finishedAt"] = now_iso()
    out = ART / "open_rides_followup_physical_partial.json"
    out.write_text(json.dumps(results, indent=2))
    log(json.dumps(results, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
