# Ora production hardening — slice 2 (Cloud Scheduler / worker automation)

**Date:** 2026-09-30  
**Staging service revision (post-invoker image):** `ora-auth-service-staging-00024-4wv` (100% traffic)  
**Prior slice 1 revision:** `ora-auth-service-staging-00023-rvf`  
**No changes to N3, D1, ride lifecycle, pricing logic, auth middleware, Firestore schema, Redis, or mobile UI.**

---

## A. Worker endpoint inventory

Base path prefix on service: **`/v1/internal`** (worker middleware on entire router).  
All listed routes require **`X-Ora-Worker-Token`** (shared secret from Secret Manager on Cloud Run).

| Method | Path | Purpose | Idempotent | Cadence (staging) | Normal response | Firestore | Redis | Auto-schedule? |
|--------|------|---------|------------|-------------------|-----------------|-----------|-------|----------------|
| POST | `/rides/expire-sweep` | Expire SEARCHING rides past TTL | Yes (safe repeat) | `* * * * *` (1 min)† | 200 + sweep stats | Yes | No | **Yes** |
| POST | `/rides/offer-expire-sweep` | Expire stale offers | Yes | `* * * * *` | 200 + stats | Yes | No | **Yes** |
| POST | `/rides/dispatch-sweep` | N4 wave sweeper | Yes | `* * * * *` | 200 + stats | Yes | Yes (N3) | **Yes** |
| POST | `/outbox/dispatch-fcm-sweep` | D1 FCM projector sweep | Yes | `* * * * *` | 200 + stats | Yes | No | **Yes** |
| POST | `/rides/no-show-sweep` | NO_SHOW after wait | Yes | `*/5 * * * *` | 200 + stats | Yes | No | **Yes** |
| POST | `/storage/expires-at-cleanup` | TTL cleanup (idempotency/snapshots/streams) | Yes | `*/15 * * * *` | 200 + stats | Yes | No | **Yes** |
| POST | `/rides/:rideId/dispatch-tick` | Single-ride N4 tick | Per ride | — | 200 | Yes | Yes | **No** (ops/tests) |
| GET | `/drivers/nearby` | N3 candidate discovery | Read | — | 200 | Yes | Yes | **No** (on-demand / bench) |

† Docs reference ~30s ride expiry sweeps (`matching-engine.md`); **Cloud Scheduler minimum cron interval is 1 minute** — staging uses 1-minute jobs.

---

## B. Scheduler jobs created

| Scheduler job | Target |
|---------------|--------|
| `ora-staging-sched-expire-sweep` | Cloud Run Job `ora-staging-worker-expire-sweep` |
| `ora-staging-sched-offer-expire-sweep` | `ora-staging-worker-offer-expire-sweep` |
| `ora-staging-sched-dispatch-sweep` | `ora-staging-worker-dispatch-sweep` |
| `ora-staging-sched-dispatch-fcm-sweep` | `ora-staging-worker-dispatch-fcm-sweep` |
| `ora-staging-sched-no-show-sweep` | `ora-staging-worker-no-show-sweep` |
| `ora-staging-sched-expires-at-cleanup` | `ora-staging-worker-expires-at-cleanup` |

Location: `us-central1` · State: **ENABLED**

---

## C. Schedule / cadence

| Scheduler | Cron (UTC) |
|-----------|------------|
| expire / offer / dispatch / FCM | `* * * * *` |
| no-show | `*/5 * * * *` |
| expires-at cleanup | `*/15 * * * *` |

---

## D. Secure authentication mechanism

**Limitation (documented):** Cloud Scheduler HTTP targets **do not** support Secret Manager injection into custom headers such as `X-Ora-Worker-Token`. Putting the token in Scheduler job headers would store it in the Scheduler job resource (plaintext at rest in GCP API).

**Architecture used (no auth model change):**

1. **Cloud Scheduler** → `POST` **Run Jobs API** `:run` with **OAuth** (`ora-staging-scheduler-invoker@…`, scope `cloud-platform`). Scheduler config contains **no worker token** (only `User-Agent: Google-Cloud-Scheduler` + OAuth).
2. **Cloud Run Job** (same image as auth-service) runs `scripts/staging_worker_http_invoke.mjs` with:
   - `ORA_INTERNAL_WORKER_TOKEN` from Secret Manager `ora-staging-internal-worker-token:latest`
   - `STAGING_API_BASE_URL` (HTTPS, non-secret)
   - `WORKER_INVOKER_PATH` / `WORKER_INVOKER_METHOD`
