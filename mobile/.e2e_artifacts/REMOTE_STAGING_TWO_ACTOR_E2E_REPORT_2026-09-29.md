# Remote staging two-actor E2E — finish report (2026-09-29)

**Remote API:** `https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app/v1`  
**Devices:** Samsung `RF8R40ZQ1JH` (passenger), emulator `emulator-5554` (driver)  
**No local backend, no `adb reverse`, no `pm clear` on emulator after driver auth.**

## Verdict

**REMOTE TWO-ACTOR E2E = GREEN**

All gates were completed through the real apps and verified in Firestore (`rideOffers` + `rides`).

---

## AUTH

| Device   | Result |
|----------|--------|
| Samsung  | **PASS** |
| Emulator | **PASS** (Open rides / driver shell; no GMS WebView block) |

`/v1/auth/me` via custom token was skipped in automation (`custom_token_failed` in ops helper); assignment and lifecycle prove driver identity.

---

## MARKETPLACE

| Gate                         | Result |
|------------------------------|--------|
| Passenger pricing            | **PASS** (Rs on review; server pricing) |
| Ride creation                | **PASS** |
| Driver discovery             | **PASS** |
| Respond                      | **PASS** |
| Driver offer                 | **PASS** |
| Passenger offer selection    | **PASS** |
| Assignment                   | **PASS** |
| EN_ROUTE                     | **PASS** |
| ARRIVED                      | **PASS** |
| STARTED                      | **PASS** |
| COMPLETED                    | **PASS** |
| RIDE_CLOSED                  | **PASS** |

**Respond UX:** Offer sheet showed **Passenger offer: Rs 1140** — no “minor units” / API jargon (`fin_sheet.xml`, run 4).

---

## BACKEND PROOF

| Field | Value |
|-------|--------|
| **rideId** | `1820535b-e702-4740-bca0-4f939730874d` |
| **requestVersion** | `1` |
| **pricingSnapshotId** | `ps_eb8944e5-eae4-4e36-9aa3-d83616d7ebf1` |
| **passengerOfferMinor** | `114000` (Rs 1140) |
| **driverOfferMinor** | `114000` (Rs 1140, `PASSENGER_PRICE_ACCEPTED`) |
| **assignedDriverId** | `SRjL7BJgCKTduhtpjtYMRZMq5fD2` |
| **passengerId** | `AQLQjCfBw3W17kfgzziM6po1Nh33` |
| **final state** | `RIDE_CLOSED` |
| **agreedOfferId** | `1820535b-e702-4740-bca0-4f939730874d_SRjL7BJgCKTduhtpjtYMRZMq5fD2_v1` |
| **Timestamps** | assigned `2026-09-29T09:40:09.579Z`, arrived `09:42:06.603Z`, started `09:42:16.579Z`, completed `09:42:28.587Z`, closed `09:42:38.665Z` |

**Integrity:** Exactly **one** `rideOffers` doc for this ride/driver/requestVersion; status `SELECTED`; no duplicate assignment.

---

## Ops notes (not product changes)

1. **Driver offer “false fail”:** Offers live in top-level `rideOffers`, not `rides/{id}/offers`. Fixed `backend/auth-service/scripts/e2e_ride_snapshot.ts` for proof scripts only.
2. **Submit offer tap:** Automation must hit the **Button** labeled `Submit offer`, not the sheet heading (same class of bug as Respond hit-target).
3. **Passenger compose:** Mock GPS + `Liberty%sMarket%sLahore` Places search; do **not** tap the “Lahore” city chip on review (navigates away from Request Easy).
4. **Driver lifecycle:** Primary actions are on **My trips → assigned ride detail**, not Open rides.

Artifacts: `finish_remote_two_actor_e2e.py`, `fin_*.xml`, `life_*.xml`, `finish_remote_two_actor_report.json`.

---

## Earlier blocker (resolved)

Emulator driver recovery after prior `pm clear` GMS overlay — resolved without further `pm clear`. Session remained stable through GREEN run.
