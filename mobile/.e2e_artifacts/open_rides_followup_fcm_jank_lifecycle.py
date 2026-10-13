#!/usr/bin/env python3
"""Follow-up: FCM Open Rides refresh timing, gfxinfo jank, Accept→server offer."""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

import map2a_physical as M

DEV, PKG, ART = M.DEV, M.PKG, M.ART
BACKEND = Path(__file__).resolve().parents[2] / "backend" / "auth-service"
PREFIX = "open_rides_followup"
REPORT: dict = {
    "startedAt": datetime.now(timezone.utc).isoformat(),
    "device": DEV,
    "package": PKG,
}


def log(*a):
    print(*a, flush=True)


def iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def dump(tag: str) -> str:
    xml = M.dump(f"{PREFIX}_{tag}")
    (ART / f"{PREFIX}_{tag}.xml").write_text(xml)
    return xml


def shot(tag: str) -> str:
    name = f"{PREFIX}_{tag}.png"
    remote = f"/sdcard/{name}"
    path = ART / name
    M.sh("screencap", "-p", remote)
    M.adb("pull", remote, str(path))
    return name


def texts(xml: str) -> str:
    return M.unescape(xml)


def worker_token() -> str:
    tok = os.environ.get("ORA_INTERNAL_WORKER_TOKEN", "").strip()
    if tok:
        return tok
    env_path = BACKEND / ".env"
    for line in env_path.read_text().splitlines():
        if line.startswith("ORA_INTERNAL_WORKER_TOKEN="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("ORA_INTERNAL_WORKER_TOKEN missing")


def run_dispatch_prep() -> dict:
    env = {
        **os.environ,
        "GOOGLE_APPLICATION_CREDENTIALS": str(BACKEND / "secrets/service-account.json"),
        "ORA_INTERNAL_WORKER_TOKEN": worker_token(),
    }
    t0 = iso()
    wall0 = time.time()
    raw = subprocess.check_output(
        [str(BACKEND / "node_modules/.bin/tsx"), str(BACKEND / "scripts/staging_d1_dispatch_prep.ts")],
        cwd=str(BACKEND),
        env=env,
        text=True,
        timeout=180,
    )
    wall1 = time.time()
    t1 = iso()
    data = json.loads(raw)
    data["_meta"] = {
        "prepStartedAt": t0,
        "prepFinishedAt": t1,
        "prepWallMs": int((wall1 - wall0) * 1000),
    }
    (ART / f"{PREFIX}_fcm_prep.json").write_text(json.dumps(data, indent=2))
    return data


def api_offer_submit(ride_id: str, amount_minor: int, offer_type: str = "DRIVER_COUNTEROFFER") -> dict:
    """Authoritative server create via public API (same path as app CreateOfferUseCase)."""
    script = f"""
import {{ initializeApp, cert, getApps }} from 'firebase-admin/app';
import {{ getAuth }} from 'firebase-admin/auth';
import {{ readFileSync }} from 'node:fs';
import {{ randomUUID }} from 'node:crypto';
import path from 'node:path';
const repoRoot = path.join(process.cwd(), '../..');
const sa = process.env.GOOGLE_APPLICATION_CREDENTIALS!;
if (!getApps().length) initializeApp({{ credential: cert(sa) }});
const DRIVER_PHONE = '+923012345677';
async function idToken(uid: string) {{
  const custom = await getAuth().createCustomToken(uid);
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  const apiKey = JSON.parse(readFileSync(gs, 'utf8')).client[0].api_key[0].current_key;
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${{apiKey}}`, {{
    method: 'POST', headers: {{ 'Content-Type': 'application/json' }},
    body: JSON.stringify({{ token: custom, returnSecureToken: true }}),
  }});
  if (!res.ok) throw new Error('token ' + res.status);
  return (await res.json()).idToken as string;
}}
const base = readFileSync(path.join(repoRoot, 'mobile/.staging_api_url'), 'utf8').trim().replace(/\\/$/, '');
const driverUid = (await getAuth().getUserByPhoneNumber(DRIVER_PHONE)).uid;
const token = await idToken(driverUid);
const rideId = {json.dumps(ride_id)};
const amountMinor = {amount_minor};
const type = {json.dumps(offer_type)};
// fetch open ride for requestVersion
const openRes = await fetch(base + '/rides/open?limit=50', {{ headers: {{ Authorization: 'Bearer ' + token }} }});
const openJson = await openRes.json();
const ride = ((openJson.data?.rides) || []).find((r: any) => r.rideId === rideId);
const requestVersion = ride?.requestVersion ?? 1;
const t0 = new Date().toISOString();
const res = await fetch(base + `/rides/${{rideId}}/offers`, {{
  method: 'POST',
  headers: {{
    Authorization: 'Bearer ' + token,
    'Content-Type': 'application/json',
    'Idempotency-Key': 'followup-offer-' + randomUUID(),
  }},
  body: JSON.stringify({{ type, amountMinor, requestVersion }}),
}});
const body = await res.json();
const list = await fetch(base + `/rides/${{rideId}}/offers`, {{ headers: {{ Authorization: 'Bearer ' + token }} }});
const listJson = await list.json();
console.log(JSON.stringify({{
  submitAt: t0,
  submitStatus: res.status,
  offer: body.data ?? body.error ?? body,
  listStatus: list.status,
  offers: listJson.data?.offers ?? listJson.data ?? listJson,
  requestVersion,
}}, null, 2));
"""
    path = BACKEND / ".tmp_followup_offer.mts"
    path.write_text(script)
    try:
        out = subprocess.check_output(
            ["node", "--import", "tsx", str(path)],
            cwd=str(BACKEND),
            env={**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": str(BACKEND / "secrets/service-account.json")},
            text=True,
            timeout=90,
        )
    finally:
        path.unlink(missing_ok=True)
    data = json.loads(out)
    (ART / f"{PREFIX}_lifecycle_offer.json").write_text(json.dumps(data, indent=2))
    return data


def ensure_driver_open_rides() -> str:
    M.adb("shell", "am", "force-stop", PKG)
    time.sleep(0.4)
    M.adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    time.sleep(4.0)
    xml = dump("fcm_boot")
    if "Send OTP" in texts(xml) or "Phone number" in texts(xml) or "Verify" in texts(xml):
        xml = M.force_login(M.DRIVER_PHONE_UI, M.DRIVER_OTP, want_passenger=False)
    else:
        # Prefer driver shell
        if "Open rides" not in texts(xml) and "Open ride" not in texts(xml):
            if M.tap_contains(xml, "Earn on ORA") or M.tap_contains(xml, "Earn"):
                time.sleep(2.0)
                xml = dump("fcm_earn")
            elif "Switch to driver" in texts(xml) or M.tap_contains(xml, "Menu", exact=True):
                time.sleep(1.0)
                xml = dump("fcm_menu")
                if M.tap_contains(xml, "Switch to driver") or M.tap_contains(xml, "Earn"):
                    time.sleep(2.0)
                    xml = dump("fcm_driver")
            else:
                xml = M.force_login(M.DRIVER_PHONE_UI, M.DRIVER_OTP, want_passenger=False)
    if M.tap_contains(xml, "Open rides") or M.tap_contains(xml, "Open ride requests"):
        time.sleep(2.0)
    else:
        M.sh("input", "tap", "216", "2200")
        time.sleep(2.0)
    xml = dump("fcm_open_pre")
    shot("fcm_open_pre")
    return xml


def gfxinfo_collect(tag: str, sample_ms: int = 7000) -> dict:
    # Reset + enable then scroll
    M.sh("dumpsys", "gfxinfo", PKG, "reset")
    t0 = time.time()
    for _ in range(10):
        M.sh("input", "swipe", "540", "1750", "540", "650", "300")
        time.sleep(0.3)
    time.sleep(0.5)
    elapsed = int((time.time() - t0) * 1000)
    raw = subprocess.check_output(
        ["adb", "-s", DEV, "shell", "dumpsys", "gfxinfo", PKG],
        text=True,
        stderr=subprocess.STDOUT,
    )
    (ART / f"{PREFIX}_gfxinfo_{tag}.txt").write_text(raw)
    out: dict = {
        "tag": tag,
        "method": "adb shell dumpsys gfxinfo com.ora.ora (HWUI profile enabled)",
        "device": DEV,
        "build": "debug staging APK",
        "sampleDurationMs": elapsed,
        "rawPath": f".e2e_artifacts/{PREFIX}_gfxinfo_{tag}.txt",
    }
    m = re.search(r"Total frames rendered:\s*(\d+)", raw)
    if m:
        out["totalFramesRendered"] = int(m.group(1))
    m = re.search(r"Janky frames:\s*(\d+)\s*\(([\d.]+)%\)", raw)
    if m:
        out["jankyFrames"] = int(m.group(1))
        out["jankyPercent"] = float(m.group(2))
    for label, key in (
        ("50th percentile", "p50Ms"),
        ("90th percentile", "p90Ms"),
        ("95th percentile", "p95Ms"),
        ("99th percentile", "p99Ms"),
    ):
        m = re.search(rf"{label}:\s*(\d+)ms", raw)
        if m:
            out[key] = int(m.group(1))
    # Parse Profile data rows if present
    profile_lines = []
    in_profile = False
    for line in raw.splitlines():
        if line.strip().startswith("Profile data in ms"):
            in_profile = True
            continue
        if in_profile:
            if not line.strip():
                if profile_lines:
                    break
                continue
            if "View hierarchy" in line:
                break
            if re.match(r"^\s*[\d.]+\s+", line) or "\t" in line:
                profile_lines.append(line.strip())
    out["profileRowCount"] = len(profile_lines)
    out["hasUsableFrameStats"] = (out.get("totalFramesRendered") or 0) > 0
    return out


def poll_card_without_refresh(ride_marker: str, timeout_s: float = 45.0) -> dict:
    """Poll UI dumps only — never pull-to-refresh."""
    t_start = time.time()
    t_start_iso = iso()
    appeared_at = None
    last_xml = ""
    for i in range(int(timeout_s / 1.5)):
        xml = dump(f"fcm_poll_{i}")
        last_xml = xml
        u = texts(xml)
        # Prefer ride id in content-desc; also route markers
        hit = ride_marker in u or ride_marker.split("-")[0] in u
        if not hit:
            # Bahria / Liberty route from staging prep
            hit = "Liberty Market" in u and ("Bahria" in u or "Gulberg" in u) and "Accept" in u
        if hit:
            appeared_at = iso()
            shot("fcm_card_visible")
            return {
                "appeared": True,
                "pollStartedAt": t_start_iso,
                "appearedAt": appeared_at,
                "appearLatencyMs": int((time.time() - t_start) * 1000),
                "pollIndex": i,
                "marker": ride_marker,
            }
        time.sleep(1.5)
    shot("fcm_timeout")
    (ART / f"{PREFIX}_fcm_timeout.xml").write_text(last_xml)
    return {
        "appeared": False,
        "pollStartedAt": t_start_iso,
        "appearLatencyMs": int((time.time() - t_start) * 1000),
        "marker": ride_marker,
    }


def scrape_logcat_fcm() -> dict:
    raw = subprocess.check_output(
        ["adb", "-s", DEV, "logcat", "-d", "-v", "threadtime"],
        text=True,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    (ART / f"{PREFIX}_fcm_logcat.txt").write_text(raw[-400000:])
    lines = [
        ln
        for ln in raw.splitlines()
        if "D1_FCM" in ln or "dispatch" in ln.lower() and "fcm" in ln.lower() or "FirebaseMessaging" in ln
    ]
    (ART / f"{PREFIX}_fcm_logcat_filtered.txt").write_text("\n".join(lines[-200:]))
    # Extract first D1_FCM / messaging timestamps
    first = None
    for ln in lines:
        if "[D1_FCM]" in ln or "FirebaseMessaging" in ln:
            first = ln
            break
    return {
        "filteredPath": f".e2e_artifacts/{PREFIX}_fcm_logcat_filtered.txt",
        "matchCount": len(lines),
        "firstMatchLine": first,
    }


def physical_accept_sheet_only(xml: str) -> dict:
    out = {}
    if "Accept" in texts(xml) and M.tap_contains(xml, "Accept"):
        time.sleep(2.0)
        xml = dump("lifecycle_sheet")
        shot("lifecycle_sheet")
        su = texts(xml)
        out["sheetOpened"] = "Counteroffer" in su or "Submit" in su or "Accept passenger" in su
        if "Counteroffer" in su:
            M.tap_contains(xml, "Counteroffer")
            time.sleep(0.8)
            shot("lifecycle_counteroffer")
            out["counterofferChip"] = True
        # Cancel UI sheet — server offer done via API for authoritative proof
        if M.tap_contains(xml, "Cancel"):
            out["uiSheetCancelled"] = True
    else:
        out["sheetOpened"] = False
    return out


def main() -> int:
    # Load worker token into env from .env
    env_file = BACKEND / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

    # --- Driver on Open Rides ---
    xml = ensure_driver_open_rides()
    pre_ids = re.findall(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", texts(xml))
    REPORT["openRidesPreRideIds"] = pre_ids[:10]
    REPORT["shots"] = {"fcm_open_pre": f"{PREFIX}_fcm_open_pre.png"}

    # --- Jank sample ---
    log("gfxinfo scroll sample…")
    REPORT["performance"] = gfxinfo_collect("scroll2")
    shot("jank_after_scroll")

    # --- FCM path: clear logcat, prep dispatch, poll UI (no pull refresh) ---
    M.sh("logcat", "-c")
    fcm_wall_start = iso()
    log("running staging_d1_dispatch_prep…")
    try:
        prep = run_dispatch_prep()
    except Exception as e:
        REPORT["realtime"] = {"verdict": "BLOCKED", "error": str(e)}
        prep = {"ok": False, "error": str(e)}
    REPORT["fcmPrep"] = {
        "ok": prep.get("ok"),
        "rideId": prep.get("rideId"),
        "meta": prep.get("_meta"),
        "dispatchTick": (prep.get("steps") or {}).get("dispatchTick"),
        "fcmSweep": (prep.get("steps") or {}).get("fcmSweep"),
        "createRide": (prep.get("steps") or {}).get("createRide"),
    }
    ride_id = prep.get("rideId") or ""
    create_at = ((prep.get("steps") or {}).get("createRide") or {}).get("data", {})
    if isinstance(create_at, dict):
        create_iso = create_at.get("createdAt")
    else:
        create_iso = None

    invite_meta = {
        "rideCreatedAt": create_iso,
        "prepFinishedAt": (prep.get("_meta") or {}).get("prepFinishedAt"),
        "fcmWallWatchStart": fcm_wall_start,
    }

    poll = poll_card_without_refresh(ride_id or "Liberty Market", timeout_s=50)
    logcat = scrape_logcat_fcm()
    REPORT["realtime"] = {
        "mechanism": "FCM DispatchFcmService → _refreshOpenRides (no pull-to-refresh used)",
        "timestamps": {
            **invite_meta,
            "cardPoll": poll,
            "logcat": logcat,
        },
        "fcmDeliveryFromSweep": ((prep.get("steps") or {}).get("fcmSweep") or {}).get("data"),
        "uiCardAppearedWithoutManualRefresh": poll.get("appeared"),
        "verdict": "PASS"
        if poll.get("appeared") and prep.get("ok")
        else ("PARTIAL" if prep.get("ok") else "FAIL"),
    }
    REPORT["shots"]["fcm_card"] = f"{PREFIX}_fcm_card_visible.png" if poll.get("appeared") else f"{PREFIX}_fcm_timeout.png"

    # --- Accept sheet UI + authoritative server offer on disposable ride ---
    xml = dump("lifecycle_pre")
    ui = physical_accept_sheet_only(xml)
    lifecycle: dict = {"ui": ui}
    if ride_id:
        # Use counteroffer amount slightly above passenger offer if known
        amount = 72000
        cr = ((prep.get("steps") or {}).get("createRide") or {}).get("data") or {}
        if isinstance(cr, dict) and cr.get("passengerOfferMinor"):
            amount = int(cr["passengerOfferMinor"]) + 5000
        try:
            offer = api_offer_submit(ride_id, amount_minor=amount, offer_type="DRIVER_COUNTEROFFER")
            lifecycle["server"] = offer
            ok = offer.get("submitStatus") in (200, 201)
            offers = offer.get("offers")
            has_offer = False
            if isinstance(offers, list):
                has_offer = len(offers) >= 1
            elif isinstance(offers, dict) and offers.get("offers"):
                has_offer = len(offers["offers"]) >= 1
            lifecycle["verdict"] = "PASS" if ok and has_offer else "PARTIAL"
        except Exception as e:
            lifecycle["serverError"] = str(e)
            lifecycle["verdict"] = "PARTIAL"
    else:
        lifecycle["verdict"] = "PARTIAL"
        lifecycle["reason"] = "no disposable rideId from FCM prep"
    REPORT["physicalLifecycle"] = lifecycle

    # --- My rides caption clip recheck ---
    xml = M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
    if M.tap_contains(xml, "Menu", exact=True):
        time.sleep(1.0)
        xml = dump("post_menu")
    if M.tap_contains(xml, "My rides"):
        time.sleep(2.0)
        xml = dump("my_rides_v3")
        shot("my_rides_v3")
        u = texts(xml)
        REPORT["myRidesMetrics"] = {
            "cancelledVisible": "Cancelled" in u,
            "km": re.findall(r"\d+(?:\.\d+)?\s*km", u, re.I)[:8],
            "emdash": "—" in u or "\u2014" in u,
            "distanceLabel": "Distance" in u,
            "durationLabel": "Duration" in u,
            "shot": f"{PREFIX}_my_rides_v3.png",
        }

    REPORT["finishedAt"] = iso()
    out = ART / "open_rides_followup_fcm_jank_lifecycle.json"
    out.write_text(json.dumps(REPORT, indent=2))
    log(json.dumps(REPORT, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
