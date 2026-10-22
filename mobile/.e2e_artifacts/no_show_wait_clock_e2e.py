#!/usr/bin/env python3
"""Physical proof: passenger wait-clock (DRIVER_ARRIVED) -> server NO_SHOW.

Flow: fresh ride -> driver offer -> passenger select -> driver marks en route
+ arrived -> capture passenger 'Driver has arrived' + ticking 'Waiting Xs' ->
wait for scheduled no-show sweep (RIDE_NO_SHOW_WAIT_MS=5min server-side;
staging scheduler */5min) -> verify NO_SHOW in Firestore -> capture passenger
'No-show recorded' terminal UI.

Reuses two_actor_lifecycle_ratings_e2e helpers/flows; writes ns_* artifacts.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import two_actor_lifecycle_ratings_e2e as T  # noqa: E402

ART = T.ART
P, D = T.P, T.D
REPORT = {"checks": {}, "ui": {}, "timeline": []}


def _fail_safe(msg: str) -> None:
    """Never overwrite committed lr_/report artifacts: distinct filename."""
    T.REPORT["error"] = msg
    T.REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    T.REPORT["verdict"] = "NOT GREEN"
    out = f"{ART}/no_show_failed_report.json"
    open(out, "w").write(json.dumps(T.REPORT, indent=2))
    print(json.dumps(T.REPORT, indent=2))
    sys.exit(1)


T.fail = _fail_safe  # noqa: E305 — keep committed report artifacts intact


def note(k, v):
    REPORT["timeline"].append({"at": datetime.now(timezone.utc).isoformat(), k: v})


def progress_to_arrived(rid: str) -> None:
    for label, expected in (("Mark en route", "DRIVER_EN_ROUTE"),
                            ("Mark arrived", "DRIVER_ARRIVED")):
        found = False
        for _ in range(14):
            t = T.open_driver_assigned_detail(rid, f"ns_d_{expected}")
            if label in t:
                found = True
                break
            time.sleep(2)
        if not found:
            REPORT["checks"][expected] = "FAIL"
            T.fail(f"'{label}' never visible")
        T.tap_button(D, label, t) or T.tap(D, label, t)
        time.sleep(4)
        snap = T.wait_state(rid, expected, tries=10, pause=2.0)
        st = (snap.get("ride") or {}).get("state")
        REPORT["checks"][expected] = "PASS" if st == expected else "FAIL"
        if st != expected:
            T.fail(f"expected {expected} got {st}")
        T.shot(D, f"ns_d_{expected.lower()}")


def capture_passenger(rid: str, want: str, tag: str, timeout_s: int = 60):
    """Poll passenger UI for `want` text; dump+shot; return (found, dump)."""
    deadline = time.time() + timeout_s
    t = ""
    while time.time() < deadline:
        t = T.dump(P, tag)
        if want in t:
            T.shot(P, tag)
            return True, t
        time.sleep(3)
    T.shot(P, tag + "_miss")
    return False, t


def main() -> None:
    REPORT["started"] = datetime.now(timezone.utc).isoformat()
    REPORT["devices"] = {"passenger": P, "driver": D}
    REPORT["api"] = T.REPORT.get("remote_api",
                                 "https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1")
    subprocess.check_call(["adb", "-s", D, "shell", "monkey", "-p", T.PKG,
                           "-c", "android.intent.category.LAUNCHER", "1"])
    time.sleep(3)
    T.driver_ready()
    rid = T.passenger_create_ride()
    REPORT["rideId"] = rid
    T.driver_discover_and_offer(rid)
    T.passenger_select_offer(rid)
    progress_to_arrived(rid)
    note("driver_arrived_backend", True)

    # Wait-clock UI: two captures ~65s apart must show 'Waiting' and tick forward.
    ok1, t1 = capture_passenger(rid, "Waiting", "ns_p_wait1", 90)
    REPORT["ui"]["wait_label_1"] = ok1
    waits = [x for x in ("Waiting", "Driver has arrived") if x in t1]
    REPORT["ui"]["wait_screen_text"] = waits
    time.sleep(65)
    t2 = T.dump(P, "ns_p_wait2")
    T.shot(P, "ns_p_wait2")
    import re
    m1 = re.search(r"Waiting (\d+)m? ?(\d+)?s?", t1)
    m2 = re.search(r"Waiting (\d+)m? ?(\d+)?s?", t2)
    REPORT["ui"]["wait_label_2"] = "Waiting" in t2
    REPORT["ui"]["wait_tick"] = (m1.group(0) if m1 else None, m2.group(0) if m2 else None)
    REPORT["checks"]["wait_clock_ui"] = (
        "PASS" if ok1 and "Waiting" in t2 and (m1 and m2 and m1.group(0) != m2.group(0))
        else "FAIL"
    )

    # Wait for server NO_SHOW (5min from arrivedAt + <=5min scheduler + margin).
    snap0 = T.tsx("e2e_ride_snapshot.ts", rid)
    arrived_at = (snap0.get("ride") or {}).get("arrivedAt")
    REPORT["arrivedAt"] = arrived_at
    deadline = time.time() + 15 * 60
    state = None
    while time.time() < deadline:
        snap = T.tsx("e2e_ride_snapshot.ts", rid)
        state = (snap.get("ride") or {}).get("state")
        if state == "NO_SHOW":
            break
        time.sleep(20)
    REPORT["checks"]["backend_no_show"] = "PASS" if state == "NO_SHOW" else f"FAIL ({state})"
    note("backend_state_final", state)

    # Passenger terminal UI.
    ok, t3 = capture_passenger(rid, "No-show recorded", "ns_p_noshow", 90)
    REPORT["ui"]["no_show_title"] = ok
    REPORT["ui"]["no_fees_copy"] = "No fees" in t3
    REPORT["ui"]["cancel_absent"] = "Cancel ride" not in t3
    REPORT["ui"]["back_home_present"] = "Back to Home" in t3
    REPORT["checks"]["no_show_ui"] = "PASS" if ok and "No fees" in t3 else "FAIL"
    REPORT["checks"]["wait_label_stopped"] = (
        "PASS" if "Waiting" not in t3.split("No-show recorded")[0][:200] else "INFO"
    )

    REPORT["lifecycle_gates"] = T.REPORT.get("gates", {})
    all_ok = all(v == "PASS" for v in REPORT["checks"].values() if v != "INFO")
    REPORT["verdict"] = "GREEN" if all_ok else "NOT GREEN"
    REPORT["finished"] = datetime.now(timezone.utc).isoformat()
    out = f"{ART}/no_show_wait_clock_physical_report.json"
    open(out, "w").write(json.dumps(REPORT, indent=2))
    print(json.dumps(REPORT, indent=2))
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
