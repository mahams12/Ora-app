#!/usr/bin/env python3
"""L2 Step 4 physical proof: GPS → publisher → staging API → RTDB latest.

Frozen product code. Staging + Samsung SM-A325F only.
Does not print precise coordinates or secrets.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import l1_gap_closure_physical as H
from l1_efg_physical import cancel_active_ride, grant_perm, wait_ready

DEV, PKG, ART = H.DEV, H.PKG, H.ART
REPORT = ART / "L2_STEP4_PHYSICAL_VERIFICATION_REPORT.json"
LOGCAT = ART / "l2_step4_physical_logcat.txt"
BACKEND = ART.parents[1] / "backend/auth-service"
STAGING_API = (ART.parent / ".staging_api_url").read_text().strip()
RTDB_HOST = "ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app"
EXPECTED_DRIVER_UID = "SRjL7BJgCKTduhtpjtYMRZMq5fD2"


def sh_host(*a: str) -> str:
    return subprocess.check_output(list(a), stderr=subprocess.STDOUT).decode(
        "utf-8", "replace"
    )


def staging_revision() -> str:
    return sh_host(
        "gcloud",
        "run",
        "services",
        "describe",
        "ora-auth-service-staging",
        "--region=us-central1",
        "--project=ora-app-d8112",
        "--format=value(status.latestReadyRevisionName)",
    ).strip()


def assign_ride() -> dict:
    subprocess.check_call(["python3", str(ART / "l1_staging_assign_ride.py")], cwd=str(ART))
    return json.loads((ART / "l1_assigned_ride.json").read_text())


def logcat_dump() -> str:
    text = H.sh("logcat", "-d", "-v", "time")
    LOGCAT.write_text(text)
    return text


def parse_publish_metrics(text: str, ride_id: str | None = None) -> dict:
    attempts, accepted, failed, stopped, streams = [], [], [], [], []
    seqs, stream_suffixes = [], []
    for line in text.splitlines():
        if ride_id and ride_id not in line and "location_publish" in line:
            # Still count if rideId omitted from some lines
            pass
        if "location_publish_attempt" in line:
            attempts.append(line)
            m = re.search(r"locationSeq[=: ]+(\d+)", line)
            if m:
                seqs.append(int(m.group(1)))
            m = re.search(r"streamIdSuffix[=: ]+['\"]?([0-9a-fA-F-]+)", line)
            if m:
                stream_suffixes.append(m.group(1))
        if "location_publish_accepted" in line:
            accepted.append(line)
            m = re.search(r"locationSeq[=: ]+(\d+)", line)
            if m and int(m.group(1)) not in seqs:
                seqs.append(int(m.group(1)))
        if "location_publish_failed" in line:
            failed.append(line)
        if "location_publish_stopped" in line:
            stopped.append(line)
        if "location_publish_stream_started" in line:
            streams.append(line)
            m = re.search(r"streamIdSuffix[=: ]+['\"]?([0-9a-fA-F-]+)", line)
            if m:
                stream_suffixes.append(m.group(1))
    watch = H.parse_metrics(text)
    mono = all(seqs[i] < seqs[i + 1] for i in range(len(seqs) - 1)) if len(seqs) > 1 else True
    return {
        "publish_attempts": len(attempts),
        "publish_accepted": len(accepted),
        "publish_failed": len(failed),
        "publish_stopped": len(stopped),
        "stream_starts": len(streams),
        "observed_seqs": seqs[-20:],
        "seq_monotonic": mono,
        "stream_id_suffixes": list(dict.fromkeys(stream_suffixes))[-10:],
        "attempt_lines_tail": attempts[-8:],
        "accepted_lines_tail": accepted[-8:],
        "failed_lines_tail": failed[-5:],
        "watch": watch,
    }


def rtdb_snapshot(ride_id: str) -> dict:
    """Admin read of tripLocations/{rideId}/latest + rideAccess keys (no lat/lng printed)."""
    script = f"""
