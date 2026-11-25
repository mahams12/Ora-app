# ORA Admin Platform — Dashboard Metrics & Aggregation

**Status:** DRAFT for review — reconciled 2026-11-24
**Core constraint:** no full-collection scans on dashboard load. Three tiers: live bounded `count()` queries for queue depths, scheduled cached aggregates for trends, bounded on-demand reports for drill-down.

**Cost honesty (reconciled):** Firestore `count()` aggregation queries are billed per ~1,000 index entries scanned — **cheap relative to document reads but NOT free**. All figures below marked **ESTIMATE** are planning estimates, not verified billing data. Actual cost depends on collection sizes and index selectivity; validate against Firestore usage metrics before/after launch.

---

## 1. Live operational metrics vs historical analytics (separation)

| Tier | Refresh | Cost profile | Examples |
|---|---|---|---|
| **Live ops** | On dashboard load (poll; no listeners) | Bounded `count()` + small doc fetches; target ≤ ~50 index-entry reads per load | queue depths, active rides by state, online drivers now, outbox backlog |
| **Near-real-time aggregates** | Every 15 min via scheduler job | Window-bounded scans (last 24h) writing tiny `adminMetrics` docs | today's registrations/rides, hourly trends |
| **Historical analytics** | Daily/monthly rollups + on-demand reports | Pre-aggregated docs; reports are bounded queries with mandatory range+cap | 30-day trends, driver performance, city activity, financial sums |

Dashboard API returns cached docs + live queue counts; every section carries `computedAt`/`freshness` so staleness is displayed, never hidden.

---

## 2. Metric catalog

### 2.1 Entity totals (daily aggregate + live deltas)

| Metric | Source | Freshness | Notes |
|---|---|---|---|
| Total registered users | `users` count | daily | — |
| Total active users (`isActive && !banned`) | `users` | daily | — |
| Total passengers / drivers (`role`) | `users` | daily | — |
| Drivers by status | `users.driverStatus` / `drivers.driverStatus` | **live count()** | small cardinality, indexed |
| Drivers online now | see §3 | **live, freshness-gated** | NOT a raw geoDrivers count |
| Vendors | `vendors` | future | Phase 3 |

### 2.2 Application pipeline (live — operational urgency)

| Metric | Source | Notes |
|---|---|---|
| Pending driver applications | `drivers.driverStatus='pending'` count | the queue admins watch |
| Under-review / info-requested counts | same fields | once states exist |
| Queue aging buckets (<24h, 1–3d, >3d) | `onboardingSubmittedAt` | bounded query or aggregate field |
| Approved/rejected last 7d | `adminAuditLogs` action counts | audit-derived = authoritative |

### 2.3 Ride operations (live + daily)

| Metric | Source | Freshness |
|---|---|---|
| Active rides now | `rides.state IN (non-terminal)` count | live count() — `state` index |
| Rides by state | same | live |
| Created/completed/cancelled/expired today | `createdAt`/`completedAt` ranges | 15-min aggregate + live-today |
| Cancellation rate (7d) | counts ratio | daily |
| NO_SHOW count | state transitions | daily |
| Avg time-to-assign | `assignedAt-createdAt` | aggregation job over windowed rides |
| Dispatch efficiency (invites→offers→assigns) | `rideDispatchWaves`, `rideOffers`, `driverInviteResponses` | daily aggregate |

### 2.4 Financial (Phase-gated)

| Metric | Source | Availability |
|---|---|---|
| Gross fare volume (completed) | `agreedFareMinor` sum over window | computable today via bounded aggregation job |
| Platform fees accrued | `platformFeeMinor` sum | computable (≈0 today, launch fee NONE) |
| Driver payouts accrued | `driverPayoutMinor` sum | computable |
| Payment method mix | `paymentMethod` | daily |
| Refunds/payouts outstanding | `refunds`, `driverPayouts` | **collections don't exist** — future |
| Wallet balances | `walletAccounts` | future |

### 2.5 Quality & safety

| Metric | Source |
|---|---|
| Open disputes | `disputes.status='OPEN'` count (live) |
| Disputes by category | `disputes.category` |
| Avg rating received | `ratings` — aggregation job (no stored averages) |
| Low-rating rides (≤2★) | `ratings.stars` |
| Safety events / reports queue | `safetyEvents`/`reports` — future |

### 2.6 Platform health (ops-facing)

| Metric | Source |
|---|---|
| Sweep job success/failures | Cloud Scheduler/Run metrics + `SWEEPS_ALL` logs |
| Outbox backlog (PENDING/CLAIMED/DEAD_LETTER) | `outboxEvents`/`outboxDeliveries` status counts |
| FCM delivery rate | `outboxDeliveries` outcomes |
| API error rate/latency | Cloud Run metrics / structured logs |
| Pricing estimate availability | `PRICING_UNAVAILABLE` 503 rate |

