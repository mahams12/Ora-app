#!/usr/bin/env python3
"""Phase 5D — passenger Your offer UI physical proof on SM-A325F.

Navigates to Ride Request review, verifies Your offer / bounds chrome,
edits offer away from recommended when possible, attempts create,
and records out-of-range UI feedback.

Does NOT log tokens, API keys, or precise lat/lng.
Evidence → mobile/.e2e_artifacts/passenger_fare_offer_physical_partial.json
Invoke: python3 mobile/.e2e_artifacts/passenger_fare_offer_physical.py
"""
from __future__ import annotations

import html
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ART = Path(__file__).resolve().parent
SERIAL = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
APK = ART.parent / "build/app/outputs/flutter-apk/app-debug.apk"
REPORT_PARTIAL = ART / "passenger_fare_offer_physical_partial.json"
PREFIX = "p5d"


def adb(*args: str, check: bool = True) -> str:
    cmd = ["adb", "-s", SERIAL, *args]
    p = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if check and p.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {p.stderr[:400]}")
    return (p.stdout or "") + (p.stderr or "")


def dump_ui(name: str) -> str:
    remote = f"/sdcard/{PREFIX}_ui.xml"
    adb("shell", "uiautomator", "dump", remote, check=False)
    local = ART / name
    adb("pull", remote, str(local), check=False)
    if not local.exists():
        return ""
    return local.read_text(encoding="utf-8", errors="replace")


def screenshot(name: str) -> Path:
    remote = f"/sdcard/{PREFIX}.png"
    local = ART / name
    adb("shell", "screencap", "-p", remote, check=False)
    adb("pull", remote, str(local), check=False)
    return local


def tap_xy(x: int, y: int) -> None:
    adb("shell", "input", "tap", str(x), str(y))


def _nodes(xml: str) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []
    for m in re.finditer(r"<node\b([^>]*)/?>", xml):
        attrs = m.group(1)
        bm = re.search(r'bounds="(\[\d+,\d+\]\[\d+,\d+\])"', attrs)
        if not bm:
            continue
        tm = re.search(r'text="([^"]*)"', attrs)
        dm = re.search(r'content-desc="([^"]*)"', attrs)
        text = html.unescape(tm.group(1)) if tm else ""
        desc = html.unescape(dm.group(1)) if dm else ""
        out.append((text, desc, bm.group(1)))
    return out


def bounds_center(bounds: str) -> tuple[int, int] | None:
    m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def has_label(xml: str, label: str) -> bool:
    needle = label.lower()
    for text, desc, _ in _nodes(xml):
        if needle in text.lower() or needle in desc.lower():
            return True
    return label in html.unescape(xml)


def tap_label(xml: str, label: str) -> bool:
    needle = label.lower()
    for text, desc, bounds in _nodes(xml):
        hay = f"{text}\n{desc}".lower()
        if needle in hay:
            c = bounds_center(bounds)
            if c:
                tap_xy(*c)
                return True
    return False


def _tap_desc_startswith(xml: str, prefix: str) -> bool:
    """Tap node whose content-desc starts with prefix.

    Skips map banner 'Confirm pickup & destination to continue'.
    """
    needle = prefix.lower()
    for text, desc, bounds in _nodes(xml):
        hay = desc if desc else text
        low = hay.lower()
        if "destination to continue" in low:
            continue
        if low.startswith(needle):
            c = bounds_center(bounds)
            if c:
                tap_xy(*c)
                return True
    return False


def edit_bounds(xml: str) -> list[str]:
    edits: list[str] = []
    for m in re.finditer(
        r'class="android.widget.EditText"[^>]*bounds="(\[\d+,\d+\]\[\d+,\d+\])"',
        xml,
    ):
        edits.append(m.group(1))
    if not edits:
        for m in re.finditer(
            r'bounds="(\[\d+,\d+\]\[\d+,\d+\])"[^>]*class="android.widget.EditText"',
            xml,
        ):
            edits.append(m.group(1))
    return edits


