# Ora — Two-Device Full Physical E2E + Performance + Reliability Gate

**Correlation ID:** `ORA-E2E-20260923-1554`  
**Started:** 2026-09-23 ~15:54 PKT  
**Mode:** Audit only — **no product code changes**

---

## 1. Executive summary

**Full two-device physical ride marketplace E2E is NOT proven and cannot be claimed GREEN.**

| Blocker | Detail |
|---------|--------|
| **E2E-002 (P0)** | Only **one** physical Android device connected (`RF8R40ZQ1JH`). No Device B → driver discovery, offers, assignment, dual-sided progression, dual ratings, and dual history are **UNTESTED on hardware**. |
| **E2E-003 (P1)** | This session’s automated passenger compose run **did not reach Review** — Places showed *“Location lookup isn't available right now. Try again.”* → **pricing and ride creation not exercised physically today**. |
| **Frozen prerequisites** | AUTH-001 remains **GREEN** on Device A (cold launch ~10s, no Try Again). Prior **5C pricing GREEN** (15:20 PKT) is **not re-validated** in this run (delta `pricing_estimate_ok` = 0). |
| **Harness** | Backend **341/341** Vitest PASS (ride lifecycle, offers, progression, close, ratings covered in-process). Flutter **445 PASS / 1 FAIL** (`mvvm_layer_test` wiring drift — pre-existing). |

**Verdict:** **STOP** before two-device ride E2E claim. Connect a second physical device and re-run compose with Places key parity (same build flags as 5C proof).

---

## 2. Test environment

| Item | Device A (Passenger) | Device B (Driver) |
|------|----------------------|-------------------|
| Model | Samsung **SM-A325F** | **Not connected** |
| ADB | `RF8R40ZQ1JH` | — |
| OS | Android **13** (API 33) | — |
| APK | `com.ora.ora` **1.0.0** (code 1), installed **2026-09-23 15:47:33** | — |
| API base (logcat) | `http://127.0.0.1:8081/v1` | — |
| adb reverse | `tcp:8081 tcp:8080` | N/A |

| Backend | Value |
|---------|--------|
| PID | **14764** (single listener) |
| Port | **8080** |
| healthz | `{"ok":true,"service":"ora-auth-service"}` |
| Firebase project | **ora-app-d8112** (from backend log) |

---

## 3. Test accounts

| Role | Evidence |
|------|----------|
| Passenger (Device A) | Firebase UID **`AQLQjCfBw3W17kfgzziM6po1Nh33`** (from `register_ok` / `pricing_estimate_begin` in backend log) |
| Driver (Device B) | **Not established** — no second device / no driver login this run |

Docs list test OTP **`+923001234567` / `123456`**; a **second** Firebase test number for driver was **not configured or used** in this gate.

---

## 4. Auth results (Phase 1 — Device A only)

| Metric | Value | Class |
|--------|-------|-------|
| Activity cold start | WaitTime **4093 ms**, TotalTime **4081 ms**, LaunchState **COLD** | SLOW |
| Time to Home | **10127 ms** | GOOD (overall) |
| Try Again | **Not used / not required** | AUTH-001 **GREEN** |
| register_ok delta (this check) | **0** (session already warm) | OK |

Driver auth → Driver Home: **UNTESTED** (no Device B).

---

## 5. Passenger compose (Phase 2 — Device A)

**Automation:** `p5c_clean_run.py` under correlation marker in backend log.

| Step | Result |
|------|--------|
| Home → Ride compose | **Partial** — reached ride request UI |
| GPS / pickup | Pickup at **31.41273, 74.17249** (test provider / current location path) |
| Places / destination | **FAILED** — UI: *“Location lookup isn't available right now. Try again.”* |
| Continue | **Disabled** |
| Review | **Not reached** (`FAIL: review not reached`) |

**Evidence:** [`p5c_clean_ui.xml`](p5c_clean_ui.xml)

**Likely cause (ops, not code change):** APK built without **`ORA_GOOGLE_PLACES_API_KEY`** (5C proof script injects key; 15:47 rebuild used local API defines only).

---

## 6. GPS / Places

| Check | Status |
|-------|--------|
| GPS pickup on device | **YELLOW** — coordinates present; may differ from 5C Lahore mock (31.5204, 74.3587) |
| Places autocomplete | **RED (this session)** — lookup unavailable on device |
| Prior 4A/5C physical | **Not re-run** — treat as **stale** until Places succeeds again |

---

## 7. Pricing (Phase 3)

| Check | This session | Prior 5C (15:20) |
|-------|--------------|-------------------|
| Reach Review | **No** | Yes |
| pricing_estimate_begin → ok | **No new events** (delta 0) | Yes (trio, lahore, Rs 270) |
| Regression | **Cannot confirm GREEN** | Reported GREEN |

---

## 8–16. Ride creation through history (Phases 4–15)

All **UNTESTED physical** (no Review, no Device B).

