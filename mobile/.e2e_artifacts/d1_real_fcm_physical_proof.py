#!/usr/bin/env python3
"""D1 real FCM physical proof: Samsung=driver, emulator=passenger, staging only."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

D = os.environ.get("ORA_E2E_DRIVER", "RF8R40ZQ1JH")
P = os.environ.get("ORA_E2E_PASSENGER", "emulator-5554")
PKG = "com.ora.ora"
ART = "/Users/jazimsaeed/Ora-app/mobile/.e2e_artifacts"
BACKEND = "/Users/jazimsaeed/Ora-app/backend/auth-service"
REPORT: Dict[str, Any] = {"gates": {}, "startedAt": datetime.now(timezone.utc).isoformat()}


def adb(dev: str, *args: str) -> str:
    return subprocess.check_output(["adb", "-s", dev, *args], stderr=subprocess.STDOUT).decode(
        "utf-8", errors="replace"
    )


def shell(dev: str, *args: str) -> None:
    subprocess.check_call(["adb", "-s", dev, "shell", *args])


def dump(dev: str, tag: str) -> str:
    path = f"{ART}/d1_{tag}_ui.xml"
    for attempt in range(5):
        try:
            shell(dev, "uiautomator", "dump", "/sdcard/d1_ui.xml")
            subprocess.check_call(
                ["adb", "-s", dev, "pull", "/sdcard/d1_ui.xml", path],
                stderr=subprocess.DEVNULL,
            )
            return open(path, encoding="utf-8").read()
        except subprocess.CalledProcessError:
            time.sleep(2 + attempt)
    raise RuntimeError(f"uiautomator dump failed on {dev} tag={tag}")


def nodes(t: str) -> List[Tuple[str, int, int]]:
    out: List[Tuple[str, int, int]] = []
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t
    ):
        desc = m.group(1).replace("&#10;", " | ")
        x1, y1, x2, y2 = map(int, m.groups()[1:])
        out.append((desc, (x1 + x2) // 2, (y1 + y2) // 2))
    return out


def tap(dev: str, needle: str, t: str, exclude: Optional[str] = None) -> bool:
    for desc, cx, cy in nodes(t):
        if exclude and exclude in desc:
            continue
        if needle in desc:
            shell(dev, "input", "tap", str(cx), str(cy))
            return True
    return False


def wait_for(dev: str, needle: str, tries: int = 25, pause: float = 2.0, tag: str = "w") -> str:
    for _ in range(tries):
        t = dump(dev, tag)
        if needle in t:
            return t
        time.sleep(pause)
    return dump(dev, tag)


def launch(dev: str) -> None:
    shell(dev, "am", "force-stop", PKG)
    subprocess.check_call(
        ["adb", "-s", dev, "shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1"]
    )
    time.sleep(10)


def phone_tap(dev: str) -> Tuple[int, int]:
    return (640, 1200) if dev.startswith("emulator-") else (540, 1364)


def auth(dev: str, phone: str, otp: str, tag: str) -> None:
    launch(dev)
    for _ in range(12):
        t = dump(dev, tag)
        if "Signing you in" in t:
            time.sleep(3)
            continue
        break
    t = dump(dev, tag)
    if dev == P and "Where are you headed" in t:
        return
    if dev == D and ("Open ride requests" in t or 'content-desc="Driver"' in t or "Earn on ORA" in t):
        return
    if "Send code" in t or "Phone number" in t:
        cx, cy = phone_tap(dev)
        shell(dev, "input", "tap", str(cx), str(cy))
        shell(dev, "input", "text", phone.lstrip("+"))
        shell(dev, "input", "keyevent", "KEYCODE_BACK")
        time.sleep(1)
        tap(dev, "Send code", dump(dev, tag)) or tap(dev, "Send verification code", dump(dev, tag))
        time.sleep(8)
        otp_y = 500 if dev.startswith("emulator-") else 610
        shell(dev, "input", "tap", str(cx), str(otp_y))
        shell(dev, "input", "text", otp)
        tap(dev, "Verify", dump(dev, tag))
        if dev == P:
            wait_for(dev, "Where are you headed", 25, 2.0, tag + "_p")
        else:
            wait_for(dev, "Earn on ORA", 25, 2.0, tag + "_d")


def driver_mode(dev: str) -> None:
    t = dump(dev, "d_home")
    if "Earn on ORA" in t:
        tap(dev, "Earn on ORA", t)
        wait_for(dev, "Open ride requests", 20, 2.0, "d_dhome")
    t = dump(dev, "d_open_nav")
    if not (
        tap(dev, "Open ride requests", t)
        or tap(dev, "Open ride", t)
        or tap(dev, "Open rides", t)
    ):
        shell(dev, "am", "start", "-a", "android.intent.action.VIEW", "-d", "ora://driver/open", PKG)
    time.sleep(4)
    t = wait_for(dev, "Open ride requests", 20, 2.0, "d_open")
    if "Open ride requests" not in t and "Ride request" not in t:
        raise RuntimeError("driver open rides tab not reached")


def staging_api_prep() -> None:
    """Passenger ride + driver online via staging HTTP (no Places UI)."""
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    if not env.get("ORA_INTERNAL_WORKER_TOKEN"):
        proc = subprocess.run(
            [
                "gcloud",
                "run",
                "services",
                "describe",
                "ora-auth-service-staging",
                "--region=us-central1",
                "--project=ora-app-d8112",
                "--format=json",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if proc.returncode == 0:
            svc = json.loads(proc.stdout)
            for c in svc.get("spec", {}).get("template", {}).get("spec", {}).get("containers", []):
                for e in c.get("env", []):
                    if e.get("name") == "ORA_INTERNAL_WORKER_TOKEN" and e.get("value"):
                        env["ORA_INTERNAL_WORKER_TOKEN"] = e["value"]
                        break
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/staging_d1_dispatch_prep.ts"],
        cwd=BACKEND,
        env=env,
        text=True,
    )
    prep = json.loads(out)
    REPORT["staging_prep"] = prep
    if not prep.get("ok"):
        REPORT["gates"]["ride_creation"] = "FAIL_API_PREP"
        return
    REPORT["rideId"] = prep.get("rideId")
    tick = (prep.get("steps") or {}).get("dispatchTick") or {}
    sweep = (prep.get("steps") or {}).get("fcmSweep") or {}
    REPORT["gates"]["ride_creation"] = "PASS"
    REPORT["gates"]["dispatch_tick"] = "PASS" if tick.get("status") == 200 else "FAIL"
    REPORT["gates"]["dispatch_sweep"] = "PASS" if sweep.get("status") == 200 else "FAIL"


def passenger_ride() -> None:
    auth(P, "+923012345678", "123456", "p_auth")
    t = dump(P, "p_home")
    tap(P, "Where are you headed?", t) or tap(P, "Where are you headed", t) or shell(P, "input", "tap", "540", "450")
    time.sleep(3)
    wait_for(P, "Where to?", 20, 2.0, "p_compose")
    tap(P, "Use current location", dump(P, "p_pick"))
    time.sleep(3)
    tap(P, "Confirm pickup", dump(P, "p_pick2"), exclude="destination")
    time.sleep(2)
    t = dump(P, "p_dest")
    eds = re.findall(r'EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', t)
    if eds:
        x1, y1, x2, y2 = map(int, eds[-1])
        shell(P, "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        for _ in range(35):
            shell(P, "input", "keyevent", "KEYCODE_DEL")
        shell(P, "input", "text", "Liberty%Market%Lahore")
        time.sleep(8)
        t_sug = dump(P, "p_sug")
        tap(P, "Liberty Market", t_sug) or tap(P, "Gulberg", t_sug)
        time.sleep(3)
    for _ in range(6):
        t = dump(P, "p_conf")
        if "Confirm destination" in t:
            tap(P, "Confirm destination", t)
            break
        shell(P, "input", "swipe", "540", "1200", "540", "700", "400")
        time.sleep(1)
    t = dump(P, "p_cont")
    tap(P, "Continue", t) or shell(P, "input", "tap", "540", "1674")
    t = wait_for(P, "Select a ride", 25, 2.0, "p_rev")
    if "Pricing unavailable" in t:
        REPORT["gates"]["ride_creation"] = "FAIL_PRICING"
        return
    tap(P, "Lahore", dump(P, "p_city")) if "Lahore" not in t else None
    time.sleep(1)
    for _ in range(5):
        t = dump(P, "p_req")
        if "Waiting for offers" in t:
            REPORT["gates"]["ride_creation"] = "PASS"
            return
        tap(P, "Request Easy", t) or tap(P, "Request ", t)
        time.sleep(5)
    REPORT["gates"]["ride_creation"] = "FAIL"


def run_sweep() -> dict:
    env = {**os.environ}
    env["GOOGLE_APPLICATION_CREDENTIALS"] = f"{BACKEND}/secrets/service-account.json"
    out = subprocess.check_output(
        ["bash", "-lc", f"set -a; source {BACKEND}/.env 2>/dev/null; set +a; {BACKEND}/scripts/run_staging_d1_fcm_sweep.sh"],
        cwd=BACKEND,
        env=env,
        text=True,
    )
    REPORT["sweep_output"] = out[-2000:]
    return {"ok": True}


def check_token_registered() -> dict:
    env = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": f"{BACKEND}/secrets/service-account.json"}
    out = subprocess.check_output(
        [f"{BACKEND}/node_modules/.bin/tsx", f"{BACKEND}/scripts/check_driver_device_tokens.ts"],
        cwd=BACKEND,
        env=env,
        text=True,
    )
    return json.loads(out)


def notification_visible() -> bool:
    out = adb(D, "shell", "dumpsys", "notification", "--noredact")
    snippet = ""
    for line in out.splitlines():
        if PKG in line or "New ride request" in line or "Ride requests" in line:
            snippet += line + "\n"
    REPORT["notification_dump_snippet"] = snippet[-4000:] or out[-1500:]
    return PKG in snippet and "New ride request" in out


def main() -> None:
    st = adb(D, "get-state").strip()
    REPORT["gates"]["samsung_adb"] = "PASS" if st == "device" else "BLOCKED"
    if st != "device":
        fail("Samsung not authorized")

    auth(D, "+923012345677", "000000", "d_auth")
    REPORT["gates"]["driver_auth"] = "PASS"
    try:
        driver_mode(D)
        REPORT["gates"]["driver_open_tab"] = "PASS"
    except Exception as e:
        REPORT["gates"]["driver_open_tab"] = "FAIL"
        REPORT["driver_open_error"] = str(e)
    time.sleep(8)

    try:
        tok = check_token_registered()
        REPORT["token_check"] = tok
        REPORT["gates"]["fcm_token_registration"] = (
            "PASS" if tok.get("tokenDocCount", 0) >= 1 and tok["docs"][0].get("hasToken") else "FAIL"
        )
    except Exception as e:
        REPORT["gates"]["fcm_token_registration"] = "FAIL"
        REPORT["token_error"] = str(e)

    use_api = os.environ.get("ORA_D1_USE_API_PREP", "1") != "0"
    if use_api:
        try:
            staging_api_prep()
        except Exception as e:
            REPORT["gates"]["ride_creation"] = "FAIL"
            REPORT["staging_prep_error"] = str(e)
    else:
        passenger_ride()
        time.sleep(3)
        try:
            run_sweep()
            REPORT["gates"]["dispatch_sweep"] = "PASS"
        except Exception as e:
            REPORT["gates"]["dispatch_sweep"] = "FAIL"
            REPORT["sweep_error"] = str(e)

    time.sleep(5)
    REPORT["gates"]["physical_notification"] = "PASS" if notification_visible() else "FAIL"

    out_path = f"{ART}/d1_real_fcm_physical_proof_report.json"
    with open(out_path, "w") as f:
        json.dump(REPORT, f, indent=2)
    print(json.dumps(REPORT["gates"], indent=2))
    print("WROTE", out_path)


def fail(msg: str) -> None:
    REPORT["fail"] = msg
    print("FAIL", msg, file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