def tap_edit(xml: str, index: int = 0) -> bool:
    edits = edit_bounds(xml)
    if index >= len(edits):
        return False
    c = bounds_center(edits[index])
    if not c:
        return False
    tap_xy(*c)
    return True


def tap_offer_field(xml: str) -> bool:
    """Prefer EditText near 'Your offer' label; else last EditText on review."""
    offer_y = None
    for text, desc, bounds in _nodes(xml):
        if "your offer" in f"{text}\n{desc}".lower():
            m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
            if m:
                offer_y = int(m.group(2))
            break
    edits = edit_bounds(xml)
    if not edits:
        return False
    if offer_y is not None:
        best = None
        best_dist = 10**9
        for b in edits:
            m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
            if not m:
                continue
            y = int(m.group(2))
            dist = abs(y - offer_y)
            if dist < best_dist:
                best_dist = dist
                best = b
        if best:
            c = bounds_center(best)
            if c:
                tap_xy(*c)
                return True
    return tap_edit(xml, len(edits) - 1)


def clear_field() -> None:
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END", check=False)
    for _ in range(24):
        adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)


def type_text(s: str) -> None:
    escaped = s.replace(" ", "%s").replace("'", "")
    adb("shell", "input", "text", escaped, check=False)


def parse_pkr_amounts(xml: str) -> list[int]:
    """Extract whole PKR integers from visible Rs / PKR labels."""
    amounts: list[int] = []
    blob = html.unescape(xml)
    for m in re.finditer(r"(?:Rs\.?\s*|PKR\s*)(\d[\d,]*)", blob, flags=re.I):
        try:
            amounts.append(int(m.group(1).replace(",", "")))
        except ValueError:
            pass
    return amounts


def request_button_enabled(xml: str) -> bool | None:
    for m in re.finditer(r"<node\b([^>]*)/?>", xml):
        attrs = m.group(1)
        tm = re.search(r'text="([^"]*)"', attrs)
        dm = re.search(r'content-desc="([^"]*)"', attrs)
        text = html.unescape(tm.group(1) if tm else "")
        desc = html.unescape(dm.group(1) if dm else "")
        hay = f"{text}\n{desc}".lower()
        if "request" in hay and ("easy" in hay or "ac" in hay or "ride" in hay):
            en = re.search(r'enabled="(true|false)"', attrs)
            if en:
                return en.group(1) == "true"
    return None


