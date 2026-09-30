#!/usr/bin/env python3
"""Physical verification: Respond semantics bounds + one tap opens offer sheet (no submit)."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

D = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
OLD_BOUNDS = (53, 622, 1028, 1546)
MARKER = f"=== RESPOND_HIT_TARGET_VERIFY {datetime.now(timezone.utc).isoformat()} ==="


def sh(*args: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", D, "shell", *args],
        stderr=subprocess.STDOUT,
        timeout=45,
    ).decode("utf-8", errors="replace")


def dump(tag: str) -> str:
    path = f"{ART}/rh_{tag}.xml"
    sh("uiautomator", "dump", "/sdcard/rh.xml")
    subprocess.check_call(["adb", "-s", D, "pull", "/sdcard/rh.xml", path], timeout=25)
    return path


def parse_nodes(path: str) -> list[dict]:
    t = open(path, encoding="utf-8").read()
    out: list[dict] = []
    for m in re.finditer(r"<node ([^/>]+)/?>", t):
        a = m.group(1)

        def g(n: str) -> str:
            mm = re.search(rf'{n}="([^"]*)"', a)
            return mm.group(1) if mm else ""

        b = g("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        out.append(
            {
                "class": g("class"),
                "desc": g("content-desc").replace("&#10;", "\n"),
                "text": g("text"),
                "clickable": g("clickable") == "true",
                "enabled": g("enabled") == "true",
                "bounds": tuple(map(int, bm.groups())),
            }
        )
    return out


def tap_node(n: dict) -> None:
    x1, y1, x2, y2 = n["bounds"]
    sh("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))


def tap_desc(t: str, needle: str, *, prefix: bool = False) -> bool:
    for n in parse_nodes(t):
        d = n["desc"]
        if prefix and not d.startswith(needle):
            continue
        if not prefix and needle not in d:
            continue
        if not n["clickable"]:
            continue
        tap_node(n)
        return True
    return False


def find_respond(nodes: list[dict]) -> dict | None:
    for n in nodes:
        if n["class"] != "android.widget.Button":
            continue
        blob = f"{n['desc']}\n{n['text']}"
        if "Respond to ride request" in blob or re.search(r"Respond", blob):
            return n
    return None


def bounds_height(b: tuple[int, int, int, int]) -> int:
    return b[3] - b[1]


def is_full_card_bounds(b: tuple[int, int, int, int]) -> bool:
    h = bounds_height(b)
    return h > 600 and b[0] <= OLD_BOUNDS[0] + 5 and b[2] >= OLD_BOUNDS[2] - 5


def ensure_driver_open_rides() -> tuple[str, list[dict]]:
    sh("input", "keyevent", "KEYCODE_WAKEUP")
    subprocess.check_call(
        ["adb", "-s", D, "shell", "am", "start", "-n", f"{PKG}/.MainActivity"],
        timeout=15,
    )
    time.sleep(6)
    list_path = ""
    nodes: list[dict] = []
    for i in range(10):
        list_path = dump(f"nav{i}")
        nodes = parse_nodes(list_path)
        blob = open(list_path, encoding="utf-8").read()
        if find_respond(nodes) and ("Passenger offer" in blob or "Ride request" in blob):
            return list_path, nodes
        if "Phone number" in blob or "Send verification code" in blob:
            eds = [n for n in nodes if n["class"] == "android.widget.EditText"]
            if eds:
                tap_node(eds[0])
            else:
                sh("input", "tap", "540", "1364")
            for _ in range(24):
                sh("input", "keyevent", "67")
            sh("input", "text", "923012345677")
            time.sleep(1)
            tap_desc(list_path, "Send code") or tap_desc(list_path, "Send verification code")
            time.sleep(10)
            sh("input", "tap", "540", "610")
            sh("input", "text", "000000")
            time.sleep(1)
            list_path = dump(f"auth{i}")
            tap_desc(list_path, "Verify", prefix=True)
            time.sleep(12)
            continue
        if tap_desc(list_path, "Earn on ORA"):
            time.sleep(4)
            continue
        if tap_desc(list_path, "Open ride requests", prefix=True) or tap_desc(
            list_path, "Open ride", prefix=True
        ):
            time.sleep(5)
            continue
        if tap_desc(list_path, "Menu"):
            time.sleep(2)
            drawer = dump(f"drawer{i}")
            if tap_desc(drawer, "Earn on ORA") or tap_desc(drawer, "Driver"):
                time.sleep(4)
                continue
            if tap_desc(drawer, "Open ride requests", prefix=True):
                time.sleep(5)
                continue
        time.sleep(2)
    list_path = dump("open_final")
    return list_path, parse_nodes(list_path)


def main() -> int:
    report = {
        "marker": MARKER,
        "device": D,
        "old_bounds": list(OLD_BOUNDS),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    print(MARKER)

    subprocess.check_call(["adb", "-s", D, "reverse", "tcp:8081", "tcp:8080"], timeout=10)
    report["adb_reverse"] = "tcp:8081 -> tcp:8080"

    list_path, nodes = ensure_driver_open_rides()
    report["list_xml"] = list_path

    respond = find_respond(nodes)
    if respond is None:
        report["verdict"] = "BLOCKED"
        report["reason"] = "no_respond_or_open_ride_on_screen"
        out = f"{ART}/respond_hit_target_verify_report.json"
        open(out, "w").write(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 2

    report["respond"] = {
        "class": respond["class"],
        "bounds": list(respond["bounds"]),
        "clickable": respond["clickable"],
        "enabled": respond["enabled"],
        "desc": respond["desc"][:120],
    }
    h = bounds_height(respond["bounds"])
    report["bounds_height"] = h
    report["full_card_like"] = is_full_card_bounds(respond["bounds"])

    if not respond["clickable"] or not respond["enabled"]:
        report["verdict"] = "FAIL"
        report["reason"] = "respond_not_clickable_or_enabled"
        out = f"{ART}/respond_hit_target_verify_report.json"
        open(out, "w").write(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
        return 1

    tap_node(respond)
    report["tapped_once"] = True
    time.sleep(3)
    sheet_path = dump("sheet")
    report["sheet_xml"] = sheet_path
    sheet_blob = open(sheet_path, encoding="utf-8").read()
    sheet_open = all(
        s in sheet_blob for s in ("Submit offer", "Accept passenger price", "Amount")
    )
    report["sheet_open"] = sheet_open

    if report["full_card_like"]:
        report["verdict"] = "FAIL"
        report["reason"] = "bounds_still_full_card"
    elif not sheet_open:
        report["verdict"] = "FAIL"
        report["reason"] = "tap_did_not_open_sheet"
    else:
        report["verdict"] = "PASS"

    out = f"{ART}/respond_hit_target_verify_report.json"
    open(out, "w").write(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    return 0 if report["verdict"] == "PASS" else 1 if report["verdict"] == "FAIL" else 2


if __name__ == "__main__":
    sys.exit(main())
