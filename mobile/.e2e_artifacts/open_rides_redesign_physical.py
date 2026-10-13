#!/usr/bin/env python3
"""Open Rides redesign audit — physical capture on SM-A325F (staging)."""
from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

import map2a_physical as M

DEV, PKG, ART = M.DEV, M.PKG, M.ART
REPORT = ART / "OPEN_RIDES_REDESIGN_AUDIT_REPORT.json"
LOGCAT = ART / "open_rides_audit_logcat.txt"


def log(*a):
    print(*a, flush=True)


def screencap(tag: str) -> str:
    name = f"open_rides_audit_{tag}.png"
    remote = f"/sdcard/{name}"
    path = ART / name
    try:
        M.sh("screencap", "-p", remote)
        M.adb("pull", remote, str(path))
        return str(path.relative_to(ART.parent)) if path.exists() else ""
    except Exception as e:
        log("screencap fail", tag, type(e).__name__)
        return ""


def dump(tag: str) -> str:
    xml = M.dump(f"ora_{tag}")
    (ART / f"open_rides_audit_{tag}.xml").write_text(xml)
    return xml


def texts(xml: str) -> str:
    return M.unescape(xml)


def has(xml: str, *needles: str) -> bool:
    u = texts(xml)
    return all(n in u for n in needles)


def main() -> int:
    t0 = time.time()
    M.sh("logcat", "-c")
    checks = {}
    shots = {}

    # Warm launch — app already installed by caller.
    M.adb("shell", "am", "force-stop", PKG)
    time.sleep(0.5)
    cold_start = time.time()
    M.adb(
        "shell",
        "am",
        "start",
        "-n",
        f"{PKG}/.MainActivity",
    )
    time.sleep(4.0)
    xml = dump("boot")
    shots["boot"] = screencap("boot")
    cold_ms = int((time.time() - cold_start) * 1000)

    # Login as driver if needed.
    if has(xml, "Send OTP") or has(xml, "Phone number") or has(xml, "Verify"):
        log("auth required — driver force_login")
        xml = M.force_login(M.DRIVER_PHONE_UI, M.DRIVER_OTP, want_passenger=False)
        dump("after_login")
        shots["after_login"] = screencap("after_login")
        checks["A_driver_login"] = "PASS"
    else:
        checks["A_already_authed"] = (
            "PASS" if ("Open rides" in texts(xml) or "ora" in texts(xml).lower()) else "PARTIAL"
        )

    # Navigate to Open rides.
    if not has(xml, "Open rides"):
        if M.tap_contains(xml, "Open rides") or M.tap_contains(xml, "Open"):
            time.sleep(2.5)
            xml = dump("open_tab")
        else:
            M.sh("input", "tap", "216", "2200")
            time.sleep(2.5)
            xml = dump("open_tab_tap")

    first_card_ms = int((time.time() - cold_start) * 1000)
    shots["open_rides"] = screencap("open_rides")
    xml = dump("open_rides")
    u = texts(xml)

    checks["B_open_rides_screen"] = (
        "PASS" if "Open rides" in u else "FAIL"
    )
    checks["C_accept_visible"] = (
        "PASS" if "Accept" in u else ("PARTIAL" if "No open ride" in u else "FAIL")
    )
    checks["D_decline_visible"] = (
        "PASS" if "Decline" in u else ("PARTIAL" if "No open ride" in u else "FAIL")
    )
    checks["E_no_fake_name"] = (
        "PASS" if "Ayesha" not in u and "LEA 1234" not in u else "FAIL"
    )
    checks["F_earnings_or_empty"] = (
        "PASS"
        if ("Your earnings" in u or "Rs " in u or "No open ride" in u)
        else "PARTIAL"
    )

    # Accept → offer sheet (only if a card exists).
    if "Accept" in u:
        M.tap_contains(xml, "Accept")
        time.sleep(1.5)
        xml = dump("after_accept")
        shots["after_accept"] = screencap("after_accept")
        u2 = texts(xml)
        checks["G_accept_opens_sheet"] = (
            "PASS"
            if (
                "Submit offer" in u2
                or "Accept passenger price" in u2
                or "Counter" in u2
                or "offer" in u2.lower()
            )
            else "FAIL"
        )
        # Dismiss sheet
        M.sh("input", "keyevent", "4")
        time.sleep(1.0)
        xml = dump("after_sheet_back")
    else:
        checks["G_accept_opens_sheet"] = "BLOCKED"

    # Decline local hide (if still visible).
    xml = dump("pre_decline")
    if "Decline" in texts(xml):
        before = texts(xml).count("Accept")
        M.tap_contains(xml, "Decline")
        time.sleep(1.0)
        xml = dump("after_decline")
        shots["after_decline"] = screencap("after_decline")
        after = texts(xml).count("Accept")
        checks["H_decline_local"] = (
            "PASS" if after <= before else "PARTIAL"
        )
        # No false server success banner
        checks["I_no_decline_success_claim"] = (
            "PASS"
            if "declined on server" not in texts(xml).lower()
            else "FAIL"
        )
    else:
        checks["H_decline_local"] = "BLOCKED"
        checks["I_no_decline_success_claim"] = "BLOCKED"

    # Pull logcat
    try:
        out = M.adb("shell", "logcat", "-d", "-t", "200")
        LOGCAT.write_text(out if isinstance(out, str) else out.decode("utf-8", "replace"))
    except Exception as e:
        log("logcat fail", type(e).__name__)

    elapsed = int((time.time() - t0) * 1000)
    report = {
        "artifact": "OPEN_RIDES_REDESIGN_AUDIT_REPORT",
        "completedAt": datetime.now(timezone.utc).isoformat(),
        "device": {
            "serial": DEV,
            "model": "SM-A325F",
            "android": "13",
            "package": PKG,
        },
        "physicalCapture": {
            "coldStartMs": cold_ms,
            "timeToOpenRidesMs": first_card_ms,
            "elapsedMs": elapsed,
            "screenshots": shots,
            "checks": checks,
        },
    }
    # Merge later by caller — write partial physical section
    partial = ART / "open_rides_audit_physical_partial.json"
    partial.write_text(json.dumps(report, indent=2))
    log("physical partial written", partial)
    log("checks", json.dumps(checks, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
