#!/usr/bin/env python3
"""Focused physical verification: immediate MapLibre on Where to? + route/pins.

Evidence → mobile/.e2e_artifacts/imm_* + IMMEDIATE_MAP_PHYSICAL_REPORT.json (written by agent).
Does NOT log API keys, tokens, or precise lat/lng.
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
PREFIX = "imm"
PARTIAL = ART / "immediate_map_physical_partial.json"


def adb(*args: str, check: bool = True) -> str:
    p = subprocess.run(
        ["adb", "-s", SERIAL, *args], capture_output=True, text=True, check=False
    )
    if check and p.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)}: {(p.stderr or '')[:400]}")
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


def tap_desc_startswith(xml: str, prefix: str) -> bool:
    p = prefix.lower()
    for text, desc, bounds in _nodes(xml):
        for hay in (text, desc):
            if hay.lower().startswith(p):
                c = bounds_center(bounds)
                if c:
                    tap_xy(*c)
                    return True
    return False


def edit_bounds(xml: str) -> list[str]:
    edits: list[str] = []
    for m in re.finditer(r"<node\b([^>]*)/?>", xml):
        attrs = m.group(1)
        if 'class="android.widget.EditText"' not in attrs and "EditText" not in attrs:
            continue
        bm = re.search(r'bounds="(\[\d+,\d+\]\[\d+,\d+\])"', attrs)
        if bm:
            edits.append(bm.group(1))
    return edits


def type_text(s: str) -> None:
    # Escape spaces for `input text`
    escaped = s.replace(" ", "%s")
    adb("shell", "input", "text", escaped, check=False)


def clear_field() -> None:
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END", check=False)
    for _ in range(40):
        adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)


def interesting_labels(xml: str) -> list[str]:
    keys = (
        "map",
        "where",
        "pickup",
        "destination",
        "continue",
        "confirm",
        "offer",
        "fare",
        "rs",
        "km",
        "min",
        "expand",
        "collapse",
        "3d",
        "liberty",
        "izmir",
        "loading",
        "unavailable",
        "preview",
        "select a ride",
        "request",
    )
    out: list[str] = []
    for text, desc, _ in _nodes(xml):
        blob = f"{text} | {desc}".strip(" |")
        if not blob:
            continue
        low = blob.lower()
        if any(k in low for k in keys):
            out.append(blob[:160])
    return out[:80]


def main() -> int:
    evidence: list[str] = []
    checks: dict[str, object] = {}
    notes: list[str] = []
    started = datetime.now(timezone.utc).isoformat()

    adb("shell", "am", "force-stop", PKG)
    time.sleep(0.5)
    adb(
        "shell",
        "monkey",
        "-p",
        PKG,
        "-c",
        "android.intent.category.LAUNCHER",
        "1",
        check=False,
    )
    time.sleep(5)

    xml = ""
    for i in range(20):
        xml = dump_ui(f"{PREFIX}_boot_{i}.xml")
        if has_label(xml, "Where are you headed") or has_label(xml, "Expand map"):
            break
        time.sleep(1)
    screenshot(f"{PREFIX}_boot.png")
    evidence.extend([f"{PREFIX}_boot.png"])

    if not has_label(xml, "Expand map"):
        if not tap_label(xml, "Where are you headed"):
            notes.append("Could not open Where are you headed")
            checks["rideRequestOpened"] = False
        else:
            time.sleep(2.5)
            for j in range(12):
                xml = dump_ui(f"{PREFIX}_nav_{j}.xml")
                if has_label(xml, "Expand map") or has_label(xml, "Where to?"):
                    break
                time.sleep(1)

    on_request = has_label(xml, "Expand map") or (
        has_label(xml, "Where to?") and has_label(xml, "Pickup")
    )
    checks["rideRequestOpened"] = on_request
    screenshot(f"{PREFIX}_01_idle_compose.png")
    dump_ui(f"{PREFIX}_01_idle_compose.xml")
    evidence.extend([f"{PREFIX}_01_idle_compose.png", f"{PREFIX}_01_idle_compose.xml"])
    idle_labels = interesting_labels(xml if on_request else dump_ui(f"{PREFIX}_01_idle_compose.xml"))
    checks["idleMapShellAbsent"] = not any(
        "map preview" in x.lower() and "unavailable" not in x.lower()
        for x in idle_labels
    )
    # Live map: expand control present; placeholder "Map preview" title absent as sole surface.
    checks["idleHasExpandChrome"] = has_label(
        dump_ui(f"{PREFIX}_01_idle_compose.xml"), "Expand map"
    )
    checks["idleStatusChip"] = has_label(
        dump_ui(f"{PREFIX}_01_idle_compose.xml"), "Confirm pickup"
    ) or has_label(dump_ui(f"{PREFIX}_01_idle_compose.xml"), "destination to continue")

    # GPS pickup
    xml = dump_ui(f"{PREFIX}_pre_gps.xml")
    if has_label(xml, "Use current location"):
        tap_label(xml, "Use current location")
        time.sleep(4)
        xml = dump_ui(f"{PREFIX}_gps.xml")
        for _ in range(8):
            if tap_desc_startswith(xml, "Confirm pickup") or tap_label(
                xml, "Confirm pickup | Confirm pickup"
            ):
                time.sleep(2)
                break
            # Exact-ish: avoid map status chip
            tapped = False
            for text, desc, bounds in _nodes(xml):
                hay = f"{text}\n{desc}"
                if hay.startswith("Confirm pickup") or desc.startswith("Confirm pickup"):
                    c = bounds_center(bounds)
                    if c:
                        tap_xy(*c)
                        tapped = True
                        break
            if tapped:
                time.sleep(2)
                break
            time.sleep(0.8)
            xml = dump_ui(f"{PREFIX}_gps_confirm.xml")
    else:
        notes.append("Use current location not found")

    xml = dump_ui(f"{PREFIX}_02_pickup.xml")
    screenshot(f"{PREFIX}_02_pickup.png")
    evidence.extend([f"{PREFIX}_02_pickup.png", f"{PREFIX}_02_pickup.xml"])
    checks["pickupResolved"] = has_label(xml, "Pickup set") or has_label(
        xml, "Pickup confirmed"
    ) or has_label(xml, "Izmir") or has_label(xml, "Current location")
    checks["pickupLabels"] = interesting_labels(xml)[:25]

    # Destination
    edits = edit_bounds(xml)
    if edits:
        c = bounds_center(edits[-1])
        if c:
            tap_xy(*c)
    else:
        tap_xy(540, 1950)
    time.sleep(0.5)
    clear_field()
    type_text("Liberty Market Lahore")
    time.sleep(6)
    xml = dump_ui(f"{PREFIX}_sugg.xml")
    screenshot(f"{PREFIX}_sugg.png")
    evidence.extend([f"{PREFIX}_sugg.png", f"{PREFIX}_sugg.xml"])
    tapped_tip = False
    for tip in ("Liberty Market Gulberg", "Liberty Market", "Gulberg", "Liberty"):
        if tap_label(xml, tip):
            tapped_tip = True
            time.sleep(2)
            break
    checks["destinationSuggestionTapped"] = tapped_tip
    if not tapped_tip:
        notes.append("No Liberty/Gulberg suggestion tapped")

    for i in range(10):
        xml = dump_ui(f"{PREFIX}_prop_{i}.xml")
        if tap_desc_startswith(xml, "Confirm destination") or tap_label(
            xml, "Confirm destination"
        ):
            time.sleep(2.5)
            break
        adb(
            "shell",
            "input",
            "swipe",
            "540",
            "1700",
            "540",
            "1100",
            "350",
            check=False,
        )
        time.sleep(0.8)
    else:
        notes.append("Confirm destination not found")

    # Wait for pricing / dual-point map
    for i in range(20):
        xml = dump_ui(f"{PREFIX}_route_wait_{i}.xml")
        if (
            has_label(xml, "Continue")
            and (
                has_label(xml, "confirmed")
                or has_label(xml, "Loading route")
                or has_label(xml, "Pickup & destination")
            )
        ):
            break
        time.sleep(1)

    # Continue to review if needed for fare; but first capture compact route map
    xml = dump_ui(f"{PREFIX}_03_compact_route.xml")
    screenshot(f"{PREFIX}_03_compact_route.png")
    evidence.extend(
        [f"{PREFIX}_03_compact_route.png", f"{PREFIX}_03_compact_route.xml"]
    )
    checks["compactRouteLabels"] = interesting_labels(xml)[:30]

    # Expand
    if tap_label(xml, "Expand map"):
        time.sleep(1.5)
        xml = dump_ui(f"{PREFIX}_04_expanded.xml")
        screenshot(f"{PREFIX}_04_expanded.png")
        evidence.extend([f"{PREFIX}_04_expanded.png", f"{PREFIX}_04_expanded.xml"])
        checks["expanded"] = has_label(xml, "Collapse map") or not has_label(
            xml, "Where to?"
        )
        # Toggle 3D / layers if present
        if tap_label(xml, "3D"):
            time.sleep(1.0)
            screenshot(f"{PREFIX}_05_3d_toggle.png")
            evidence.append(f"{PREFIX}_05_3d_toggle.png")
            checks["toggled3d"] = True
        else:
            # tooltip may be content-desc
            tapped3d = False
            for text, desc, bounds in _nodes(xml):
                if "3d" in f"{text}{desc}".lower():
                    c = bounds_center(bounds)
                    if c:
                        tap_xy(*c)
                        tapped3d = True
                        break
            checks["toggled3d"] = tapped3d
            if tapped3d:
                time.sleep(1.0)
                screenshot(f"{PREFIX}_05_3d_toggle.png")
                evidence.append(f"{PREFIX}_05_3d_toggle.png")

        xml = dump_ui(f"{PREFIX}_05b_layers.xml")
        tapped_layers = False
        for text, desc, bounds in _nodes(xml):
            hay = f"{text}{desc}".lower()
            if "layer" in hay or "building" in hay:
                c = bounds_center(bounds)
                if c:
                    tap_xy(*c)
                    tapped_layers = True
                    break
        checks["toggledLayers"] = tapped_layers
        if tapped_layers:
            time.sleep(1.0)
            screenshot(f"{PREFIX}_06_layers_toggle.png")
            evidence.append(f"{PREFIX}_06_layers_toggle.png")

        # Collapse
        xml = dump_ui(f"{PREFIX}_pre_collapse.xml")
        if tap_label(xml, "Collapse map") or tap_label(xml, "Close"):
            time.sleep(1.2)
        else:
            adb("shell", "input", "keyevent", "KEYCODE_BACK", check=False)
            time.sleep(1.2)
        xml = dump_ui(f"{PREFIX}_07_collapsed.xml")
        screenshot(f"{PREFIX}_07_collapsed.png")
        evidence.extend([f"{PREFIX}_07_collapsed.png", f"{PREFIX}_07_collapsed.xml"])
        checks["collapsedBackToSheet"] = has_label(xml, "Where to?") or has_label(
            xml, "Select a ride"
        ) or has_label(xml, "Continue")
    else:
        notes.append("Expand map not tappable")
        checks["expanded"] = False

    # Continue → review / fare
    xml = dump_ui(f"{PREFIX}_pre_continue.xml")
    if tap_label(xml, "Continue"):
        time.sleep(3.0)
    for i in range(20):
        xml = dump_ui(f"{PREFIX}_review_{i}.xml")
        if (
            has_label(xml, "Your offer")
            or has_label(xml, "Estimated fare")
            or has_label(xml, "Select a ride")
            or has_label(xml, "Offer range")
            or has_label(xml, "Request")
        ):
            break
        if tap_label(xml, "Continue"):
            time.sleep(2.0)
        time.sleep(1.0)
    screenshot(f"{PREFIX}_08_review_fare.png")
    dump_ui(f"{PREFIX}_08_review_fare.xml")
    evidence.extend([f"{PREFIX}_08_review_fare.png", f"{PREFIX}_08_review_fare.xml"])
    xml = dump_ui(f"{PREFIX}_08_review_fare.xml")
    checks["reviewFareLabels"] = interesting_labels(xml)[:40]
    checks["fareVisible"] = any(
        k in " ".join(interesting_labels(xml)).lower()
        for k in ("rs", "fare", "offer", "pkr")
    )
    checks["reviewChrome"] = (
        has_label(xml, "Your offer")
        or has_label(xml, "Estimated fare")
        or has_label(xml, "Select a ride")
        or has_label(xml, "Offer range")
    )

    # Attribution presence (info control) — soft check via prior expanded shot notes
    checks["notes"] = notes
    partial = {
        "artifact": "immediate_map_physical_partial",
        "startedAtUtc": started,
        "completedAtUtc": datetime.now(timezone.utc).isoformat(),
        "device": {"serial": SERIAL, "package": PKG},
        "checks": checks,
        "evidence": evidence,
        "notes": notes,
    }
    PARTIAL.write_text(json.dumps(partial, indent=2), encoding="utf-8")
    print(json.dumps({"ok": True, "partial": str(PARTIAL), "checks": checks}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
