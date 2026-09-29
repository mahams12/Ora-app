#!/usr/bin/env python3
"""Bounded physical ride create — Request Easy once on emulator."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

DEVICE = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
ART = Path(__file__).resolve().parent
LOG = ART / "backend_8080.log"
BACKEND = ART.parent.parent / "backend/auth-service"


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
            return (640, 2600)
        x1, y1, x2, y2 = map(int, m.groups())
        return ((x1 + x2) // 2, (y1 + y2) // 2)


def adb(*args: str) -> None:
    subprocess.check_call(["adb", "-s", DEVICE, *args])


def dump(name: str) -> str:
    remote = f"/sdcard/{name}"
    local = ART / name
    subprocess.check_call(
        ["adb", "-s", DEVICE, "shell", "uiautomator", "dump", remote],
        timeout=45,
    )
    subprocess.check_call(
        ["adb", "-s", DEVICE, "pull", remote, str(local)],
        timeout=30,
    )
    return local.read_text(encoding="utf-8")


def parse_nodes(xml: str) -> list[UiNode]:
    root = ET.fromstring(xml)
    return [
        UiNode(
            cls=n.get("class") or "",
            text=n.get("text") or "",
            desc=n.get("content-desc") or "",
            bounds=n.get("bounds") or "",
            clickable=n.get("clickable") or "",
            enabled=n.get("enabled") or "",
        )
        for n in root.iter("node")
    ]


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


def fetch_latest_rides() -> list[dict]:
    env = {**os.environ}
    sa = BACKEND / "secrets/service-account.json"
    env["GOOGLE_APPLICATION_CREDENTIALS"] = str(sa)
    out = subprocess.check_output(
        ["./node_modules/.bin/tsx", "scripts/e2e_fetch_latest_ride.ts"],
        cwd=str(BACKEND),
        env=env,
        text=True,
    )
    data = json.loads(out)
    return data.get("rides") or []


def ride_snapshot(ride_id: str) -> dict:
    env = {**os.environ}
    sa = BACKEND / "secrets/service-account.json"
    env["GOOGLE_APPLICATION_CREDENTIALS"] = str(sa)
    out = subprocess.check_output(
        ["./node_modules/.bin/tsx", "scripts/e2e_ride_snapshot.ts", ride_id],
        cwd=str(BACKEND),
        env=env,
        text=True,
    )
    return json.loads(out)


def log_after_marker(marker: str) -> list[str]:
    lines = LOG.read_text(encoding="utf-8").splitlines()
    post: list[str] = []
    seen = False
    for line in lines:
        if marker in line:
            seen = True
            continue
        if seen:
            post.append(line)
    return post


def main() -> int:
    before_rides = fetch_latest_rides()
    before_ids = {r["rideId"] for r in before_rides}
    print("RIDES_BEFORE_COUNT", len(before_rides))
    print("RIDES_BEFORE_IDS", sorted(before_ids)[:5])

    marker = f"=== RIDE_CREATE_BOUNDED_TEST {datetime.now(timezone.utc).isoformat()} ==="
    with LOG.open("a", encoding="utf-8") as f:
        f.write(marker + "\n")
    print("MARKER", marker)

    review_xml = dump("ride_create_review_before.xml")
    nodes = parse_nodes(review_xml)
    req = find_button(nodes, "Request Easy")
    print("REQUEST_EASY_BEFORE", req)
    if "Select a ride" not in review_xml and "Estimated fare" not in review_xml:
        print("BLOCKED: not on Review screen")
        return 2
    if req is None:
        print("FAIL: Request Easy button missing")
        return 1
    if req.enabled != "true" or req.clickable != "true":
        print("FAIL: Request Easy not enabled/clickable", req)
        return 1

    tap_node(req)
    print("TAPPED_REQUEST_EASY_ONCE", req.center)
    time.sleep(2)

    ui_xml = ""
    for i in range(30):
        ui_xml = dump(f"ride_create_after_submit_{i}.xml")
        blob = ui_xml.replace("&#10;", "\n")
        if "Waiting for offers" in blob or (
            "Offers" in blob and "Request Easy" not in blob
        ):
            break
        if "Request failed" in blob or "Could not load offers" in blob:
            print("FAIL: error UI after submit")
            print(blob[:2000])
            return 1
        if "Sending your request" in blob:
            time.sleep(2)
            continue
        time.sleep(2)

    blob = ui_xml.replace("&#10;", "\n")
    print(
        "UI_HINTS",
        {
            "waiting": "Waiting for offers" in blob,
            "offers": "Offers" in blob,
            "retry": "Retry" in blob or "failed" in blob.lower(),
        },
    )

    post_log = log_after_marker(marker)
    fails = [l for l in post_log if "ride_create_failed" in l]
    print("RIDE_CREATE_FAILED_LINES", fails)

    after_rides = fetch_latest_rides()
    new_rides = [r for r in after_rides if r["rideId"] not in before_ids]
    print("NEW_RIDES_COUNT", len(new_rides))
    print("NEW_RIDES", new_rides)

    if fails:
        print("FAIL: ride_create_failed in log", fails[-1])
        return 1
    if len(new_rides) != 1:
        print("FAIL: expected exactly 1 new ride", len(new_rides))
        return 1
    if "Waiting for offers" not in blob and not (
        "Offers" in blob and "Request Easy" not in blob
    ):
        print("FAIL: waiting-for-offers UI not shown")
        return 1

    ride_id = new_rides[0]["rideId"]
    snap = ride_snapshot(ride_id)
    ride = snap.get("ride") or {}
    print("FIRESTORE_SNAPSHOT", json.dumps(snap, indent=2)[:4000])

    now = datetime.now(timezone.utc)
    expires = ride.get("expiresAt")
    checks = {
        "state_SEARCHING": ride.get("state") == "SEARCHING",
        "assignedDriverId_null": ride.get("assignedDriverId") is None,
        "requestVersion_1": ride.get("requestVersion") == 1,
        "pricingSnapshotId_set": bool(ride.get("pricingSnapshotId")),
        "recommendedFareMinor_310": ride.get("recommendedFareMinor") == 31000,
        "passengerOfferMinor_310": ride.get("passengerOfferMinor") == 31000,
        "city_lahore": ride.get("city") == "lahore",
        "serviceType_ride": ride.get("serviceType") == "ride",
        "category_easy": ride.get("category") == "easy",
        "expires_future": expires and expires > now.isoformat().replace("+00:00", "Z"),
    }
    print("CHECKS", checks)
    if not all(checks.values()):
        print("FAIL: firestore checks", checks)
        return 1

    # duplicate: tap was once; idem should prevent dup — already checked count==1
    print("RIDE_ID", ride_id)
    print("PRICING_SNAPSHOT_ID", ride.get("pricingSnapshotId"))
    print("HTTP_EVIDENCE", "no ride_create_failed post-marker; create success inferred 201")
    print("RESULT PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
