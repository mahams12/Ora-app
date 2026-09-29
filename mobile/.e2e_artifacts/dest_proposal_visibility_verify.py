#!/usr/bin/env python3
"""Bounded physical verify: destination Confirm proposal visibility fix."""
from __future__ import annotations

import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
PKG = "com.ora.ora"
ART = Path(__file__).resolve().parent


@dataclass
class UiNode:
    cls: str
    text: str
    desc: str
    bounds: str
    clickable: str
    enabled: str

    @property
    def center(self) -> tuple[int, int]:
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", self.bounds)
        if not m:
            return (540, 1200)
        x1, y1, x2, y2 = map(int, m.groups())
        return ((x1 + x2) // 2, (y1 + y2) // 2)


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEVICE, *args])


def dump(name: str) -> str:
    remote = f"/sdcard/{name}"
    local = ART / name
    for attempt in range(5):
        try:
            subprocess.check_call(
                ["adb", "-s", DEVICE, "shell", "uiautomator", "dump", remote],
                timeout=45,
            )
            subprocess.check_call(
                ["adb", "-s", DEVICE, "pull", remote, str(local)],
                timeout=30,
            )
            return local.read_text(encoding="utf-8")
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            time.sleep(1 + attempt)
    raise RuntimeError(f"uiautomator dump failed: {name}")


def parse_nodes(xml: str) -> list[UiNode]:
    root = ET.fromstring(xml)
    out: list[UiNode] = []
    for n in root.iter("node"):
        out.append(
            UiNode(
                cls=n.get("class") or "",
                text=n.get("text") or "",
                desc=n.get("content-desc") or "",
                bounds=n.get("bounds") or "",
                clickable=n.get("clickable") or "",
                enabled=n.get("enabled") or "",
            )
        )
    return out


def find_button(nodes: list[UiNode], needle: str) -> Optional[UiNode]:
    for n in nodes:
        if "Button" not in n.cls:
            continue
        blob = f"{n.text}\n{n.desc}".replace("&#10;", "\n")
        if needle.lower() in blob.lower():
            return n
    return None


def tap_node(n: UiNode) -> None:
    x, y = n.center
    adb("shell", "input", "tap", str(x), str(y))


def tap_desc_substring(xml: str, needle: str) -> bool:
    for n in parse_nodes(xml):
        blob = f"{n.text}\n{n.desc}"
        if needle.lower() in blob.lower() and n.clickable == "true":
            tap_node(n)
            return True
    return False


def wait_button(needle: str, tries: int = 30, pause: float = 2.0) -> tuple[str, UiNode]:
    for i in range(tries):
        xml = dump(f"dest_vis_wait_{needle.replace(' ', '_')}_{i}.xml")
        btn = find_button(parse_nodes(xml), needle)
        if btn is not None:
            return xml, btn
        time.sleep(pause)
    raise RuntimeError(f"Button not found: {needle}")


def location_prep() -> None:
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION")
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION")
    adb("shell", "settings", "put", "secure", "location_mode", "3")
    subprocess.call(["adb", "-s", DEVICE, "emu", "geo", "fix", "74.3587", "31.5204"])


def ensure_composer() -> None:
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(5)
    for _ in range(8):
        xml = dump("dest_vis_boot.xml")
        if "Signing you in" in xml:
            tap_desc_substring(xml, "Try again")
            time.sleep(6)
            continue
        if "Send code" in xml or "Phone number" in xml:
            for n in parse_nodes(xml):
                if n.cls == "android.widget.EditText":
                    tap_node(n)
                    break
            adb("shell", "input", "text", "923012345678")
            time.sleep(1)
            tap_desc_substring(dump("dest_vis_send.xml"), "Send code") or adb(
                "shell", "input", "tap", "640", "1500"
            )
            time.sleep(6)
            adb("shell", "input", "text", "123456")
            time.sleep(1)
            tap_desc_substring(dump("dest_vis_otp.xml"), "Verify")
            time.sleep(10)
            continue
        if "Turn on" in xml and "com.google.android.gms" in xml:
            tap_desc_substring(xml, "Turn on")
            time.sleep(3)
            continue
        if "Where are you headed" in xml or "Where to?" in xml:
            tap_desc_substring(xml, "Where are you headed") or tap_desc_substring(
                xml, "Easy"
            )
            time.sleep(3)
            return
        if "Where to?" in xml:
            return
        time.sleep(2)
    xml = dump("dest_vis_compose_open.xml")
    if "Where to?" not in xml:
        adb("shell", "input", "tap", "540", "400")
        time.sleep(3)


