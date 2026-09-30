#!/usr/bin/env python3
"""D1 notification tap physical verification (Samsung driver device)."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

D = os.environ.get("ORA_E2E_DRIVER", "RF8R40ZQ1JH")
PKG = "com.ora.ora"
TARGET_RIDE = os.environ.get(
    "ORA_D1_TARGET_RIDE", "762867a3-e4ac-42e1-890a-284740b5b2ce"
)
RIDE_PREFIX = TARGET_RIDE.split("-")[0]
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
REPORT: Dict[str, Any] = {
    "targetRideId": TARGET_RIDE,
    "device": D,
    "startedAt": datetime.now(timezone.utc).isoformat(),
    "gates": {},
}


def adb(*args: str) -> str:
    return subprocess.check_output(
        ["adb", "-s", D, *args], stderr=subprocess.STDOUT, timeout=120
    ).decode("utf-8", errors="replace")


def shell(*args: str) -> None:
    subprocess.check_call(["adb", "-s", D, "shell", *args], timeout=120)


def save_text(name: str, text: str) -> str:
    path = f"{ART}/{name}"
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    REPORT.setdefault("artifacts", []).append(path)
    return path


def dump_ui(tag: str) -> str:
    path = f"{ART}/d1_tap_{tag}.xml"
    for attempt in range(5):
        try:
            shell("uiautomator", "dump", "/sdcard/d1_tap_ui.xml")
            subprocess.check_call(
                ["adb", "-s", D, "pull", "/sdcard/d1_tap_ui.xml", path],
                stderr=subprocess.DEVNULL,
                timeout=30,
            )
            return open(path, encoding="utf-8").read()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            time.sleep(1 + attempt)
    raise RuntimeError(f"uiautomator dump failed tag={tag}")


def parse_nodes(xml: str) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for m in re.finditer(r"<node ([^>]+)>", xml):
        a = m.group(1)

        def g(n: str) -> str:
            mm = re.search(rf'{n}="([^"]*)"', a)
            return mm.group(1) if mm else ""

        b = g("bounds")
        bm = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", b)
        if not bm:
            continue
        x1, y1, x2, y2 = map(int, bm.groups())
        out.append(
            {
                "text": g("text"),
                "desc": g("content-desc").replace("&#10;", " "),
                "clickable": g("clickable") == "true",
                "package": g("package"),
                "rid": g("resource-id"),
                "bounds": (x1, y1, x2, y2),
                "cx": (x1 + x2) // 2,
                "cy": (y1 + y2) // 2,
            }
        )
    return out


def notification_dumpsys() -> str:
    return adb("shell", "dumpsys", "notification", "--noredact")


def notification_exists(dump: str) -> bool:
    return PKG in dump and "New ride request" in dump and "android.title=String (New ride request)" in dump


def ora_notification_rows(shade_xml: str) -> List[Dict[str, Any]]:
    nodes = parse_nodes(shade_xml)
    rows = [
        n
        for n in nodes
        if n["rid"] == "com.android.systemui:id/expandableNotificationRow"
        and n["clickable"]
    ]
    title_ys: List[int] = []
    for n in nodes:
        blob = n["text"] + n["desc"]
        if "New ride request" in blob:
            title_ys.append(n["cy"])
    ora_rows: List[Dict[str, Any]] = []
    for y in title_ys:
        for row in rows:
            x1, y1, x2, y2 = row["bounds"]
            if y1 <= y <= y2:
                ora_rows.append({**row, "markers": ["New ride request"]})
                break
    return ora_rows


def count_ora_dispatch_notifications(dump: str) -> int:
    return dump.count("android.title=String (New ride request)")


def expand_shade() -> None:
    shell("cmd", "statusbar", "expand-notifications")
    time.sleep(2)


def collapse_shade() -> None:
    subprocess.run(
        ["adb", "-s", D, "shell", "cmd", "statusbar", "collapse"],
        check=False,
        capture_output=True,
    )
    time.sleep(1)


def top_resumed_package() -> str:
    out = adb("shell", "dumpsys", "activity", "activities")
    m = re.search(r"topResumedActivity=ActivityRecord\{[^ ]+ [^ ]+ ([^/]+)/", out)
    if m:
        return m.group(1)
    m2 = re.search(r"mResumedActivity: ActivityRecord\{[^ ]+ [^ ]+ ([^/]+)/", out)
    return m2.group(1) if m2 else ""


def driver_open_rides_visible(xml: str) -> bool:
    if PKG not in xml and "com.ora.ora" not in xml:
        # uiautomator uses package attr on nodes
        pkgs = {n["package"] for n in parse_nodes(xml)}
        if PKG not in pkgs:
            return False
    markers = (
        "Open rides",
        "Open ride requests",
        "Ride request",
        "Available ride requests",
    )
    return any(m in xml for m in markers)


def ride_visible_in_ui(xml: str) -> bool:
    if RIDE_PREFIX in xml or TARGET_RIDE in xml:
        return True
    markers = ("Liberty Market", "Liberty", "Gulberg")
    return any(m in xml for m in markers)


def fetch_open_rides_api() -> Dict[str, Any]:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [
            f"{BACKEND}/node_modules/.bin/tsx",
            f"{BACKEND}/scripts/d1_driver_open_rides_check.ts",
            TARGET_RIDE,
        ],
        cwd=BACKEND,
        env=env,
        text=True,
        timeout=90,
    )
    return json.loads(out.strip())


def count_offer_sheets(xml: str) -> int:
    return xml.count("Submit offer") + xml.count("Accept passenger price")


def main() -> None:
    st = adb("get-state").strip()
    if st != "device":
        REPORT["gates"]["notification_exists"] = "BLOCKED"
        REPORT["fail"] = f"adb state={st}"
        write_report()
        sys.exit(2)

    before_dump = notification_dumpsys()
    save_text("d1_tap_before_dumpsys_snippet.txt", before_dump[-12000:])
    before_count = count_ora_dispatch_notifications(before_dump)
    REPORT["ora_dispatch_notification_count_before"] = before_count
    REPORT["gates"]["notification_exists"] = (
        "PASS" if notification_exists(before_dump) else "BLOCKED"
    )
    if REPORT["gates"]["notification_exists"] == "BLOCKED":
        REPORT["fail"] = "No com.ora.ora New ride request in dumpsys"
        write_report()
        sys.exit(2)

    collapse_shade()
    shell("input", "keyevent", "KEYCODE_WAKEUP")
    time.sleep(1)
    expand_shade()
    shade_before = dump_ui("before_shade")
    ora_rows = ora_notification_rows(shade_before)
    REPORT["ora_notification_rows"] = len(ora_rows)
    if not ora_rows:
        REPORT["gates"]["notification_tap"] = "BLOCKED"
        REPORT["fail"] = "Notification text in dumpsys but no Ora row in shade UI"
        write_report()
        sys.exit(2)

    row = ora_rows[0]
    shell("input", "tap", str(row["cx"]), str(row["cy"]))
    time.sleep(6)
    collapse_shade()
    time.sleep(2)

    after_app = dump_ui("after_tap_app")
    top_pkg = top_resumed_package()
    REPORT["top_package_after_tap"] = top_pkg
    nav_ok = top_pkg == PKG and driver_open_rides_visible(after_app)
    REPORT["gates"]["navigation_driver_open_rides"] = "PASS" if nav_ok else "BLOCKED"

    try:
        api = fetch_open_rides_api()
        REPORT["open_rides_api"] = api
        api_hit = api.get("targetPresent") is True
    except Exception as e:
        REPORT["open_rides_api_error"] = str(e)
        api_hit = False

    ui_ride_id = TARGET_RIDE in after_app or RIDE_PREFIX in after_app
    ui_route = ride_visible_in_ui(after_app)
    REPORT["gates"]["target_ride_api_visible"] = "PASS" if api_hit else "BLOCKED"
    REPORT["gates"]["target_ride_ui_visible"] = "PASS" if ui_ride_id else "BLOCKED"
    REPORT["target_ride_ui_ride_id"] = ui_ride_id
    REPORT["target_ride_ui_route_markers"] = ui_route
    REPORT["target_ride_api"] = api_hit

    after_dump = notification_dumpsys()
    save_text("d1_tap_after_dumpsys_snippet.txt", after_dump[-8000:])
    after_count = count_ora_dispatch_notifications(after_dump)
    REPORT["ora_dispatch_notification_count_after_tap"] = after_count

    # Duplicate tap safety: second tap only if the same notification remains.
    expand_shade()
    shade_dup = dump_ui("before_dup_tap")
    rows_dup = ora_notification_rows(shade_dup)
    dup_tap_ok = False
    dup_note = ""
    if rows_dup:
        shell("input", "tap", str(rows_dup[0]["cx"]), str(rows_dup[0]["cy"]))
        time.sleep(4)
        collapse_shade()
        dup_xml = dump_ui("after_dup_tap")
        sheets = count_offer_sheets(dup_xml)
        still_nav = driver_open_rides_visible(dup_xml) and top_resumed_package() == PKG
        dup_tap_ok = still_nav and sheets == 0
        REPORT["duplicate_offer_sheet_count"] = sheets
        dup_note = "second_shade_tap"
    else:
        collapse_shade()
        dup_xml = dump_ui("after_dup_tap")
        still_nav = driver_open_rides_visible(dup_xml) and top_resumed_package() == PKG
        sheets = count_offer_sheets(dup_xml)
        dup_tap_ok = still_nav and sheets == 0 and after_count <= before_count
        REPORT["duplicate_offer_sheet_count"] = sheets
        dup_note = "notification_cleared_after_first_tap"
    REPORT["duplicate_safety_note"] = dup_note
    REPORT["gates"]["duplicate_safety"] = "PASS" if dup_tap_ok else "BLOCKED"

    REPORT["gates"]["notification_tap"] = (
        "PASS" if nav_ok else "BLOCKED"
    )

    write_report()
    print(json.dumps(REPORT["gates"], indent=2))
    blocked = [k for k, v in REPORT["gates"].items() if v == "BLOCKED"]
    sys.exit(0 if not blocked else 1)


def write_report() -> None:
    REPORT["finishedAt"] = datetime.now(timezone.utc).isoformat()
    path = f"{ART}/d1_notification_tap_physical_verify_report.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(REPORT, f, indent=2)
    md = f"{ART}/D1_NOTIFICATION_TAP_PHYSICAL_PROOF.md"
    g = REPORT["gates"]
    with open(md, "w", encoding="utf-8") as f:
        f.write("# D1 notification tap — physical proof\n\n")
        f.write(f"**Device:** `{D}` · **Target ride:** `{TARGET_RIDE}`\n\n")
        f.write(f"**Started:** {REPORT.get('startedAt')} · **Finished:** {REPORT.get('finishedAt')}\n\n")
        f.write("| Gate | Result |\n|------|--------|\n")
        for key in (
            "notification_exists",
            "notification_tap",
            "navigation_driver_open_rides",
            "target_ride_api_visible",
            "target_ride_ui_visible",
            "duplicate_safety",
        ):
            f.write(f"| {key.replace('_', ' ')} | **{g.get(key, '—')}** |\n")
        f.write("\n## Artifacts\n\n")
        for p in REPORT.get("artifacts", []):
            f.write(f"- `{p}`\n")
        for suffix in (
            "d1_tap_before_shade.xml",
            "d1_tap_after_tap_app.xml",
            "d1_tap_before_dup_tap.xml",
            "d1_tap_after_dup_tap.xml",
        ):
            fp = f"{ART}/{suffix}"
            if os.path.isfile(fp):
                f.write(f"- `{fp}`\n")
        if REPORT.get("fail"):
            f.write(f"\n**Note:** {REPORT['fail']}\n")
        if REPORT.get("open_rides_api"):
            f.write(f"\n**API revalidation:** `{json.dumps(REPORT['open_rides_api'])}`\n")
    print("WROTE", path, md)


if __name__ == "__main__":
    main()
