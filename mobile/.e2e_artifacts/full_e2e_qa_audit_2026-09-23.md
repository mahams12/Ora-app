# Ora — Full Physical E2E + Performance + UX QA Audit

**Date:** 2026-09-23  
**Commit:** `ae8232d`  
**Mode:** Read-only audit (no product code changes)  
**Auditors:** Senior engineer + QA/reliability review (automated + physical sampling)

---

## 1. Executive summary

Ora’s **backend ride marketplace core is heavily tested in-process** (341 Vitest tests PASS). **Flutter has broad unit/widget coverage** (442 PASS, 1 structural test FAIL). **Physical-device evidence is strong for auth bootstrap (when backend reachable), Places, and pricing (5C GREEN)** but **does not yet prove a full passenger→driver→completion journey on hardware** because only **one** Android device was available.

**Production beta readiness:** **NOT READY** for unrestricted beta. Core logic is mature; **physical multi-party E2E, performance baselines, network-resilience on device, and dispatch/FCM wake UX** remain gaps.

**Top confirmed issues this audit:**
- **PERF-001 (P2):** Cold launch **~4.1s** to first activity (adb `TotalTime`) — **SLOW**.
- **AUTH-001 (P1):** Cold launch can sit on **“Signing you in…”** until user taps **Try again** even with backend `healthz` OK — **CONFIRMED** on RF8R40ZQ1JH.
- **E2E-001 (P0 for “full physical E2E” claim):** **No second driver device** → assignment/progression/driver UX **UNTESTED physically**.
- **TEST-001 (P3):** `mvvm_layer_test.dart` **1 FAIL** (logout wiring string match drift).

**Pricing:** Treat as **FROZEN / CLOSED (5C GREEN)** — no regression observed in this session.

---

## 2. Test environment

| Item | Value |
|------|--------|
| Device | Samsung SM-A325F, `RF8R40ZQ1JH`, Android 13 (API 33) |
| Second device | **None** (only macOS + Chrome in `flutter devices`) |
| APK | `com.ora.ora` v1.0.0 (versionCode 1), lastUpdateTime **2026-09-23 14:53:17** |
| API base (debug) | `http://127.0.0.1:8081/v1` via `adb reverse tcp:8081 → tcp:8080` |
| Backend | auth-service PID **14764**, port **8080**, `healthz` OK, `google_routes` configured |
| Firebase project | `ora-app-d8112` (from backend logs) |
| Test passenger | Firebase test phone flow used in prior proofs (`+923012345678` / OTP `123456` in ops scripts — not repeated here) |
| Harness | Backend Vitest **341/341 PASS**; Flutter **442 PASS / 1 FAIL** |

---

## 3. Complete E2E flow result

| Stage | Physical SM-A325F | Backend/harness |
|-------|-------------------|-----------------|
| Login → Home | **PARTIAL** (5C session; cold launch blocked on splash without Try again) | auth.test.ts |
| Ride request → Review → Pricing | **GREEN** (5C proof, Trio, Rs 270) | pricing_estimate.test.ts |
| Create ride → Offers → Assign → Active → Close → Rate → History | **UNTESTED physical** | rides.test.ts (87), progression proofs |
| Driver open rides → offer → progression | **UNTESTED physical** | slice_l/m driver tests, rides.test.ts |
| Dispatch / FCM wake | **UNTESTED physical** | dispatch.test.ts, delivery_d1.test.ts |

---

## 22. Latency table (measured vs not)

| Metric | Measured | Class | Method |
|--------|----------|-------|--------|
| Cold launch (activity) | **4076 ms** | **SLOW** | `adb am start -W`, LaunchState COLD |
| Warm launch (activity resume) | **~0–10 ms** | FAST | same activity foreground |
| Monkey launch → UI dump | **9455 ms** | **VERY SLOW** | includes 6s sleep + splash |
| Try again → home (automated) | **53469 ms**, home **not detected** | **VERY SLOW / FAIL** | uiautomator loop (splash stuck) |
| Home → ride request tap | **5655 ms**, screen **not** ride compose | INCONCLUSIVE | wrong screen state |
| Login OTP → home | NOT MEASURED | — | needs instrumented run |
| Places autocomplete | NOT MEASURED (this session) | — | 5C used ~6s debounce in automation |
| Pricing (5C trio) | NOT TIMED end-to-end | — | backend begin→ok in same session |
| Ride create | NOT MEASURED physical | — | |
| Offers poll interval | **2s → 3s → 5s** (design) | N/A | `OfferPollingPolicy` |
| Active ride poll | **3s → 5s → 8s** (design) | N/A | `ActiveRidePollingPolicy` |
| Frame/jank | NOT MEASURED | — | DevTools/profile required |
| Firestore read counts on device | NOT MEASURED | — | client uses HTTP only |

---

## 25. Bug list (selected)

| ID | Sev | Status | Summary |
|----|-----|--------|---------|
| AUTH-001 | P1 | CONFIRMED | Splash **Signing you in…** without auto-recover; **Try again** required though backend healthy |
| PERF-001 | P2 | CONFIRMED | Cold start **~4s** activity launch on SM-A325F |
| E2E-001 | P0* | CONFIRMED | Full two-sided physical E2E **impossible** with one device |
| TEST-001 | P3 | CONFIRMED | `mvvm_layer_test.dart` logout pattern assertion failed |
| POLL-001 | P2 | LIKELY | Offers/active screens generate **continuous GET polling** (battery/network) |
| IDEM-001 | P2 | LIKELY | Backend in-progress idempotency lock **only on ride create** (backend audit) |
| DOC-001 | P3 | CONFIRMED | `ORA_CURRENT_STATE.md` still says **5C device pending** vs GREEN proof |

\*P0 relative to “full physical E2E” acceptance criterion, not data corruption.

---

## 27. What is GREEN

- Backend ride/offer/progression/rating/expiry/no-show/dispatch **unit/integration** (341 tests)
- Physical **5C pricing** (authenticated, Trio, Lahore, fare visible) — see `p5c_device_proof_report.json`
- Flutter pricing/auth/ride VM **unit tests** (40 pricing-related + broader suite)
- Architecture: server-authoritative pricing snapshots, idempotent mutations (client + server)

---

## 28. YELLOW

- D1 FCM delivery (harness; real FCM optional)
- Dispatch waves (live proof scripts exist; not physical device)
- Auth bootstrap UX on cold launch (functional with retry, poor UX/latency)
- Physical single-user passenger flows beyond pricing

---

## 29. RED

- **Full physical passenger+driver lifecycle** (UNTESTED)
- **Production beta readiness** (overall)
- Automated **performance SLA** evidence (mostly NOT MEASURED)

---

## 30. Recommended next slice

1. **Second physical device** (or scripted two-UID harness with two APK installs) for offer/assign/progression E2E.
2. **Instrumentation-only** run: Firebase Performance or Dart timeline for login, pricing, ride create (no behavior change).
3. **Fix AUTH-001** minimal: splash bootstrap timeout → auto retry `/register`+`/me` (after audit approval).
4. Update **ORA_CURRENT_STATE.md** 5C line to GREEN.

---

*Full section detail for phases 0–21 is in the chat audit deliverable; this file is the durable index + measurements + bug summary.*