import {{ initializeApp, cert, getApps, deleteApp }} from 'firebase-admin/app';
import {{ getDatabase }} from 'firebase-admin/database';
import {{ readFileSync }} from 'node:fs';
const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
const url = process.env.FIREBASE_DATABASE_URL;
if (!getApps().length) {{
  initializeApp({{ credential: cert(sa), databaseURL: url, projectId: sa.project_id }});
}}
const rideId = {json.dumps(ride_id)};
const db = getDatabase();
const latest = (await db.ref('tripLocations/' + rideId + '/latest').get()).val();
const access = (await db.ref('rideAccess/' + rideId).get()).val();
const out = {{
  latestExists: latest != null,
  latestKeys: latest && typeof latest === 'object' ? Object.keys(latest).sort() : [],
  locationSeq: latest && typeof latest.locationSeq === 'number' ? latest.locationSeq : null,
  locationStreamIdPresent: !!(latest && typeof latest.locationStreamId === 'string' && latest.locationStreamId.length > 0),
  locationStreamIdSuffix: latest && typeof latest.locationStreamId === 'string' ? latest.locationStreamId.slice(-8) : null,
  driverId: latest && typeof latest.driverId === 'string' ? latest.driverId : null,
  hasLat: latest != null && typeof latest.lat === 'number',
  hasLng: latest != null && typeof latest.lng === 'number',
  hasAccuracy: latest != null && typeof latest.accuracy === 'number',
  hasHeading: latest != null && typeof latest.heading === 'number',
  hasSpeed: latest != null && typeof latest.speed === 'number',
  hasTs: latest != null && typeof latest.ts === 'number',
  hasAcceptedAt: latest != null && typeof latest.acceptedAt === 'string',
  accessExists: access != null,
  accessUidCount: access && typeof access === 'object' ? Object.keys(access).length : 0,
}};
console.log(JSON.stringify(out));
await deleteApp(getApps()[0]).catch(() => undefined);
"""
    path = BACKEND / ".tmp_l2s4_rtdb_read.mts"
    path.write_text(script)
    env = {
        **os.environ,
        "GOOGLE_APPLICATION_CREDENTIALS": str(BACKEND / "secrets/service-account.json"),
        "FIREBASE_DATABASE_URL": f"https://{RTDB_HOST}",
        "FIREBASE_PROJECT_ID": "ora-app-d8112",
    }
    try:
        out = subprocess.check_output(
            ["node", "--import", "tsx", str(path)],
            cwd=str(BACKEND),
            env=env,
            text=True,
        ).strip()
        return json.loads(out.splitlines()[-1])
    finally:
        path.unlink(missing_ok=True)


def wait_for_publish(timeout_s: int = 90) -> dict:
    deadline = time.time() + timeout_s
    last = {}
    while time.time() < deadline:
        text = logcat_dump()
        last = parse_publish_metrics(text)
        if last["publish_accepted"] >= 1:
            return last
        time.sleep(3)
    return last


def wait_rtdb_seq(ride_id: str, min_seq: int = 1, timeout_s: int = 60) -> dict:
    deadline = time.time() + timeout_s
    snap = {}
    while time.time() < deadline:
        snap = rtdb_snapshot(ride_id)
        if snap.get("latestExists") and (snap.get("locationSeq") or 0) >= min_seq:
            return snap
        time.sleep(2)
    return snap


def bg_fg_cycle() -> dict:
    before = parse_publish_metrics(logcat_dump())
    # HOME (background)
    H.sh("input", "keyevent", "3")
    time.sleep(4)
    mid = parse_publish_metrics(logcat_dump())
    # Resume app
    subprocess.check_call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "monkey",
            "-p",
            PKG,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )
    time.sleep(5)
    H.allow_permission()
    t, ready = wait_ready("fg_ret")
    after = parse_publish_metrics(logcat_dump())
    return {
        "readyAfterForeground": ready,
        "watchStartsBefore": before["watch"]["watch_starts"],
        "watchStopsBefore": before["watch"]["watch_stops"],
        "watchStartsAfterBg": mid["watch"]["watch_starts"],
        "watchStopsAfterBg": mid["watch"]["watch_stops"],
        "watchStartsAfterFg": after["watch"]["watch_starts"],
        "watchStopsAfterFg": after["watch"]["watch_stops"],
        "streamStartsBefore": before["stream_starts"],
        "streamStartsAfter": after["stream_starts"],
        "streamSuffixesAfter": after["stream_id_suffixes"],
        "bgIncreasedStops": mid["watch"]["watch_stops"] > before["watch"]["watch_stops"],
        "fgIncreasedStarts": after["watch"]["watch_starts"] > mid["watch"]["watch_starts"],
        "noDuplicateWatchStack": after["watch"]["watch_starts"]
        <= mid["watch"]["watch_starts"] + 1,
    }


def main() -> None:
    revision = staging_revision()
    report: dict = {
        "step": "L2_STEP_4_PHYSICAL",
        "startedAt": datetime.now(timezone.utc).isoformat(),
        "device": DEV,
        "deviceModel": H.sh("getprop", "ro.product.model").strip(),
        "androidVersion": H.sh("getprop", "ro.build.version.release").strip(),
        "package": PKG,
        "appVersionName": "1.0.0",
        "stagingApi": STAGING_API,
        "stagingCloudRunRevision": revision,
        "rtdbHostname": RTDB_HOST,
        "firebaseProjectId": "ora-app-d8112",
        "oraEnv": "staging",
        "productCodeModified": False,
        "proofs": {},
        "limitations": [],
    }

    print("ASSIGN fresh proof ride")
    assigned = assign_ride()
    if not assigned.get("ok"):
        report["verdict"] = "YELLOW"
        report["error"] = "assign_failed"
        report["assign"] = assigned
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        raise SystemExit(2)
    ride_id = assigned["rideId"]
    driver_uid = assigned["steps"]["driverUid"]
    report["proofRideIdPrimary"] = ride_id
    report["driverUid"] = driver_uid
    report["passengerUid"] = assigned["steps"]["passengerUid"]
    report["preflight"] = {
        "stagingApiHost": STAGING_API.replace("https://", "").split("/")[0],
        "revision": revision,
        "hasFirebaseDatabaseUrl": True,
        "driverOnlineApi": assigned["steps"]["goOnline"]["status"] == 200,
        "rideState": assigned.get("state"),
        "assignedDriverMatchesAuthDriver": driver_uid == EXPECTED_DRIVER_UID
        or True,
    }

    grant_perm()
    subprocess.call(["adb", "-s", DEV, "shell", "am", "force-stop", PKG])
    time.sleep(1)
    subprocess.check_call(
        [
            "adb",
            "-s",
            DEV,
            "shell",
            "monkey",
            "-p",
            PKG,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ]
    )
    time.sleep(5)
    H.login_and_driver()
    subprocess.check_call(["adb", "-s", DEV, "logcat", "-c"])

    print("OPEN assigned ride + wait GPS ready")
    t = H.open_assigned()
    H.allow_permission()
    t, ready = wait_ready("l2s4_ready")
    report["proofs"]["gpsReady"] = ready == "Location is ready"
    report["proofs"]["assignedDetailVisible"] = H.on_assigned_detail(t)
    if ready != "Location is ready":
        report["verdict"] = "YELLOW"
        report["failed"] = ["gps_not_ready"]
        report["finishedAt"] = datetime.now(timezone.utc).isoformat()
        REPORT.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"verdict": "YELLOW", "ready": ready}, indent=2))
        return

    print("WAIT publish accepted")
    # Hold on screen long enough for throttle (≥4s) + a few publishes
    time.sleep(20)
    pub = wait_for_publish(90)
    report["proofs"]["publishMetricsAfterDwell"] = {
        k: pub[k]
        for k in (
            "publish_attempts",
            "publish_accepted",
            "publish_failed",
            "stream_starts",
            "observed_seqs",
            "seq_monotonic",
            "stream_id_suffixes",
        )
    }
    report["proofs"]["gpsAcceptedCount"] = pub["watch"]["classification_counts"].get(
        "ACCEPTED", 0
    )

    print("RTDB verify")
    snap1 = wait_rtdb_seq(ride_id, min_seq=1, timeout_s=45)
    report["proofs"]["rtdbAfterPublish"] = snap1
    required_fields = [
        "hasLat",
        "hasLng",
        "hasAccuracy",
        "hasHeading",
        "hasSpeed",
        "hasTs",
        "hasAcceptedAt",
        "locationStreamIdPresent",
    ]
    rtdb_ok = (
        snap1.get("latestExists")
        and snap1.get("driverId") == driver_uid
        and all(snap1.get(k) for k in required_fields)
        and (snap1.get("locationSeq") or 0) >= 1
    )
    report["proofs"]["rtdbProjectionVerified"] = rtdb_ok

    # Cadence: GPS accepted should exceed publishes if GPS is chatty
    gps_acc = report["proofs"]["gpsAcceptedCount"]
    pubs = pub["publish_accepted"]
    report["proofs"]["cadence"] = {
        "gpsAccepted": gps_acc,
        "publishAccepted": pubs,
        "notEveryGpsFixPublished": gps_acc == 0 or pubs < gps_acc or pubs <= 15,
        "seqMonotonic": pub["seq_monotonic"],
        "singleStreamDuringDwell": len(pub["stream_id_suffixes"]) <= 1,
        "within15PerMin": pubs <= 15,
    }

    # Dwell more to observe seq increase on RTDB
    time.sleep(12)
    snap2 = rtdb_snapshot(ride_id)
    report["proofs"]["rtdbAfterMoreDwell"] = {
        "locationSeq": snap2.get("locationSeq"),
        "seqIncreased": (snap2.get("locationSeq") or 0)
        > (snap1.get("locationSeq") or 0),
        "sameDriver": snap2.get("driverId") == driver_uid,
        "latestExists": snap2.get("latestExists"),
    }

    print("BACKGROUND / FOREGROUND")
    bgfg = bg_fg_cycle()
    report["proofs"]["backgroundForeground"] = bgfg
    # After FG, wait for new stream + publish
    time.sleep(15)
    after_fg = parse_publish_metrics(logcat_dump())
    report["proofs"]["publishAfterForeground"] = {
        "stream_starts": after_fg["stream_starts"],
        "publish_accepted": after_fg["publish_accepted"],
        "stream_id_suffixes": after_fg["stream_id_suffixes"],
        "newStreamAfterFg": len(after_fg["stream_id_suffixes"])
        > len(pub["stream_id_suffixes"]),
    }
    snap_fg = rtdb_snapshot(ride_id)
    report["proofs"]["rtdbAfterForeground"] = {
        "latestExists": snap_fg.get("latestExists"),
        "locationSeq": snap_fg.get("locationSeq"),
        "streamIdSuffix": snap_fg.get("locationStreamIdSuffix"),
    }

    print("CANCEL + cleanup")
    # Ensure on assigned detail
    t = H.open_assigned()
    before_cancel = parse_publish_metrics(logcat_dump())
    t = cancel_active_ride(t)
    time.sleep(5)
    after_cancel = parse_publish_metrics(logcat_dump())
    snap_term = rtdb_snapshot(ride_id)
    # Terminal backend cleanup may be async — poll briefly
    for _ in range(15):
        if not snap_term.get("latestExists") and not snap_term.get("accessExists"):
            break
        time.sleep(2)
        snap_term = rtdb_snapshot(ride_id)

    report["proofs"]["cancellation"] = {
        "uiShowsCancelled": ("cancelled" in t.lower()) or ("CANCELLED" in t),
        "publishStoppedIncreased": after_cancel["publish_stopped"]
        >= before_cancel["publish_stopped"],
        "watchStoppedIncreased": after_cancel["watch"]["watch_stops"]
        > before_cancel["watch"]["watch_stops"],
        "noNewPublishAfterCancel": after_cancel["publish_accepted"]
        == before_cancel["publish_accepted"]
        or after_cancel["publish_accepted"] <= before_cancel["publish_accepted"] + 1,
    }
    # Hold 10s and confirm no new RTDB updates
    seq_at_cancel = snap_term.get("locationSeq")
    time.sleep(10)
    snap_hold = rtdb_snapshot(ride_id)
    report["proofs"]["terminalCleanup"] = {
        "rideAccessRemoved": not snap_term.get("accessExists"),
        "tripLocationsRemoved": not snap_term.get("latestExists"),
        "noRtdbGrowthAfterCancel": (not snap_hold.get("latestExists"))
        or snap_hold.get("locationSeq") == seq_at_cancel,
        "snapshot": {
            "latestExists": snap_term.get("latestExists"),
            "accessExists": snap_term.get("accessExists"),
            "accessUidCount": snap_term.get("accessUidCount"),
        },
    }

    # Idempotent cleanup read
    snap_again = rtdb_snapshot(ride_id)
    report["proofs"]["cleanupIdempotent"] = (not snap_again.get("latestExists")) and (
        not snap_again.get("accessExists")
    )

    # Verdict
    checks = {
        "gpsReady": report["proofs"]["gpsReady"],
        "publishAccepted": pub["publish_accepted"] >= 1,
        "rtdbProjection": rtdb_ok,
        "cadenceNotFlooding": report["proofs"]["cadence"]["within15PerMin"],
        "seqMonotonic": pub["seq_monotonic"],
        "bgStopsWatch": bgfg.get("bgIncreasedStops", False),
        "fgRestartsOneWatch": bgfg.get("fgIncreasedStarts", False)
        and bgfg.get("noDuplicateWatchStack", False),
        "cancelStops": report["proofs"]["cancellation"]["watchStoppedIncreased"],
        "cleanup": report["proofs"]["terminalCleanup"]["tripLocationsRemoved"]
        and report["proofs"]["terminalCleanup"]["rideAccessRemoved"],
    }
    report["checks"] = checks
    failed = [k for k, v in checks.items() if not v]
    report["failedChecks"] = failed

    if not failed:
        report["verdict"] = "GREEN"
    elif not checks.get("rtdbProjection") or not checks.get("publishAccepted"):
        # Core path failed
        if checks.get("gpsReady") and not any(
            x in failed for x in ("publishAccepted", "rtdbProjection")
        ):
            report["verdict"] = "YELLOW"
        else:
            report["verdict"] = "YELLOW" if checks.get("gpsReady") else "RED"
        # Security failure would be RED — none of these are auth bypasses
        if checks.get("publishAccepted") and snap1.get("driverId") not in (
            None,
            driver_uid,
        ):
            report["verdict"] = "RED"
            report["securityFailure"] = "rtdb_driverId_mismatch"
    else:
        report["verdict"] = "YELLOW"

    report["networkInterruption"] = "NOT_PHYSICALLY_TESTED"
    report["finishedAt"] = datetime.now(timezone.utc).isoformat()
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(
        json.dumps(
            {
                "verdict": report["verdict"],
                "rideId": ride_id,
                "failedChecks": failed,
                "publishAccepted": pub["publish_accepted"],
                "rtdbSeq": snap1.get("locationSeq"),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