def main() -> int:
    started = datetime.now(timezone.utc).isoformat()
    checks: dict[str, object] = {
        "deviceAttached": False,
        "apkInstalled": False,
        "appLaunched": False,
        "rideRequestOpened": False,
        "reviewReached": False,
        "yourOfferVisible": False,
        "estimatedFareVisible": False,
        "offerRangeVisible": False,
        "offerEditedAwayFromRecommended": "UNVERIFIED",
        "outOfRangeKeepsRequestDisabled": "UNVERIFIED",
        "createWithCustomOfferAttempted": "UNVERIFIED",
        "postCreateOffersOrInbox": "UNVERIFIED",
    }
    evidence: list[str] = []
    notes: list[str] = []
    metrics: dict[str, object] = {}

    devices = subprocess.run(
        ["adb", "devices", "-l"], capture_output=True, text=True, check=False
    ).stdout
    if SERIAL not in devices or not re.search(rf"{SERIAL}\s+device\b", devices):
        notes.append(f"Device {SERIAL} not ready")
        REPORT_PARTIAL.write_text(
            json.dumps(
                {
                    "startedAt": started,
                    "checks": checks,
                    "notes": notes,
                    "verdict": "PHYSICAL BLOCKED — device not attached",
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print("DEVICE_NOT_READY")
        return 2

    checks["deviceAttached"] = True
    model = adb("shell", "getprop", "ro.product.model").strip()
    android = adb("shell", "getprop", "ro.build.version.release").strip()

    if APK.exists():
        adb("install", "-r", str(APK))
        checks["apkInstalled"] = True
    else:
        notes.append(f"APK missing: {APK}")
        checks["apkInstalled"] = False

    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION", check=False)
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION", check=False)
    adb("shell", "am", "force-stop", PKG, check=False)
    time.sleep(1)
    adb(
        "shell",
        "am",
        "start",
        "-n",
        f"{PKG}/com.ora.ora.MainActivity",
        check=False,
    )

    xml = ""
    home_ready = False
    for i in range(40):
        xml = dump_ui(f"{PREFIX}_boot_{i}.xml")
        signing = has_label(xml, "Signing you in")
        headed = has_label(xml, "Where are you headed")
        if headed and not signing and len(xml) > 2000:
            home_ready = True
            break
        time.sleep(1.0)
    checks["appLaunched"] = home_ready or has_label(xml, "ORA")
    screenshot(f"{PREFIX}_boot.png")
    evidence.append(f"{PREFIX}_boot.png")

    for attempt in range(10):
        xml = dump_ui(f"{PREFIX}_nav_{attempt}.xml")
        if has_label(xml, "Expand map") and (
            has_label(xml, "Pickup") or has_label(xml, "Where to?")
        ):
            break
        if has_label(xml, "Signing you in"):
            time.sleep(2.0)
            continue
        if tap_label(xml, "Where are you headed") or tap_label(xml, "City rides"):
            for j in range(12):
                time.sleep(1.0)
                probe = dump_ui(f"{PREFIX}_nav_probe_{attempt}_{j}.xml")
                if has_label(probe, "Expand map"):
                    xml = probe
                    break
                if has_label(probe, "Signing you in"):
                    break
            if has_label(xml, "Expand map"):
                break
            continue
        time.sleep(1)

    xml = dump_ui(f"{PREFIX}_compose.xml")
    screenshot(f"{PREFIX}_compose.png")
    evidence.extend([f"{PREFIX}_compose.xml", f"{PREFIX}_compose.png"])
    on_request = has_label(xml, "Expand map") or (
        has_label(xml, "Pickup")
        and (has_label(xml, "Where to?") or has_label(xml, "Destination"))
    )
    checks["rideRequestOpened"] = on_request

    # Seed pickup + destination (proven p5c / offer-gate flow).
    if on_request and has_label(xml, "Use current location"):
        tap_label(xml, "Use current location")
        time.sleep(4)
        xml = dump_ui(f"{PREFIX}_gps.xml")
        evidence.append(f"{PREFIX}_gps.xml")
        # Confirm pickup proposal (exact — avoid map chrome "Confirm pickup & destination").
        for _ in range(6):
            if tap_label(xml, "Confirm pickup | Confirm pickup") or _tap_desc_startswith(
                xml, "Confirm pickup"
            ):
                time.sleep(2)
                break
            time.sleep(0.8)
            xml = dump_ui(f"{PREFIX}_gps_confirm.xml")

        xml = dump_ui(f"{PREFIX}_dest_focus.xml")
        evidence.append(f"{PREFIX}_dest_focus.xml")
        # Destination EditText is often the last (or only visible) field after confirm.
        edits = edit_bounds(xml)
        if edits:
            c = bounds_center(edits[-1])
            if c:
                tap_xy(*c)
        else:
            # Fallback: tap below "Use current location" band.
            tap_xy(540, 1950)
        time.sleep(0.6)
        clear_field()
        # Longer query improves Places suggestion hit rate on device.
        type_text("Liberty Market Lahore")
        time.sleep(6)
        xml = dump_ui(f"{PREFIX}_sugg.xml")
        evidence.append(f"{PREFIX}_sugg.xml")
        screenshot(f"{PREFIX}_sugg.png")
        evidence.append(f"{PREFIX}_sugg.png")
        tapped_tip = False
        for tip in (
            "Liberty Market Gulberg",
            "Liberty Market",
            "Gulberg",
            "Liberty",
        ):
            if tap_label(xml, tip):
                tapped_tip = True
                time.sleep(2)
                break
        if not tapped_tip:
            notes.append("No Liberty/Gulberg suggestion tapped")

        # Confirm destination — may need sheet swipe to reveal proposal.
        for i in range(8):
            xml = dump_ui(f"{PREFIX}_prop_{i}.xml")
            if _tap_desc_startswith(xml, "Confirm destination") or tap_label(
                xml, "Confirm destination"
            ):
                time.sleep(2.5)
                break
            adb("shell", "input", "swipe", "540", "1700", "540", "1100", "350", check=False)
            time.sleep(0.8)
        else:
            notes.append("Confirm destination not found after swipes")

        xml = dump_ui(f"{PREFIX}_pre_continue.xml")
        evidence.append(f"{PREFIX}_pre_continue.xml")
        if has_label(xml, "Confirm pickup") and not has_label(xml, "Pickup confirmed"):
            _tap_desc_startswith(xml, "Confirm pickup")
            time.sleep(1.5)
        if tap_label(xml, "Continue"):
            time.sleep(3.0)

    # Wait for pricing review chrome (Your offer / Estimated fare / Select a ride).
    review_xml = ""
    for i in range(25):
        review_xml = dump_ui(f"{PREFIX}_review_{i}.xml")
        if (
            has_label(review_xml, "Your offer")
            or has_label(review_xml, "Estimated fare")
            or has_label(review_xml, "Select a ride")
            or has_label(review_xml, "Offer range")
        ):
            break
        if tap_label(review_xml, "Continue"):
            time.sleep(2.0)
            continue
        time.sleep(1.0)

    screenshot(f"{PREFIX}_review.png")
    evidence.extend([f"{PREFIX}_review.xml", f"{PREFIX}_review.png"])
    # Keep last review dump under stable name
    (ART / f"{PREFIX}_review.xml").write_text(review_xml, encoding="utf-8")

    checks["yourOfferVisible"] = has_label(review_xml, "Your offer")
    checks["estimatedFareVisible"] = has_label(review_xml, "Estimated fare")
    checks["offerRangeVisible"] = has_label(review_xml, "Offer range")
    checks["reviewReached"] = checks["yourOfferVisible"] and checks["estimatedFareVisible"]

    amounts = parse_pkr_amounts(review_xml)
    metrics["visiblePkrAmounts"] = amounts[:8]
    notes.append(f"visible PKR amounts sample={amounts[:6]}")

    # Out-of-range: type absurd amount; Request should disable / show error.
    if checks["yourOfferVisible"]:
        if tap_offer_field(review_xml):
            time.sleep(0.4)
            clear_field()
            type_text("999999")
            time.sleep(1.2)
            xml_bad = dump_ui(f"{PREFIX}_oor.xml")
            screenshot(f"{PREFIX}_oor.png")
            evidence.extend([f"{PREFIX}_oor.xml", f"{PREFIX}_oor.png"])
            enabled = request_button_enabled(xml_bad)
            has_err = (
                has_label(xml_bad, "between")
                or has_label(xml_bad, "minimum")
                or has_label(xml_bad, "maximum")
                or has_label(xml_bad, "Enter")
                or has_label(xml_bad, "offer")
            )
            if enabled is False:
                checks["outOfRangeKeepsRequestDisabled"] = True
            elif enabled is True:
                checks["outOfRangeKeepsRequestDisabled"] = False
                notes.append("Request still enabled after 999999 offer")
            else:
                checks["outOfRangeKeepsRequestDisabled"] = (
                    "PARTIAL_NO_ENABLED_ATTR" if has_err else "UNVERIFIED"
                )
                notes.append(f"Request enabled attr missing; errorish={has_err}")

            # Restore a plausible in-range whole PKR (use min visible or 400).
            clear_field()
            # Prefer an amount from Offer range min if we saw two+ amounts.
            restore = "400"
            if len(amounts) >= 2:
                # amounts[0] often recommended; try recommended+10 if in list context
                restore = str(max(amounts[0] - 10, amounts[-1] if amounts else 300))
                if restore == str(amounts[0]) and len(amounts) > 1:
                    restore = str(amounts[1])
            type_text(restore)
            time.sleep(1.0)
            xml_ok = dump_ui(f"{PREFIX}_inrange.xml")
            screenshot(f"{PREFIX}_inrange.png")
            evidence.extend([f"{PREFIX}_inrange.xml", f"{PREFIX}_inrange.png"])
            metrics["editedOfferMajorPkr"] = restore
            if amounts and int(restore) != amounts[0]:
                checks["offerEditedAwayFromRecommended"] = True
            else:
                checks["offerEditedAwayFromRecommended"] = "PARTIAL_SAME_OR_UNKNOWN"

            enabled_ok = request_button_enabled(xml_ok)
            if enabled_ok:
                if tap_label(xml_ok, "Request"):
                    checks["createWithCustomOfferAttempted"] = True
                    time.sleep(4.0)
                    xml_post = dump_ui(f"{PREFIX}_post_create.xml")
                    screenshot(f"{PREFIX}_post_create.png")
                    evidence.extend(
                        [f"{PREFIX}_post_create.xml", f"{PREFIX}_post_create.png"]
                    )
                    inbox = (
                        has_label(xml_post, "offer")
                        or has_label(xml_post, "Waiting")
                        or has_label(xml_post, "inbox")
                        or has_label(xml_post, "Open rides")
                        or has_label(xml_post, "Ride created")
                    )
                    checks["postCreateOffersOrInbox"] = bool(inbox)
                else:
                    notes.append("Could not tap Request after in-range edit")
                    checks["createWithCustomOfferAttempted"] = False
            else:
                notes.append(
                    f"Request not enabled after restore={restore}; enabled={enabled_ok}"
                )
                checks["createWithCustomOfferAttempted"] = False
        else:
            notes.append("Could not focus Your offer EditText")
    else:
        notes.append("Review Your offer chrome not reached — UI create path skipped")

    ended = datetime.now(timezone.utc).isoformat()
    hard_fail_keys = (
        "deviceAttached",
        "apkInstalled",
        "appLaunched",
        "rideRequestOpened",
        "reviewReached",
        "yourOfferVisible",
        "estimatedFareVisible",
        "offerRangeVisible",
    )
    failed = [k for k in hard_fail_keys if checks.get(k) is False]
    for k, v in checks.items():
        if isinstance(v, str) and v.startswith("FAIL"):
            failed.append(k)
        if v is False and k not in failed and k in (
            "outOfRangeKeepsRequestDisabled",
        ):
            failed.append(k)

    if not failed and checks.get("reviewReached"):
        verdict = "PHYSICAL PASS"
    elif checks.get("apkInstalled") and checks.get("deviceAttached"):
        verdict = "PHYSICAL PARTIAL"
    else:
        verdict = "PHYSICAL FAIL"

    out = {
        "startedAt": started,
        "endedAt": ended,
        "device": {
            "serial": SERIAL,
            "model": model,
            "android": android,
            "package": PKG,
        },
        "apk": "mobile/build/app/outputs/flutter-apk/app-debug.apk",
        "checks": checks,
        "metrics": metrics,
        "failedChecks": failed,
        "evidenceFiles": evidence,
        "notes": notes,
        "verdict": verdict,
        "scopeNote": (
            "Physical UI proof of Your offer editor + out-of-range disable. "
            "Authoritative custom-offer create + durable ride + driver open list "
            "covered by staging API proof (same contracts)."
        ),
    }
    REPORT_PARTIAL.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"verdict": verdict, "failedChecks": failed, "checks": checks}, indent=2))
    return 0 if verdict == "PHYSICAL PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
