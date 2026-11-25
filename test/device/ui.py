#!/usr/bin/env python3
"""UI automation helper for ORA emulator demos — drives the REAL app UI via
adb uiautomator dumps (text/desc matching) + input taps. No app changes.

Usage:
  ui.py tap <serial> "Text or desc" [timeout_s]
  ui.py input <serial> "text"          (types into focused field)
  ui.py wait <serial> "Text" [timeout_s]  -> prints seconds waited, exit 1 on timeout
  ui.py exists <serial> "Text"
  ui.py back <serial>
  ui.py key <serial> <keycode|KEYCODE_...>
  ui.py shot <serial> /path/out.png
  ui.py dump <serial>
Match = exact text, exact content-desc, or substring if prefixed '~'.
"""
import re, subprocess, sys, time, urllib.parse
import xml.etree.ElementTree as ET

def adb(serial, *args, timeout=30):
    return subprocess.run(["adb", "-s", serial, *args], capture_output=True,
                          text=True, timeout=timeout).stdout

def ui_xml(serial, retries=3):
    for _ in range(retries):
        remote = "/sdcard/ui_dump.xml"
        adb(serial, "shell", "uiautomator", "dump", remote, timeout=30)
        xml = adb(serial, "shell", "cat", remote, timeout=30)
        if "<hierarchy" in xml:
            return xml
        time.sleep(0.5)
    return ""

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")

def find(serial, needle, substring=False):
    xml = ui_xml(serial)
    if not xml:
        return None
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return None
    for node in root.iter("node"):
        text = node.get("text") or ""
        desc = node.get("content-desc") or ""
        m = BOUNDS.search(node.get("bounds") or "")
        if not m:
            continue
        for field in (text, desc):
            if substring:
                if needle in field and field:
                    x = (int(m.group(1)) + int(m.group(3))) // 2
                    y = (int(m.group(2)) + int(m.group(4))) // 2
                    return (x, y, field)
            else:
                if field == needle:
                    x = (int(m.group(1)) + int(m.group(3))) // 2
                    y = (int(m.group(2)) + int(m.group(4))) // 2
                    return (x, y, field)
    return None

def cmd_tap(serial, needle, timeout=25):
    substring = needle.startswith("~")
    n = needle[1:] if substring else needle
    deadline = time.time() + timeout
    while time.time() < deadline:
        hit = find(serial, n, substring)
        if hit:
            adb(serial, "shell", "input", "tap", str(hit[0]), str(hit[1]))
            print(f"tap '{needle}' @({hit[0]},{hit[1]}) [{hit[2][:60]}]")
            return 0
        time.sleep(0.7)
    print(f"TIMEOUT tap '{needle}'", file=sys.stderr)
    return 1

def cmd_wait(serial, needle, timeout=60):
    substring = needle.startswith("~")
    n = needle[1:] if substring else needle
    t0 = time.time()
    while time.time() - t0 < timeout:
        if find(serial, n, substring):
            print(f"wait '{needle}': {time.time()-t0:.1f}s")
            return 0
        time.sleep(0.7)
    print(f"TIMEOUT wait '{needle}'", file=sys.stderr)
    return 1

def esc(s):
    return urllib.parse.quote(s, safe="")

def main():
    cmd, serial = sys.argv[1], sys.argv[2]
    if cmd == "tap":
        timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 25
        sys.exit(cmd_tap(serial, sys.argv[3], timeout))
    if cmd == "input":
        adb(serial, "shell", "input", "text", esc(sys.argv[3])); sys.exit(0)
    if cmd == "wait":
        timeout = float(sys.argv[4]) if len(sys.argv) > 4 else 60
        sys.exit(cmd_wait(serial, sys.argv[3], timeout))
    if cmd == "exists":
        n = sys.argv[3]
        substring = n.startswith("~")
        hit = find(serial, n[1:] if substring else n, substring)
        print("exists" if hit else "missing")
        sys.exit(0 if hit else 1)
    if cmd == "back":
        adb(serial, "shell", "input", "keyevent", "4"); sys.exit(0)
    if cmd == "key":
        adb(serial, "shell", "input", "keyevent", sys.argv[3]); sys.exit(0)
    if cmd == "shot":
        remote = "/sdcard/_shot.png"
        adb(serial, "shell", "screencap", "-p", remote)
        subprocess.run(["adb", "-s", serial, "pull", remote, sys.argv[3]],
                       capture_output=True)
        print(sys.argv[3]); sys.exit(0)
    if cmd == "dump":
        print(ui_xml(serial)); sys.exit(0)
    if cmd == "swipe":
        adb(serial, "shell", "input", "swipe", *sys.argv[3:7]); sys.exit(0)
    if cmd == "rawtap":
        adb(serial, "shell", "input", "tap", sys.argv[3], sys.argv[4]); sys.exit(0)
    print("unknown cmd", file=sys.stderr); sys.exit(2)

if __name__ == "__main__":
    main()
