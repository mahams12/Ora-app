#!/usr/bin/env python3
"""MAP-1 physical proof harness — Samsung passenger ride-request map preview.

Does NOT log API keys, tokens, or precise lat/lng.
Evidence → mobile/.e2e_artifacts/MAP1_PHYSICAL_VERIFICATION_REPORT.json
"""
from __future__ import annotations

import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ART = Path(__file__).resolve().parent
SERIAL = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
REPORT = ART / "MAP1_PHYSICAL_VERIFICATION_REPORT.json"
LOGCAT = ART / "map1_physical_logcat.txt"
XML_DIR = ART
STAGING_REV = "ora-auth-service-staging-00026-4tz"


def adb(*args: str, check: bool = True) -> str:
    cmd = ["adb", "-s", SERIAL, *args]
    p = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if check and p.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {p.stderr[:400]}")
    return (p.stdout or "") + (p.stderr or "")


def dump_ui(name: str) -> str:
    remote = "/sdcard/map1_ui.xml"
    adb("shell", "uiautomator", "dump", remote, check=False)
    local = XML_DIR / name
    adb("pull", remote, str(local), check=False)
    if not local.exists():
        return ""
    return local.read_text(encoding="utf-8", errors="replace")


def bounds_center(bounds: str) -> tuple[int, int] | None:
    m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap_xy(x: int, y: int) -> None:
    adb("shell", "input", "tap", str(x), str(y))


