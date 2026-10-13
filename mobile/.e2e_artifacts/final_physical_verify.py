#!/usr/bin/env python3
"""Final physical: MapLibre ride request + FCM refresh + ORA_FRAME timing capture."""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import map2a_physical as M

DEV, PKG, ART = M.DEV, M.PKG, M.ART
PREFIX = "final"
BACKEND = Path(__file__).resolve().parents[2] / "backend" / "auth-service"
REPORT: dict = {
    "startedAt": datetime.now(timezone.utc).isoformat(),
    "device": DEV,
    "package": PKG,
}


def iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def log(*a):
    print(*a, flush=True)


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


def load_env():
    env_file = BACKEND / ".env"
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    os.environ.setdefault(
        "GOOGLE_APPLICATION_CREDENTIALS",
        str(BACKEND / "secrets/service-account.json"),
    )


def run_fcm_prep_limit100() -> dict:
    """Create ride + tick + FCM sweep with limit=100 (workaround for skip-starvation)."""
    script = r'''
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
const repoRoot = path.join(process.cwd(), '../..');
const sa = process.env.GOOGLE_APPLICATION_CREDENTIALS!;
if (!getApps().length) initializeApp({ credential: cert(sa) });
const DRIVER='+923012345677', PASSENGER='+923012345678';
const PICKUP={lat:31.4127578,lng:74.1725224,address:'Liberty Market Lahore'};
const DEST={lat:31.51058,lng:74.34445,address:'Gulberg Lahore'};
const worker=(process.env.ORA_INTERNAL_WORKER_TOKEN||'').trim();
const base=readFileSync(path.join(repoRoot,'mobile/.staging_api_url'),'utf8').trim().replace(/\/$/,'');
const gs=JSON.parse(readFileSync(path.join(repoRoot,'mobile/android/app/google-services.json'),'utf8'));
const apiKey=gs.client[0].api_key[0].current_key;
async function tok(phone:string){
  const uid=(await getAuth().getUserByPhoneNumber(phone)).uid;
  const custom=await getAuth().createCustomToken(uid);
  const res=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({token:custom,returnSecureToken:true})});
  if(!res.ok) throw new Error('token '+res.status);
  return {uid, token:(await res.json()).idToken as string};
}
async function api(method:string,route:string,opts:{bearer?:string;worker?:string;body?:unknown;idem?:string}={}){
  const headers:Record<string,string>={Accept:'application/json'};
  if(opts.bearer) headers.Authorization='Bearer '+opts.bearer;
  if(opts.worker) headers['X-Ora-Worker-Token']=opts.worker!;
  if(opts.body!=null) headers['Content-Type']='application/json';
  if(opts.idem) headers['Idempotency-Key']=opts.idem;
  const res=await fetch(base+route,{method,headers,body:opts.body!=null?JSON.stringify(opts.body):undefined});
  const json=await res.json().catch(()=>({}));
  return {status:res.status,json,at:new Date().toISOString()};
}
const d=await tok(DRIVER); const p=await tok(PASSENGER);
await api('POST','/drivers/go-online',{bearer:d.token,body:{}});
await api('POST','/location/update',{bearer:d.token,body:{
  locationSeq:1,locationStreamId:'final-phys-'+Date.now(),
  lat:PICKUP.lat,lng:PICKUP.lng,accuracy:8,heading:90,speed:0,
  timestamp:new Date().toISOString(),provider:'gps'}});
const est=await api('POST','/pricing/estimate',{bearer:p.token,body:{
  pickup:PICKUP,destination:DEST,category:'easy',city:'lahore',serviceType:'ride'}});
const ed=est.json.data as any;
const createAt=new Date().toISOString();
const ride=await api('POST','/rides',{bearer:p.token,idem:'final-phys-'+randomUUID(),body:{
  pickup:PICKUP,destination:DEST,city:'lahore',category:'easy',serviceType:'ride',
  passengerOfferMinor:ed.recommendedFareMinor,pricingSnapshotId:ed.pricingSnapshotId,
  paymentMethod:'CASH',passengerCount:1}});
const rideId=(ride.json.data as any)?.rideId;
const tickAt=new Date().toISOString();
const tick=await api('POST',`/internal/rides/${rideId}/dispatch-tick`,{worker});
const sweepAt=new Date().toISOString();
const sweep=await api('POST','/internal/outbox/dispatch-fcm-sweep?limit=100',{worker});
console.log(JSON.stringify({
  createAt, rideId, createStatus:ride.status,
  tickAt, tickStatus:tick.status, tick:tick.json.data,
  sweepAt, sweepStatus:sweep.status, sweep:sweep.json.data,
},null,2));
'''
    path = BACKEND / ".tmp_final_fcm_prep.mts"
    path.write_text(script)
    try:
        out = subprocess.check_output(
            ["node", "--import", "tsx", str(path)],
            cwd=str(BACKEND),
            env={**os.environ},
            text=True,
            timeout=180,
        )
    finally:
        path.unlink(missing_ok=True)
    data = json.loads(out)
    (ART / f"{PREFIX}_fcm_prep.json").write_text(json.dumps(data, indent=2))
    return data


