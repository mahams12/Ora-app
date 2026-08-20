# ORA — Latency SLOs & Performance Budgets

**Version:** 0.1.0-architecture  
**Date:** 2026-08-18

---

## 1. Philosophy

Zero network latency is physically impossible.  
Ora's goal is **minimum avoidable application latency** on commodity mobile hardware (mid-range Android, ≥ 3GB RAM, 4G LTE).

All SLOs below are **P95 targets** unless noted. P99 targets are 2× the P95 value.

---

## 2. App Startup SLOs

| Metric | Target P95 | Measurement Method |
|---|---|---|
| Cold start to first frame | < 2.5 s | Flutter DevTools → Timeline; Firebase Performance |
| Cold start to interactive home screen | < 3.5 s | Custom trace: `app_cold_start` |
| Warm start (app resume) | < 800 ms | Custom trace: `app_warm_start` |
| Map SDK ready after home | < 1.5 s | Trace: `map_initialized` |
| Auth token refresh (background) | < 400 ms | Trace: `auth_token_refresh` |

---

## 3. Ride Request Flow SLOs (End-to-End)

| Event | Label | Target P95 | Notes |
|---|---|---|---|
| T0 | Passenger taps "Confirm" | 0 (baseline) | |
| T1 | App sends POST /rides to server | T0 + 50 ms | Local processing + network queue |
| T2 | Server receives & validates | T1 + 100 ms | Cloud Run API processing |
| T3 | Ride document created in Firestore | T2 + 150 ms | Firestore write |
| T4 | Driver candidate list generated via Redis GEO | T3 + 80 ms | Redis GEORADIUS query |
| T5 | FCM + RTDB push to drivers | T4 + 200 ms | FCM delivery; RTDB propagation |
| T6 | Driver app receives and renders request | T5 + 300 ms | FCM + RTDB listener render |
| **Total T0→T6** | | **< 900 ms P95** | Foreground connected-listener path only |

| Event | Label | Target P95 | Notes |
|---|---|---|---|
| T6 | Driver taps Accept or Counter | 0 (sub-baseline) | Creates offer, not assignment |
| T7 | App sends POST /rides/{id}/offers | T6 + 50 ms | |
| T7b | Passenger sends POST /rides/{id}/offers/{offerId}/select | after offer inbox | Assignment command |
| T8 | Server optional lock + Firestore assignment txn | T7b + 120 ms | Select transaction |
| T9 | Assignment event emitted (RTDB + FCM) | T8 + 80 ms | Fan-out |
| T10 | Passenger app receives event | T9 + 200 ms | Firestore/RTDB listener |
| T11 | Passenger UI updated with driver info | T10 + 50 ms | Widget rebuild |
| **Total select→UI** | | **< 500 ms P95** | Foreground connected-listener path only |

**Dispatch delivery (T0→T6): < 900 ms P95** for foreground connected clients.  
**Assignment after select (select→UI): < 500 ms P95**. End-to-end booking time includes passenger comparison and is not an assignment SLO.

Background and killed-app paths are measured separately and are not held to the same foreground SLO.

---

## 4. Location Update SLOs

| Metric | Target P95 | Notes |
|---|---|---|
| GPS fix to RTDB write | < 300 ms | Client → RTDB write path |
| RTDB write to passenger listener fire | < 150 ms | RTDB propagation |
| Passenger renders new driver position | < 50 ms | Widget rebuild |
| **Total GPS-to-passenger-marker** | **< 500 ms P95** | Perceived lag in driver marker movement |
| Stale location detection | < 8 s | Server marks location stale if no update |

---

## 5. Navigation Transition SLOs

| Metric | Target P95 |
|---|---|
| Screen push transition | < 300 ms (60fps smooth) |
| Screen pop transition | < 300 ms |
| Bottom sheet open | < 200 ms |
| Map camera animate | < 400 ms |
| Route polyline render | < 500 ms after route data arrives |

---

## 6. API Endpoint SLOs (Server-Side, P95)

| Endpoint | Target |
|---|---|
| POST /rides | < 300 ms |
| POST /rides/{id}/offers | < 200 ms |
| POST /rides/{id}/offers/{offerId}/select | < 200 ms |
| GET /rides/{id} | < 100 ms |
| POST /pricing/estimate | < 400 ms (includes Google Routes call) |
| GET /drivers/nearby | < 150 ms (Redis GEO) |
| POST /rides/{id}/status | < 200 ms |
| POST /payments/confirm | < 500 ms (PSP dependent) |

---

## 7. Frame Rendering Budget

| Metric | Target | Flutter Principle |
|---|---|---|
| Frame render time | < 16.67 ms (60fps) | Never block UI isolate |
| Jank rate (slow frames) | < 1% | Measured via Flutter DevTools |
| Expensive build() calls | 0 | No synchronous I/O in build() |
| Unnecessary rebuilds | Minimize | Use `select()` / `watch` scoping |
| List items (driver cards) | < 2 ms per item | Use ListView.builder; const where possible |

---

## 8. Firestore Read Budget (per session)

| Operation | Budget per session |
|---|---|
| Auth read (user doc) | 1 read |
| Ride state listener | 1 snapshot + deltas (free after first) |
| Driver profile (on assign) | 1 read |
| Ride history (My Rides) | 1 paginated query (10 docs) |
| Saved places | 1 read (cached locally) |
| Pricing rules | 1 read (cached 1 hour) |
| **Total cold session** | **< 20 reads** |

**Anti-patterns that are FORBIDDEN:**
- Polling Firestore in a loop
- Listening to a collection without where clauses
- Reading ride document on every GPS update
- Fetching all rides without pagination

---

## 9. Network Data Budget (per active trip)

| Stream | Budget per minute |
|---|---|
| GPS uploads (driver) | ~6 KB/min (60 updates × 100 bytes) |
| GPS downloads (passenger) | ~6 KB/min |
| Firestore state deltas | ~1 KB/min |
| FCM overhead | Negligible |
| **Total active trip** | **< 15 KB/min** |

---

## 10. SLO Violation Response

| Violation | Threshold | Action |
|---|---|---|
| T0→T6 > 2 s | P95 | PagerDuty alert; investigation |
| T6→T11 > 1 s | P95 | PagerDuty alert |
| API P99 > 1 s | Any endpoint | Auto-scale + alert |
| Jank rate > 5% | Client-wide | Crash-priority Flutter performance fix |
| GPS stale > 30 s | Active trip | UI warning to passenger; server flag |
| Cold start > 5 s | P95 | Performance sprint |
