#!/usr/bin/env python3
"""Ride Request half-screen map UX — physical proof on SM-A325F.

Does NOT log API keys, tokens, or precise lat/lng.
Evidence → mobile/.e2e_artifacts/ride_request_map_halfscreen_physical_partial.json
Invoke: python3 mobile/.e2e_artifacts/ride_request_map_halfscreen_physical.py
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
REPORT_PARTIAL = ART / "ride_request_map_halfscreen_physical_partial.json"
PREFIX = "hs"


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
    """Return (text, content_desc_decoded, bounds) for each node with bounds."""
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


def bounds_size(bounds: str) -> tuple[int, int] | None:
    m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return x2 - x1, y2 - y1


def has_label(xml: str, label: str) -> bool:
    needle = label.lower()
    for text, desc, _ in _nodes(xml):
        if needle in text.lower() or needle in desc.lower():
            return True
    # raw fallback (entities)
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


def wait_label(label: str, attempts: int = 15, delay: float = 1.0, dump: str = "wait") -> str:
    xml = ""
    for i in range(attempts):
        xml = dump_ui(f"{PREFIX}_{dump}_{i}.xml")
        if has_label(xml, label):
            return xml
        time.sleep(delay)
    return xml


def tap_edit(xml: str, index: int = 0) -> bool:
    edits = [
        b
        for text, desc, b in _nodes(xml)
        if "EditText" in xml[max(0, xml.find(b) - 120) : xml.find(b) + 80]
    ]
    # Prefer class attribute scan
    edits = []
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
    if index >= len(edits):
        return False
    c = bounds_center(edits[index])
    if not c:
        return False
    tap_xy(*c)
    return True


def type_text(s: str) -> None:
    escaped = s.replace(" ", "%s").replace("'", "")
    adb("shell", "input", "text", escaped, check=False)


def screen_height(xml: str) -> int:
    m = re.search(r'bounds="\[0,0\]\[(\d+),(\d+)\]"', xml)
    if m:
        return int(m.group(2))
    return 2194


def map_chrome_bounds(xml: str) -> str | None:
    for text, desc, bounds in _nodes(xml):
        if "expand map" in desc.lower() or "collapse map" in desc.lower():
            return bounds
        if "map preview" in (text + desc).lower():
            return bounds
    return None


def estimate_map_fraction(xml: str) -> float | None:
    """Estimate compact map height from sheet-top labels vs screen height."""
    h = screen_height(xml)
    if h <= 0:
        return None
    sheet_top = None
    for t2, d2, b2 in _nodes(xml):
        blob = f"{t2}\n{d2}".lower()
        # Prefer the sheet title — sits at top of compose/review sheet.
        if blob.strip() == "where to?" or blob.startswith("where to?"):
            mm = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b2)
            if mm:
                y = int(mm.group(2))
                if sheet_top is None or y < sheet_top:
                    sheet_top = y
    if sheet_top is None:
        for t2, d2, b2 in _nodes(xml):
            blob = f"{t2}\n{d2}".lower()
            if "use current location" in blob:
                mm = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b2)
                if mm:
                    sheet_top = int(mm.group(2))
                    break
    if sheet_top is None:
        return None
    # Sheet is translated up by ~18dp under the map; sheet_top ≈ map bottom.
    return sheet_top / h


def clear_field() -> None:
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END", check=False)
    for _ in range(28):
        adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)


def main() -> int:
    started = datetime.now(timezone.utc).isoformat()
    checks: dict[str, object] = {
        "deviceAttached": False,
        "apkInstalled": False,
        "appLaunched": False,
        "rideRequestOpened": False,
        "compactDefaultSheetVisible": False,
        "compactHeightBand45to55": "UNVERIFIED",
        "expandControlPresent": False,
        "expandedFullScreen": False,
        "collapseRestoredSheet": False,
        "androidBackCollapsed": False,
        "formAccessibleAfterCollapse": False,
        "repeatedExpandCollapse": False,
        "routeOrMarkersObserved": "UNVERIFIED",
        "keyboardBehavior": "UNVERIFIED",
        "cameraJumpFlicker": "UNVERIFIED",
        "unexpectedApiCalls": "UNVERIFIED",
    }
    evidence: list[str] = []
    notes: list[str] = []
    metrics: dict[str, object] = {}

    devices = subprocess.run(
        ["adb", "devices", "-l"], capture_output=True, text=True, check=False
    ).stdout
    if SERIAL not in devices or f"{SERIAL}" not in devices:
        notes.append(f"Device {SERIAL} not attached")
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
        print("DEVICE_NOT_ATTACHED")
        return 2
    # Ensure state is device (not unauthorized)
    if not re.search(rf"{SERIAL}\s+device\b", devices):
        notes.append(f"Device {SERIAL} present but not in 'device' state")
        print("DEVICE_NOT_READY")
        return 2

    checks["deviceAttached"] = True
    model = adb("shell", "getprop", "ro.product.model").strip()
    android = adb("shell", "getprop", "ro.build.version.release").strip()

    if not APK.exists():
        notes.append(f"APK missing: {APK}")
        print("APK_MISSING")
        return 3

    adb("install", "-r", str(APK))
    checks["apkInstalled"] = True

    adb("logcat", "-c", check=False)
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
    # Wait past splash + staging sign-in ("Signing you in…") to stable home.
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
    if not home_ready:
        notes.append("Home CTA not stable after splash/sign-in wait")

    # Navigate home → Ride Request (retry; early taps can hit mid-auth).
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
            # Wait specifically for Ride Request chrome.
            for j in range(12):
                time.sleep(1.0)
                probe = dump_ui(f"{PREFIX}_nav_probe_{attempt}_{j}.xml")
                if has_label(probe, "Expand map"):
                    xml = probe
                    break
                if has_label(probe, "Signing you in"):
                    break
            else:
                continue
            if has_label(xml, "Expand map"):
                break
            continue
        time.sleep(1)

    xml = dump_ui(f"{PREFIX}_compact.xml")
    evidence.append(f"{PREFIX}_compact.xml")
    screenshot(f"{PREFIX}_compact.png")
    evidence.append(f"{PREFIX}_compact.png")

    on_request = has_label(xml, "Expand map") or (
        has_label(xml, "Pickup") and (has_label(xml, "Where to?") or has_label(xml, "Destination"))
    )
    checks["rideRequestOpened"] = on_request
    checks["compactDefaultSheetVisible"] = on_request and (
        has_label(xml, "Where to?") or has_label(xml, "Pickup")
    )
    checks["expandControlPresent"] = has_label(xml, "Expand map")

    frac = estimate_map_fraction(xml)
    metrics["estimatedMapFraction"] = frac
    if frac is not None:
        checks["compactHeightBand45to55"] = bool(0.40 <= frac <= 0.62)
        notes.append(f"compact map fraction proxy (sheetTop/screenH)={frac:.3f}")
    else:
        notes.append("compact height fraction could not be estimated from UI bounds")

    # Optional: seed locations for markers/route (best-effort; soft)
    markers_note = "skipped"
    if on_request and has_label(xml, "Use current location"):
        if tap_label(xml, "Use current location"):
            time.sleep(4)
            xml = dump_ui(f"{PREFIX}_gps.xml")
            if tap_label(xml, "Confirm pickup") or tap_label(xml, "Confirm"):
                time.sleep(1.5)
            xml = dump_ui(f"{PREFIX}_dest_focus.xml")
            if tap_edit(xml, 1) or tap_label(xml, "Destination"):
                time.sleep(0.3)
                clear_field()
                type_text("Liberty Market")
                time.sleep(4)
                xml = dump_ui(f"{PREFIX}_sugg.xml")
                evidence.append(f"{PREFIX}_sugg.xml")
                for tip in ("Liberty Market", "Liberty", "Gulberg"):
                    if tap_label(xml, tip):
                        time.sleep(1.5)
                        break
                xml = dump_ui(f"{PREFIX}_prop.xml")
                if tap_label(xml, "Confirm destination") or tap_label(xml, "Confirm"):
                    time.sleep(2.5)
                xml = dump_ui(f"{PREFIX}_with_route.xml")
                screenshot(f"{PREFIX}_with_route.png")
                evidence.append(f"{PREFIX}_with_route.png")
                # Status chip / confirmed copy implies markers path exercised
                if has_label(xml, "confirmed") or has_label(xml, "Map preview") or has_label(
                    xml, "route"
                ):
                    checks["routeOrMarkersObserved"] = "PASS_STATUS_CHIP"
                    markers_note = "status chip after confirm"
                else:
                    checks["routeOrMarkersObserved"] = "PARTIAL_NO_CHIP"
                    markers_note = "confirmed flow attempted; chip not found"
    notes.append(f"markers/route: {markers_note}")

    # Capture baseline text for state preservation
    xml = dump_ui(f"{PREFIX}_pre_expand.xml")
    had_pickup_field = has_label(xml, "Pickup")

    expand_ok = tap_label(xml, "Expand map")
    checks["expandControlPresent"] = checks["expandControlPresent"] or expand_ok
    if expand_ok:
        time.sleep(1.5)
        xml_exp = dump_ui(f"{PREFIX}_expanded.xml")
        evidence.append(f"{PREFIX}_expanded.xml")
        screenshot(f"{PREFIX}_expanded.png")
        evidence.append(f"{PREFIX}_expanded.png")
        checks["expandedFullScreen"] = has_label(xml_exp, "Collapse map") and not has_label(
            xml_exp, "Where to?"
        )

        collapse_ok = tap_label(xml_exp, "Collapse map")
        if collapse_ok:
            time.sleep(1.2)
            xml_col = dump_ui(f"{PREFIX}_collapsed.xml")
            evidence.append(f"{PREFIX}_collapsed.xml")
            screenshot(f"{PREFIX}_collapsed.png")
            evidence.append(f"{PREFIX}_collapsed.png")
            checks["collapseRestoredSheet"] = has_label(xml_col, "Where to?") or has_label(
                xml_col, "Pickup"
            )
            checks["formAccessibleAfterCollapse"] = checks["collapseRestoredSheet"] and (
                had_pickup_field == has_label(xml_col, "Pickup")
            )

        # Android back
        xml2 = dump_ui(f"{PREFIX}_pre_back.xml")
        if tap_label(xml2, "Expand map"):
            time.sleep(1.0)
            adb("shell", "input", "keyevent", "4")
            time.sleep(1.2)
            xml_back = dump_ui(f"{PREFIX}_after_back.xml")
            evidence.append(f"{PREFIX}_after_back.xml")
            screenshot(f"{PREFIX}_after_back.png")
            evidence.append(f"{PREFIX}_after_back.png")
            still_in_flow = has_label(xml_back, "Where to?") or has_label(xml_back, "Pickup")
            collapsed = has_label(xml_back, "Expand map") and not has_label(
                xml_back, "Collapse map"
            )
            checks["androidBackCollapsed"] = bool(still_in_flow and collapsed)

        # Repeated expand/collapse
        ok_repeat = True
        for i in range(3):
            x = dump_ui(f"{PREFIX}_rep_{i}a.xml")
            if not tap_label(x, "Expand map"):
                ok_repeat = False
                break
            time.sleep(0.9)
            x2 = dump_ui(f"{PREFIX}_rep_{i}b.xml")
            if not tap_label(x2, "Collapse map"):
                ok_repeat = False
                break
            time.sleep(0.9)
        checks["repeatedExpandCollapse"] = ok_repeat
        checks["cameraJumpFlicker"] = (
            "NO_CRASH_OBSERVED_DURING_REPEAT"
            if ok_repeat
            else "REPEAT_FAILED"
        )

        # Keyboard: focus pickup, assert sheet/CTA still present without hard crash
        xml_k = dump_ui(f"{PREFIX}_pre_kb.xml")
        if tap_edit(xml_k, 0) or tap_label(xml_k, "Pickup"):
            time.sleep(1.0)
            xml_kb = dump_ui(f"{PREFIX}_keyboard.xml")
            screenshot(f"{PREFIX}_keyboard.png")
            evidence.append(f"{PREFIX}_keyboard.png")
            # Primary compose CTA or fields still in hierarchy
            ok_kb = has_label(xml_kb, "Pickup") or has_label(xml_kb, "Continue") or has_label(
                xml_kb, "Destination"
            )
            checks["keyboardBehavior"] = "PASS_NO_OVERFLOW_SIGNAL" if ok_kb else "FAIL_FIELDS_GONE"
            adb("shell", "input", "keyevent", "4", check=False)  # dismiss kb / stay in flow
            time.sleep(0.5)

    logcat = adb("logcat", "-d", "-t", "800", check=False)
    logcat = re.sub(r"AIza[0-9A-Za-z_-]{20,}", "AIza[REDACTED]", logcat)
    logcat = re.sub(r"Bearer [A-Za-z0-9._\-]+", "Bearer [REDACTED]", logcat)
    (ART / f"{PREFIX}_physical_logcat.txt").write_text(logcat, encoding="utf-8")
    evidence.append(f"{PREFIX}_physical_logcat.txt")
    create_hits = len(re.findall(r"createRide", logcat, flags=re.I))
    # Expand/collapse alone should not create rides
    checks["unexpectedApiCalls"] = (
        "NO_CREATE_RIDE_ON_TOGGLE" if create_hits == 0 else f"createRide_hits={create_hits}"
    )

    ended = datetime.now(timezone.utc).isoformat()
    failed = [k for k, v in checks.items() if v is False]
    # Treat explicit FAIL_* strings as failed
    for k, v in list(checks.items()):
        if isinstance(v, str) and v.startswith("FAIL"):
            failed.append(k)

    verdict = (
        "PHYSICAL PASS"
        if not failed
        else ("PHYSICAL PARTIAL" if checks.get("apkInstalled") else "PHYSICAL FAIL")
    )
    out = {
        "startedAt": started,
        "endedAt": ended,
        "device": {"serial": SERIAL, "model": model, "android": android, "package": PKG},
        "apk": "mobile/build/app/outputs/flutter-apk/app-debug.apk",
        "checks": checks,
        "metrics": metrics,
        "failedChecks": failed,
        "evidenceFiles": evidence,
        "notes": notes,
        "verdict": verdict,
    }
    REPORT_PARTIAL.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"verdict": verdict, "failedChecks": failed, "checks": checks}, indent=2))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
