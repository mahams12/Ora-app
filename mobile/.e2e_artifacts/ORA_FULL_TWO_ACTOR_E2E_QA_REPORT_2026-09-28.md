# ORA FULL TWO-ACTOR E2E QA REPORT

**Run window (UTC):** 2026-09-28T07:54:49 – ~08:02 (continuation after driver-env fix)  
**Report generated:** 2026-09-28 ~12:58 PKT  
**Scope:** Emulator = passenger · Samsung = driver · real app + LaunchAgent backend · **no Firestore seeding**

---

## Environment

| Item | Evidence |
|------|----------|
| **Samsung (DRIVER)** | `RF8R40ZQ1JH` · SM-A325F · USB connected |
| **Emulator (PASSENGER)** | `emulator-5554` · Pixel 9 Pro AVD |
| **Backend** | **UP** · `http://127.0.0.1:8080/healthz` · PID 86151 |
| **ADB reverse** | `tcp:8081 → tcp:8080` on both devices |
| **APK / build** | Rebuilt **2026-09-28 12:49:31 PKT** · `app-debug.apk` · `ORA_API_BASE_URL=http://127.0.0.1:8081/v1` · installed Samsung **12:49:52** · emulator updated **12:54** (same artifact) |
| **Accounts** | Passenger `+923012345678` / `123456` · Driver `+923012345677` / `000000` |

---

## SINGLE RIDE CORRELATION

| Field | Value |
|-------|--------|
| **rideId** | `03f8825a-9f70-4a35-83fd-c57801dde969` |
| **requestVersion** | `1` |
| **pricingSnapshotId** | `ps_efb8dac5-4175-4db3-838c-2276cf808e23` |
| **Category** | `easy` |
| **Created (UTC)** | `2026-09-28T07:57:18.474Z` |
| **Expires (UTC)** | `2026-09-28T08:02:18.474Z` (5 min TTL) |

---

## RESULTS

| Gate | Status | Notes |
|------|--------|--------|
| Auth | **GREEN** | Driver gate verified pre-run; run4 `driver_ready` **GREEN** |
| Passenger | **GREEN** | Compose + review reached on emulator |
| Pricing | **GREEN** | Server estimate **Rs 310** · 3.6 km · ~9 min (see integrity) |
| Ride creation | **GREEN** | UI **Waiting for offers** · Firestore `SEARCHING` (script falsely reported RED — see errors) |
| Driver discovery | **GREEN** | Open rides list showed **same** Liberty / Current location ride · Rs 310 |
| Driver offer | **RED** | **0 offers** in Firestore; offer sheet **not opened** via ADB taps on **Respond** |
| Passenger offer | **RED** | No **Select** — no backend offer |
| Assignment | **BLOCKED** | — |
| EN_ROUTE | **BLOCKED** | — |
| ARRIVED | **BLOCKED** | — |
| STARTED | **BLOCKED** | — |
| COMPLETED | **BLOCKED** | — |
| RIDE_CLOSED | **BLOCKED** | — |
| Ratings | **N/A** | Not reached |

---

## PRICING INTEGRITY (ride `03f8825a…`)

| Field | Value |
|-------|--------|
| Distance | **3.576 km** |
| Duration | **~9.43 min** (stored fractional; UI ~9 min) |
| Recommended | **31000 minor** → **Rs 310** |
| Passenger offer | **31000 minor** → **Rs 310** |
| Driver display | **Rs 310** passenger/recommended on open-ride card |
| Minor units in offer UI | **P2** — sheet source exposes minor units + `POST /v1/rides/...` copy (known) |
| **Verdict** | **SERVER-DERIVED** (not hardcoded; snapshot tied to `pricingSnapshotId`) |

---

## PERFORMANCE (measured only)

| Step | Seconds |
|------|---------|
| Pricing retry (run4) | **22.3** |
| Driver discovery (continuation) | ~**6** swipe + poll (not isolated HTTP) |

---

## CRASHES / ERRORS

| When | Device | Evidence |
|------|--------|----------|
| run4 exit | Emulator | Script **`request button missing`** while UI already on **Waiting for offers** (`qa_p_price2_ui.xml`) — automation false negative |
| Offer continuation | Samsung | `tap_desc('Respond')` did not open bottom sheet; `cont_offer2.xml` still open-list; **offers: []** in snapshot |
| UiAutomator | Both | Intermittent **`could not get idle state`** / null root (non-fatal dumps) |

---

## UX DEFECTS (observed on open rides)

| Sev | Type | Detail |
|-----|------|--------|
| **P2** | DEFECT | Driver open rides: verbose “servers / not GPS feed” header |
| **P2** | DEFECT | **km (server)** · **min (server)** labels on cards |
| **P2** | DEFECT | Offer sheet: **Amount (minor units)**, **POST /v1/...**, engineering copy (code + prior audits) |
| **P3** | RECOMMENDATION | Passenger offers: long “not inventing nearby drivers” copy |

---

## BACKEND / FIRESTORE (last snapshot)

```json
{
  "rideId": "03f8825a-9f70-4a35-83fd-c57801dde969",
  "state": "SEARCHING",
  "assignedDriverId": null,
  "offers": []
}
```

Ride may have **expired** at `08:02:18Z` before a successful offer POST.

---

## FINAL VERDICT

**RED** — One correlated ride was **created** and **discovered** on the driver device, but **no offer was durably submitted**, so assignment and lifecycle were **not proven**.

---

## Follow-up (no product changes in this run)

1. **Automation:** After pricing, accept **Waiting for offers** as ride-create success; tap **Respond** at button bounds (~bottom of card, e.g. y≈1480 on Samsung 1080p) or add semantics on **Respond** `OraButton` for reliable UiAutomator.
2. **TTL:** Complete offer within **5 minutes** of create (or extend TTL for QA only — product decision).
3. **Identity:** Keep Samsung on **+923012345677** before driver steps (script updated to avoid passenger skip-on-home).
4. **Re-run:** Fresh single ride after offer automation fix; do not use stale SEARCHING rides in list.

**Artifacts:** `qa_full_e2e_run4.out`, `qa_p_price2_ui.xml`, `cont_disc.xml`, `cont_offer2.xml`, `qa_full_two_actor_e2e.py` (patched).