---

## 3. Online-driver accuracy (reconciled — requirement M)

**Do NOT count stale `geoDrivers` records as online.** `geoDrivers/{driverId}` docs persist geo membership + marker fields after a driver goes offline or their marker expires — membership is only cleaned by explicit zrem/del paths.

**"Online now" definition (must match dispatch semantics):**

A driver counts as online only when ALL hold:
1. `drivers/{uid}.availabilityState === 'online'` (durable business state — authoritative), AND
2. `users/{uid}.driverStatus === 'approved'` AND `isActive !== false` AND `banned !== true`, AND
3. geo marker is **fresh**: `markerExpiresAtMs`/`freshUntilMs` not expired AND `lastLocationTs` within the freshness window used by `NearbyDriversService` (`N3_FRESHNESS_MAX_AGE_MS` or per-driver `freshUntilMs`).

This mirrors `isAuthoritativelyEligible` (`nearby_service.ts:750-831`) minus the busy-ride check. Implementation: the aggregator computes per-city online counts during its windowed pass over `geoDrivers` (bounded by active-driver count, not collection size) OR a dedicated `adminMetrics` field updated by the same job; the dashboard "online now" card reads that aggregate with `computedAt` — it is a **15-minute-fresh estimate**, labeled as such, NOT a real-time count. A truly real-time count would require scanning geo markers per request — rejected for cost.

**Consistency rule:** dashboard online count must never exceed what dispatch could actually invite — same freshness + status gates as N3.

---

## 4. Aggregation architecture

```
Cloud Scheduler (existing pattern — wire_*_cloud_scheduler.sh)
   │  every 15 min (proposal; align with existing sweep cadence)
   ▼
POST /v1/internal/admin/aggregate        ← worker-token auth (reuse pattern)
   │
   ├─ window-bounded computations only:
   │    • last-24h rides by state (state+createdAt index)
   │    • registrations by day (users.createdAt)
   │    • fare/payout sums for completed rides in window
   │    • rating aggregates for window
   │    • online-driver snapshot per §3 (bounded geo scan)
   │
   └─ writes adminMetrics/{periodKey} (idempotent upsert)

GET /v1/admin/dashboard/*  ← adminMetrics docs + bounded live count() queries
```

**Cost controls:**
- Aggregation scans are window-bounded (`createdAt >= cutoff`) — never whole-collection.
- `count()` queries for queue depths hit indexes; cost ∝ matching index entries, capped by collection growth — monitor and revisit if users collection grows large (then switch queue depths to maintained counters).
- Dashboard load ≈ ≤ ~50 index-entry reads (ESTIMATE) regardless of data size.
- No real-time listeners; poll on load/refresh.
- Aggregation job itself is bounded work — ESTIMATE < 10k index reads per run at current scale.

**Staleness contract:** responses include `computedAt` per section; UI shows "updated X min ago". Live queue counts are real-time; trend/aggregate metrics are as-of-last-run.

---

## 5. Index requirements (add to `firestore.indexes.json`)

| Collection | Fields | Serves |
|---|---|---|
| `rides` | `state` | active-ride counts |
| `rides` | `state + createdAt` | windowed state counts |
| `rides` | `createdAt` | daily creation counts |
| `rides` | `completedAt` | completion metrics |
| `users` | `createdAt` | registration trends |
| `users` | `role + createdAt` | role growth |
| `drivers` | `driverStatus + onboardingSubmittedAt` | queue age |
| `ratings` | `ratedId + createdAt` | per-driver rating windows |
| `disputes` | `status + createdAt` | dispute queue/trends |
| `adminAuditLogs` | per Data Model §1.2 | audit queries, velocity |

---

## 6. Dashboard screen → API mapping

| Screen widget | API | Tier |
|---|---|---|
| KPI cards | `/dashboard/summary` | cached + live |
| Pending applications depth + aging | `/dashboard/summary` + queue list | live |
| Ride state breakdown | `/dashboard/operations` | live count() |
| Online drivers now | `/dashboard/operations` (aggregate, 15-min fresh) | near-real-time |
| 30-day trends | `/dashboard/timeseries` | cached |
| Driver performance table | `/reports/driver-performance?from&to` | on-demand bounded |
| City activity | `/reports/city-activity` | on-demand bounded |
| Financial summary (future) | `/dashboard/summary` financial section (`finance.read`) | cached |
| Ops health | `/dashboard/operations` health section | live counts + Cloud Monitoring link |

---

## 7. What NOT to build (V1)

- Real-time dashboards (WebSocket/SSE) — polling suffices at admin scale.
- Raw analytics events pipeline — Firestore aggregates suffice.
- Per-user drill-down analytics — admin user detail covers it.
- Financial reconciliation dashboards — blocked on payments.
- Custom report builder — fixed report set only.
- Whole-collection scans of any kind — ever.