def main() -> int:
    print("DEVICE", DEVICE)
    location_prep()
    ensure_composer()
    xml = dump("dest_vis_compose.xml")
    if "Where to?" not in xml:
        print("BLOCKED: trip composer not open")
        return 2

    if tap_desc_substring(xml, "Turn on"):
        time.sleep(3)
        xml = dump("dest_vis_after_gms.xml")

    tap_desc_substring(xml, "Use current location")
    time.sleep(5)
    xml = dump("dest_vis_after_gps.xml")

    pickup_btn = find_button(parse_nodes(xml), "Confirm pickup")
    if pickup_btn is None:
        xml, pickup_btn = wait_button("Confirm pickup", tries=15)
    print("PICKUP_CONFIRM_BTN", pickup_btn)
    tap_node(pickup_btn)
    time.sleep(3)
    xml = dump("dest_vis_after_pickup_confirm.xml")

    dest_field: Optional[UiNode] = None
    for n in parse_nodes(xml):
        if n.cls == "android.widget.EditText" and "Liberty" not in n.text:
            if n.text.strip() == "" or "location" in n.text.lower() or n == parse_nodes(xml)[-1]:
                pass
    edits = [n for n in parse_nodes(xml) if n.cls == "android.widget.EditText"]
    dest_field = edits[-1] if edits else None
    if dest_field is None:
        print("FAIL: no destination EditText")
        return 1
    tap_node(dest_field)
    time.sleep(1)
    for _ in range(40):
        adb("shell", "input", "keyevent", "KEYCODE_DEL")
    adb("shell", "input", "text", "Liberty%sMarket%sLahore")
    time.sleep(5)
    xml = dump("dest_vis_autocomplete.xml")
    if not tap_desc_substring(xml, "Gulberg III"):
        tap_desc_substring(xml, "Liberty Market Gulberg")
    time.sleep(6)
    xml = dump("dest_vis_after_select_before_confirm.xml")

    nodes = parse_nodes(xml)
    place_line = [n for n in nodes if "Place search ·" in f"{n.text}{n.desc}"]
    print("PLACE_SEARCH_NODES", len(place_line))

    dest_btn = find_button(nodes, "Confirm destination")
    if dest_btn is None:
        print("FAIL: Confirm destination Button not in hierarchy")
        for n in nodes:
            if "Confirm destination" in f"{n.text}{n.desc}":
                print("NON_BUTTON_MATCH", n)
        print("CONTINUE", find_button(nodes, "Continue"))
        return 1

    print("CONFIRM_DEST_BEFORE", dest_btn)
    continue_before = find_button(nodes, "Continue")
    print("CONTINUE_BEFORE", continue_before)

    tap_node(dest_btn)
    time.sleep(3)
    xml = dump("dest_vis_after_dest_confirm.xml")
    nodes_after = parse_nodes(xml)
    dest_btn_after = find_button(nodes_after, "Confirm destination")
    continue_after = find_button(nodes_after, "Continue")
    print("CONFIRM_DEST_AFTER", dest_btn_after)
    print("CONTINUE_AFTER", continue_after)

    if dest_btn_after is not None:
        print("FAIL: Confirm destination still present after tap")
        return 1
    if continue_after is None or continue_after.enabled != "true":
        print("FAIL: Continue not enabled after destination confirm")
        return 1
    if "confirmed" not in xml.lower() and "Destination confirmed" not in xml:
        print("WARN: destination confirmed chip/banner not matched in xml")

    print("RESULT PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