3. Job performs HTTPS request to **staging Cloud Run service** with `X-Ora-Worker-Token` header (existing middleware unchanged).

Runtime SA for jobs: `firebase-adminsdk-fbsvc@…` (secret accessor). Scheduler SA: `ora-staging-scheduler-invoker@…` with `roles/run.jobsExecutor`.

---

## E. Manual execution

| Run | Result |
|-----|--------|
| `gcloud run jobs execute ora-staging-worker-expire-sweep --wait` | **Completed / True** |
| `ora-staging-worker-dispatch-sweep` | **Completed / True** |
| `ora-staging-worker-dispatch-fcm-sweep` | **Completed / True** |
| `ora-staging-worker-expires-at-cleanup` | **Completed / True** |
| `gcloud scheduler jobs run ora-staging-sched-dispatch-sweep` | **Triggered** (no error) |

---

## F. Cloud Run HTTP result

Worker jobs exited **0**; staging service logs show sweep operations with **requestId** (not 503):

- `RIDE_EXPIRE_SWEEP`
- `N4_DISPATCH_SWEEP`
- `D1_DISPATCH_FCM_SWEEP`
- `EXPIRES_AT_CLEANUP`

Example requestIds: `b3a0f26f-e30a-4d7f-8c86-3774cb588569`, `880ab2cd-da31-4e30-afe4-c73765409047`, `985fc40e-5dba-4e0d-ac7c-835fdb7841fa`, `f6ec7c7b-73f2-4300-8fe8-d90ab03e99e3`.

---

## G. Logs / request IDs

Structured `logSafe` operations on **auth-service-staging** confirm worker invocations from jobs. Job container stdout does not log token values.

---

## H. Negative authorization

| Test | Result |
|------|--------|
| `POST /v1/internal/rides/dispatch-sweep` **without** worker header | **HTTP 403** `FORBIDDEN` (not 503) |
| Same with invalid token (slice 1) | **403** |

Proves worker secret is **configured** on service and unauthenticated calls remain rejected.

---

## I. Secret-leak check

- Scheduler job describe: **OAuth + Run API URI only** — no `X-Ora-Worker-Token` in scheduler headers.
- Cloud Run **service** revision: Maps/worker/Redis remain Secret Manager–backed (slice 1).
- Worker token only on **Cloud Run Job** secret env (not in git, not in scheduler YAML committed to repo).
- **Recommendation:** Rotate Maps key if prior plaintext revision exposure is still a concern (slice 1 audit).

---

## J. Tests

`npm test -- --run` → **391/391** pass.

---

## K. Build

`npm run build` → **PASS**

---

## L. Remaining production blockers

| Blocker | Notes |
|---------|--------|
| Production Cloud Run + DNS | Not created (staging only) |
| App Check enforcement | Staging `REQUIRE_APP_CHECK=false` |
| Release mobile build | Debug staging APK / App Check off |
| Maps key rotation | If plain env on old revisions was exposed |
| Scheduler cadence vs product | 1-min minimum vs 30s doc target — tune in prod |
| Flutter widget tests | 2 failures (unchanged) |

---

## Repo / ops artifacts

| File | Role |
|------|------|
| `scripts/staging_worker_http_invoke.mjs` | Job entry (HTTPS + header from env) |
| `scripts/wire_staging_cloud_scheduler.sh` | Idempotent Scheduler + Run Job wiring |
| `Dockerfile` | COPY invoke script into image |
| `docs/operations/staging-remote-backend.md` | Scheduler architecture note |

Wire command:

```bash
./scripts/deploy_staging_cloud_run.sh
./scripts/wire_staging_cloud_scheduler.sh
```

---

**CLOUD SCHEDULER SLICE = GREEN**

**NEXT REQUIRED ACTION = Rotate/restrict the Google Maps server API key if still exposed from pre–Secret Manager revisions; then plan production Cloud Run + `REQUIRE_APP_CHECK=true` + release mobile build.**