def scrape_frames() -> dict:
    raw = subprocess.check_output(
        ["adb", "-s", DEV, "logcat", "-d", "-v", "threadtime"],
        text=True,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    (ART / f"{PREFIX}_logcat.txt").write_text(raw[-500000:])
    frames = []
    for ln in raw.splitlines():
        if "ORA_FRAME" in ln:
            frames.append(ln)
        if "[D1_FCM]" in ln:
            frames.append(ln)
    (ART / f"{PREFIX}_frame_d1_logcat.txt").write_text("\n".join(frames[-500:]))
    totals = []
    for ln in frames:
        m = re.search(r"totalMs=([\d.]+)", ln)
        if m:
            totals.append(float(m.group(1)))
    slow = [t for t in totals if t > 16.67]
    janky = [t for t in totals if t > 33.34]
    return {
        "oraFrameSampleCount": len(totals),
        "slowFramesOver16ms": len(slow),
        "jankyFramesOver33ms": len(janky),
        "maxTotalMs": max(totals) if totals else None,
        "p50TotalMs": sorted(totals)[len(totals) // 2] if totals else None,
        "d1FcmLines": [ln for ln in frames if "[D1_FCM]" in ln][:20],
        "artifact": f".e2e_artifacts/{PREFIX}_frame_d1_logcat.txt",
    }


def ensure_passenger_ride_request() -> str:
    M.adb("shell", "am", "force-stop", PKG)
    time.sleep(0.4)
    M.adb("shell", "am", "start", "-n", f"{PKG}/.MainActivity")
    time.sleep(4.0)
    xml = dump("boot")
    if "Send OTP" in texts(xml) or "Phone number" in texts(xml) or "Verify" in texts(xml):
        xml = M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
    else:
        # Force passenger if needed
        if "Earn on ORA" not in texts(xml) and "Where to" not in texts(xml):
            xml = M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
    # Open Where to / request
    if M.tap_contains(xml, "Where to") or M.tap_contains(xml, "Where are you headed"):
        time.sleep(2.0)
    elif M.tap_contains(xml, "Request a ride") or M.tap_contains(xml, "Request"):
        time.sleep(2.0)
    xml = dump("ride_request")
    shot("ride_request")
    return xml


def expand_collapse(xml: str) -> dict:
    out = {}
    if M.tap_contains(xml, "Expand map") or M.tap_contains(xml, "Expand"):
        time.sleep(1.5)
        xml = dump("map_expanded")
        shot("map_expanded")
        out["expanded"] = True
        if M.tap_contains(xml, "Collapse map") or M.tap_contains(xml, "Collapse") or M.tap_contains(xml, "Close"):
            time.sleep(1.2)
            xml = dump("map_collapsed")
            shot("map_collapsed")
            out["collapsed"] = True
    else:
        # Try expand icon coords mid-right top area
        out["expanded"] = False
    return out


def seed_route_on_request(xml: str) -> dict:
    """Best-effort: set pickup GPS + Liberty destination for map tiles/route."""
    out = {"attempted": True}
    if M.tap_contains(xml, "Use current location"):
        time.sleep(2.0)
        xml = dump("after_gps")
        out["gps"] = True
    # Destination field
    if M.tap_contains(xml, "Search destination") or M.tap_contains(xml, "Destination"):
        time.sleep(0.8)
        M.sh("input", "text", "Liberty")
        time.sleep(2.0)
        xml = dump("dest_sugg")
        if M.tap_contains(xml, "Liberty Market") or M.tap_contains(xml, "Liberty"):
            time.sleep(1.5)
            xml = dump("dest_selected")
            out["dest"] = True
            shot("map_with_route")
    return out


def driver_open_rides_watch_fcm() -> dict:
    xml = M.force_login(M.DRIVER_PHONE_UI, M.DRIVER_OTP, want_passenger=False)
    dump("driver_home")
    if not (M.tap_contains(xml, "Open rides") or M.tap_contains(xml, "Open ride requests")):
        M.sh("input", "tap", "216", "2200")
    time.sleep(2.0)
    xml = dump("open_pre_fcm")
    shot("open_pre_fcm")
    M.sh("logcat", "-c")
    t_watch = iso()
    prep = run_fcm_prep_limit100()
    ride_id = prep.get("rideId") or ""
    appear = None
    for i in range(24):
        xml = dump(f"fcm_poll_{i}")
        u = texts(xml)
        hit = (
            (ride_id and (ride_id in u or ride_id.split("-")[0] in u))
            or ("Liberty Market" in u and "Accept" in u)
        )
        if hit:
            appear = {
                "appearedAt": iso(),
                "pollIndex": i,
                "latencyFromSweepAtMs": None,
            }
            shot("fcm_card_visible")
            break
        time.sleep(1.5)
    frames = scrape_frames()
    return {
        "watchStartedAt": t_watch,
        "prep": prep,
        "appeared": appear is not None,
        "appear": appear,
        "frames": frames,
        "manualRefreshUsed": False,
    }


def scroll_open_and_my_rides():
    # Open rides scroll for frames
    for _ in range(8):
        M.sh("input", "swipe", "540", "1700", "540", "700", "300")
        time.sleep(0.25)
    # My rides
    xml = M.force_login(M.PASSENGER_PHONE_UI, M.PASSENGER_OTP, want_passenger=True)
    if M.tap_contains(xml, "Menu", exact=True):
        time.sleep(1.0)
        xml = dump("menu")
    if M.tap_contains(xml, "My rides"):
        time.sleep(2.0)
        dump("my_rides")
        shot("my_rides")
        for _ in range(6):
            M.sh("input", "swipe", "540", "1700", "540", "700", "300")
            time.sleep(0.25)


def main() -> int:
    load_env()
    M.sh("logcat", "-c")

    # --- Map / ride request ---
    xml = ensure_passenger_ride_request()
    REPORT["rideRequest"] = {
        "shot": f"{PREFIX}_ride_request.png",
        "hasWhereTo": "Where to" in texts(xml) or "Where are you" in texts(xml),
        "hasMapPreview": "Map preview" in texts(xml) or "Expand" in texts(xml) or "Map" in texts(xml),
        "attributionHint": "©" in texts(xml) or "MapTiler" in texts(xml) or "OpenStreetMap" in texts(xml),
    }
    REPORT["routeSeed"] = seed_route_on_request(xml)
    xml = dump("pre_expand")
    REPORT["expandCollapse"] = expand_collapse(xml)

    # Toggle 3D / layers if present
    xml = dump("controls")
    controls = {}
    if M.tap_contains(xml, "3D") or M.tap_contains(xml, "Switch to 3D"):
        time.sleep(0.8)
        shot("map_3d_toggle")
        controls["threeD"] = True
    if M.tap_contains(xml, "Hide buildings") or M.tap_contains(xml, "Show buildings") or M.tap_contains(xml, "layers"):
        time.sleep(0.6)
        shot("map_layers_toggle")
        controls["layers"] = True
    REPORT["mapControls"] = controls

    # --- FCM path ---
    REPORT["fcm"] = driver_open_rides_watch_fcm()

    # --- Accept sheet if card present ---
    xml = dump("post_fcm")
    if "Accept" in texts(xml) and M.tap_contains(xml, "Accept"):
        time.sleep(1.8)
        xml = dump("accept_sheet")
        shot("accept_sheet")
        REPORT["acceptSheet"] = {
            "opened": "Counteroffer" in texts(xml) or "Submit" in texts(xml),
        }
        if M.tap_contains(xml, "Cancel"):
            time.sleep(0.8)
    else:
        REPORT["acceptSheet"] = {"opened": False}

    scroll_open_and_my_rides()
    REPORT["frameTiming"] = scrape_frames()
    REPORT["finishedAt"] = iso()
    out = ART / f"{PREFIX}_physical_report.json"
    out.write_text(json.dumps(REPORT, indent=2))
    log(json.dumps(REPORT, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