**Harness (backend Vitest):** **GREEN** for create ride, offers, accept, progression EN_ROUTE→ARRIVED→STARTED→COMPLETED→CLOSED, ratings, history queries — see `rides.test.ts` and related suites (**341/341 PASS** @ 15:54 PKT).

Label: **BACKEND/HARNESS only**, not physical two-sided E2E.

---

## 17. Failure / recovery (Phase 16)

**UNTESTED** — happy path not completed on device.

---

## 18. FCM / notifications

**UNTESTED physical.** Offer delivery via polling/API not observed (no offer flow). D1 FCM remains **YELLOW/UNTESTED** per prior audit.

---

## 19. Performance table (measured this gate)

| Metric | Time (ms) | Class |
|--------|-----------|-------|
| Cold activity start (Device A) | **4081–4093** | SLOW |
| Cold launch → Home (Device A) | **10127** | GOOD |
| Home → Ride compose (tap) | **~3000** (poll interval) | NOTICEABLE |
| Places search | **NOT MEasured** (failed) | — |
| Pricing | **NOT MEasured** | — |
| Driver / offer / assign / progression | **NOT MEasured** | — |

---

## 20. UI responsiveness (Phase 18)

| Observation | Result |
|-------------|--------|
| Home shell | Responsive (menu, ride entry visible) |
| Compose with Places failure | Error copy visible; Continue correctly disabled |
| Frame/jank profiling | **NOT MEASURED** |

---

## 21. Network / polling (Phase 19)

Not fully audited end-to-end (no active ride). Backend log shows isolated `register_ok` / historical `pricing_estimate_*`; no ride-create storm observed this session.

---

## 22. Firestore integrity (Phase 20)

**UNTESTED** — no new ride ID from this physical run.

---

## 23. Security / authorization (Phase 21)

**Harness:** covered in backend tests (cross-user mutations rejected). **Physical smoke:** **UNTESTED**.

---

## 24. Bug list

| ID | Sev | Status | Summary |
|----|-----|--------|---------|
| E2E-002 | **P0** | **Confirmed** | Only one physical Android device — full two-device E2E **impossible** |
| E2E-003 | **P1** | **Confirmed** | Places lookup unavailable on device during compose; blocks pricing/ride create |
| E2E-004 | **P3** | Confirmed | Flutter `mvvm_layer_test` **1 FAIL** (445/446 pass) — structural wiring drift |
| AUTH-001 | — | **GREEN** | Device A cold launch without Try Again (~10s) |

**E2E-003 reproduction:** Run `p5c_clean_run.py` → destination field → *Location lookup isn't available* → Review not reached.  
**Minimal fix (after approval):** Ops — rebuild with `ORA_GOOGLE_PLACES_API_KEY` + same defines as 5C; verify Console key. Not a code change in this gate.

---

## 25. Feature matrix

| Feature | Physical | Harness | Gate color |
|---------|----------|---------|------------|
| Auth bootstrap | GREEN (A) | PASS | GREEN |
| GPS pickup | YELLOW | — | YELLOW |
| Places | RED (session) | — | RED |
| Pricing | UNTESTED (session) | PASS | YELLOW |
| Ride creation | UNTESTED | PASS | YELLOW |
| Driver discovery | UNTESTED | PASS | UNTESTED phys |
| Offers / assign | UNTESTED | PASS | UNTESTED phys |
| Progression | UNTESTED | PASS | UNTESTED phys |
| Completion / close | UNTESTED | PASS | UNTESTED phys |
| Ratings / history | UNTESTED | PASS | UNTESTED phys |
| FCM | UNTESTED | partial scripts | YELLOW |
| Full two-device E2E | **No** | partial | **RED** |

---

## 26. What is actually proven

- Device A: local API config, backend reachability, **AUTH-001** cold path to Home.
- Backend: full ride marketplace logic **341/341** in Vitest.
- Historical (same day, earlier): 5C pricing on same device with full compose + trio fare (**separate report**).

---

## 27. What is NOT proven

- Any **driver-side** physical flow.
- **Passenger → create ride → offer → accept → progression → ratings → history** on hardware.
- Places/pricing **regression-free** in **this** gate run.
- FCM wake, network recovery, performance under two active clients.

---

## 28. Production-beta blockers

1. **Second physical Android device** for driver UID.  
2. **Places-enabled device build** (match 5C dart-defines including Places key).  
3. Instrumented two-sided E2E script or manual QA checklist with correlated backend/Firestore IDs.

---

## 29. Recommended next engineering slice

1. Connect **Device B**; register **driver** test phone in Firebase; install same APK config + reverse.  
2. Re-run passenger compose with **identical** build to [`run_p5c_pricing_device_proof.sh`](run_p5c_pricing_device_proof.sh).  
3. Manual or scripted **ride ID–correlated** journey through assignment and progression on **two screens**.  
4. Fix **TEST-001** (`mvvm_layer_test`) when code changes are allowed.

---

## Acceptance criterion answer

**“Full E2E GREEN” — NO.**  
The required physical two-sided journey was **not executed**. Stopping per instructions until Device B and successful compose/pricing are available.