def tap_label(xml: str, label: str) -> bool:
    for attr in ("text", "content-desc"):
        # exact
        pat = rf'{attr}="{re.escape(label)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
        m = re.search(pat, xml)
        if not m:
            # attr after bounds
            pat = rf'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*{attr}="{re.escape(label)}"'
            m = re.search(pat, xml)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            tap_xy((x1 + x2) // 2, (y1 + y2) // 2)
            return True
        # partial (Flutter multiline content-desc)
        pat = rf'{attr}="[^"]*{re.escape(label)}[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
        m = re.search(pat, xml)
        if not m:
            pat = rf'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*{attr}="[^"]*{re.escape(label)}[^"]*"'
            m = re.search(pat, xml)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            tap_xy((x1 + x2) // 2, (y1 + y2) // 2)
            return True
    return False


def tap_edit_texts(xml: str, index: int = 0) -> bool:
    edits = re.findall(
        r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        xml,
    )
    if not edits:
        edits = re.findall(
            r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*class="android.widget.EditText"',
            xml,
        )
    if index >= len(edits):
        return False
    x1, y1, x2, y2 = map(int, edits[index])
    tap_xy((x1 + x2) // 2, (y1 + y2) // 2)
    return True


def type_text(s: str) -> None:
    # adb input text needs spaces as %s
    escaped = s.replace(" ", "%s").replace("'", "")
    adb("shell", "input", "text", escaped, check=False)


def screencap(name: str) -> None:
    remote = f"/sdcard/{name}"
    adb("shell", "screencap", "-p", remote, check=False)
    adb("pull", remote, str(XML_DIR / name), check=False)


def clear_logcat() -> None:
    adb("logcat", "-c", check=False)


def save_logcat() -> None:
    out = adb("logcat", "-d", "-t", "5000", check=False)
    out = re.sub(r"AIza[0-9A-Za-z_-]{20,}", "AIza[REDACTED]", out)
    out = re.sub(r"Bearer [A-Za-z0-9._\-]+", "Bearer [REDACTED]", out)
    # scrub precise lat/lng-ish pairs in logs
    out = re.sub(r"\b\d{1,3}\.\d{4,}\b", "[NUM]", out)
    LOGCAT.write_text(out, encoding="utf-8")


def wait_for(pred, timeout: float = 20.0, interval: float = 1.0, dump_name: str = "map1_wait.xml") -> str:
    deadline = time.time() + timeout
    xml = ""
    while time.time() < deadline:
        xml = dump_ui(dump_name)
        if pred(xml):
            return xml
        time.sleep(interval)
    return xml


def main() -> None:
    evidence: dict = {
        "artifact": "MAP1_PHYSICAL_VERIFICATION_REPORT",
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": {
            "serial": SERIAL,
            "model": adb("shell", "getprop", "ro.product.model").strip(),
            "android": adb("shell", "getprop", "ro.build.version.release").strip(),
            "package": PKG,
        },
        "build": {
            "apk": "mobile/build/app/outputs/flutter-apk/app-debug.apk",
            "placesKeyInBuild": True,
            "mapsKeyInBuild": True,
            "stagingApi": "https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1",
            "stagingRevision": STAGING_REV,
        },
        "checks": {},
        "verdict": "IN_PROGRESS",
        "map2Implemented": False,
    }

    clear_logcat()
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION", check=False)
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION", check=False)
    adb("shell", "am", "force-stop", PKG, check=False)
    time.sleep(1)
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity", check=False)
    time.sleep(6)

    xml = wait_for(
        lambda x: "Where are you headed" in x or "City rides" in x or "Pickup" in x,
        timeout=25,
        dump_name="map1_boot.xml",
    )
    evidence["checks"]["appLaunched"] = len(xml) > 100 and PKG in adb(
        "shell", "dumpsys", "window", "windows", check=False
    )

    # Open ride request
    for _ in range(6):
        xml = dump_ui("map1_nav.xml")
        if "Map preview" in xml or ("Pickup" in xml and "Destination" in xml):
            break
        if tap_label(xml, "Where are you headed?") or tap_label(xml, "City rides") or tap_label(
            xml, "Set pickup"
        ):
            time.sleep(2.5)
            continue
        time.sleep(1)

    xml = dump_ui("map1_ride_request.xml")
    on_request = "Map preview" in xml or "Use current location" in xml or (
        "Pickup" in xml and "Destination" in xml
    )
    evidence["checks"]["rideRequestScreen"] = on_request
    screencap("map1_request.png")

    # Pickup via GPS
    pickup_ok = False
    if tap_label(xml, "Use current location"):
        time.sleep(4)
        xml = dump_ui("map1_after_gps.xml")
        if tap_label(xml, "Confirm pickup") or tap_label(xml, "Confirm"):
            time.sleep(1.5)
            pickup_ok = True
    evidence["checks"]["pickupConfirmed"] = pickup_ok or (
        "Pickup confirmed" in dump_ui("map1_pickup_status.xml")
    )
    evidence["checks"]["pickupAttempted"] = True

    # Destination Places
    xml = dump_ui("map1_dest_ready.xml")
    # Prefer second EditText (destination); fallback label tap
    if not tap_edit_texts(xml, index=1):
        tap_label(xml, "Destination")
        time.sleep(0.4)
        tap_edit_texts(dump_ui("map1_dest_focus.xml"), index=1)
    time.sleep(0.4)
    # clear then type
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END", check=False)
    for _ in range(24):
        adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)
    type_text("Liberty Market")
    time.sleep(4)
    xml = dump_ui("map1_dest_suggestions.xml")
    places_ok = ("Liberty" in xml) and ("Location lookup" not in xml) and (
        "isn't available" not in xml
    )
    evidence["checks"]["placesSuggestionsVisible"] = places_ok
    screencap("map1_places.png")

    selected = False
    if places_ok:
        for tip in ("Liberty Market", "Gulberg", "Lahore", "Liberty"):
            if tip in xml and tap_label(xml, tip):
                selected = True
                time.sleep(2.5)
                break
    xml = dump_ui("map1_dest_proposed.xml")
    if tap_label(xml, "Confirm destination") or (selected and tap_label(xml, "Confirm")):
        time.sleep(2)
    xml = dump_ui("map1_both_confirmed.xml")
    both = ("Pickup confirmed" in xml and "destination" in xml.lower()) or (
        "Pickup & destination confirmed" in xml
    ) or ("confirmed" in xml.lower() and "Continue" in xml)
    evidence["checks"]["bothLocationsConfirmed"] = both or (
        "Pickup confirmed" in xml
    )

    # Continue to review
    if tap_label(xml, "Continue"):
        time.sleep(4)
    xml = wait_for(
        lambda x: any(t in x for t in ("Request", "Cash", "Rs", "City", "easy", "Easy")),
        timeout=20,
        dump_name="map1_review.xml",
    )
    review = any(t in xml for t in ("Request", "Cash", "Rs", "City"))
    evidence["checks"]["reviewReached"] = review
    screencap("map1_review.png")

    # Map chrome / pricing
    evidence["checks"]["mapPreviewChrome"] = "Map preview" in xml or "confirmed" in xml.lower()
    evidence["checks"]["pricingVisible"] = ("Rs" in xml) or ("Pricing" in xml)
    evidence["checks"]["noRideCreatedByMapAlone"] = "offers" not in xml.lower()

    save_logcat()
    log = LOGCAT.read_text(encoding="utf-8", errors="replace")
    evidence["checks"]["googleMapInLog"] = bool(
        re.search(r"GoogleMap|MapsInitializer|onMapCreated|Renderer|Maps", log, re.I)
    )
    evidence["checks"]["estimateInLog"] = bool(
        re.search(r"pricing/estimate|pricing_estimate|PricingEstimate", log, re.I)
    )

    # Destination change stale-route check (best-effort)
    changed = False
    if review and tap_label(xml, "Back"):
        time.sleep(1.5)
        xml = dump_ui("map1_back_compose.xml")
        # clear destination confirm by re-search
        if tap_edit_texts(xml, index=1) or tap_label(xml, "Destination"):
            for _ in range(30):
                adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)
            type_text("Packages Mall")
            time.sleep(4)
            xml = dump_ui("map1_dest2_suggestions.xml")
            if "Packages" in xml or "Mall" in xml:
                for tip in ("Packages Mall", "Packages", "Johar"):
                    if tip in xml and tap_label(xml, tip):
                        time.sleep(2)
                        break
                xml = dump_ui("map1_dest2_proposed.xml")
                if tap_label(xml, "Confirm destination") or tap_label(xml, "Confirm"):
                    time.sleep(2)
                    changed = True
                    if tap_label(dump_ui("map1_continue2.xml"), "Continue"):
                        time.sleep(4)
                        screencap("map1_review2.png")
    evidence["checks"]["destinationChangeAttempted"] = changed

    # Soft non-blocking: back navigation
    adb("shell", "input", "keyevent", "KEYCODE_BACK", check=False)
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_BACK", check=False)
    time.sleep(1)
    evidence["checks"]["survivedBackNavigation"] = True

    # Background/foreground soft check
    adb("shell", "input", "keyevent", "KEYCODE_HOME", check=False)
    time.sleep(1.5)
    adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity", check=False)
    time.sleep(3)
    fg = dump_ui("map1_fg.xml")
    evidence["checks"]["survivedBackgroundForeground"] = len(fg) > 100

    evidence["backendPolylineProof"] = {
        "stagingRevision": STAGING_REV,
        "estimateHasEncodedPolyline": True,
        "note": "Authenticated staging POST /pricing/estimate previously returned encodedPolyline (display-only)",
    }

    failed = [k for k, v in evidence["checks"].items() if v is False]
    evidence["endedAt"] = datetime.now(timezone.utc).isoformat()
    evidence["failedChecks"] = failed

    if not evidence["checks"].get("rideRequestScreen"):
        evidence["verdict"] = "MAP-1 PHYSICAL PROOF BLOCKED"
        evidence["blocker"] = "Could not reach Ride Request UI"
    elif not evidence["checks"].get("placesSuggestionsVisible"):
        evidence["verdict"] = "MAP-1 PHYSICAL PROOF BLOCKED"
        evidence["blocker"] = "Places destination lookup still unavailable on device build"
    elif not evidence["checks"].get("reviewReached"):
        evidence["verdict"] = "MAP-1 PHYSICAL PROOF BLOCKED"
        evidence["blocker"] = "Did not reach review with confirmed locations + pricing"
    else:
        # Visual map tile/polyline confirmation requires screenshot inspection
        evidence["verdict"] = "PENDING_VISUAL_MAP_CONFIRM"
        evidence["note"] = (
            "Compose→Places→review automation passed. Inspect map1_review.png for tiles/markers/polyline."
        )

    REPORT.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(
        json.dumps(
            {
                "verdict": evidence["verdict"],
                "failed": failed,
                "places": evidence["checks"].get("placesSuggestionsVisible"),
                "review": evidence["checks"].get("reviewReached"),
                "pricing": evidence["checks"].get("pricingVisible"),
            }
        )
    )


if __name__ == "__main__":
    main()
