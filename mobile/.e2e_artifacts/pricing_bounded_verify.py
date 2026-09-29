#!/usr/bin/env python3
"""Bounded pricing physical verify — emulator Continue → Review."""
from __future__ import annotations

import json
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
            return (640, 1670)
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


def blob(xml: str) -> str:
    return xml.replace("&#10;", "\n")


def main() -> int:
    marker = f"=== PRICING_BOUNDED_TEST {datetime.now(timezone.utc).isoformat()} ==="
    log_lines_before = LOG.read_text(encoding="utf-8").count("\n") if LOG.exists() else 0
    with LOG.open("a", encoding="utf-8") as f:
        f.write(marker + "\n")
    print("MARKER", marker)
    print("LOG_FILE", LOG)
    print("LOG_LINES_BEFORE", log_lines_before)

    xml = dump("pricing_bounded_before_continue.xml")
    nodes = parse_nodes(xml)
    cont = find_button(nodes, "Continue")
    print("CONTINUE_BEFORE", cont)
    if cont is None:
        print("BLOCKED: Continue button not found")
        return 2
    if cont.enabled != "true" or cont.clickable != "true":
        print("BLOCKED: Continue not enabled", cont)
        return 2

    tap_node(cont)
    print("TAPPED_CONTINUE_ONCE", cont.center)
    time.sleep(2)

    review_xml = ""
    for i in range(25):
        review_xml = dump(f"pricing_bounded_review_wait_{i}.xml")
        b = blob(review_xml)
        if "Select a ride" in b or "Estimated fare" in b:
            break
        time.sleep(2)

    b = blob(review_xml)
    print("REVIEW_HINTS", {
        "select_a_ride": "Select a ride" in b,
        "estimated_fare": "Estimated fare" in b,
        "offer_range": "Offer range" in b or "–" in b,
        "request_easy": "Request Easy" in b,
        "retry_pricing": "Retry pricing" in b,
    })

    if "Select a ride" not in b and "Estimated fare" not in b:
        print("FAIL: Review not reached")
        return 1

    log_tail = LOG.read_text(encoding="utf-8").splitlines()
    post = []
    seen_marker = False
    for line in log_tail:
        if marker in line:
            seen_marker = True
            continue
        if seen_marker:
            post.append(line)

    begins = [json.loads(l) for l in post if "pricing_estimate_begin" in l]
    oks = [json.loads(l) for l in post if "pricing_estimate_ok" in l]
    fails = [json.loads(l) for l in post if "pricing_estimate_failed" in l]
    print("PRICING_BEGIN_COUNT", len(begins))
    print("PRICING_OK_COUNT", len(oks))
    print("PRICING_FAIL_COUNT", len(fails))
    if begins:
        print("PRICING_BEGIN_LAST", begins[-1])
    if oks:
        print("PRICING_OK_LAST", oks[-1])

    req_btn = find_button(parse_nodes(review_xml), "Request Easy")
    print("REQUEST_EASY_BTN", req_btn)

    for needle in ["Estimated fare", "Offer range", "km", "min", "Rs"]:
        print(f"UI_HAS_{needle}", needle in b)

    if not begins:
        print("FAIL: no pricing_estimate_begin after marker")
        return 1
    if fails and not oks:
        print("FAIL: pricing failed", fails[-1])
        return 1
    if not oks:
        print("FAIL: no pricing_estimate_ok after marker")
        return 1
    if req_btn is None:
        print("FAIL: Request Easy not found")
        return 1
    if req_btn.enabled != "true":
        print("FAIL: Request Easy not enabled")
        return 1

    print("RESULT PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
