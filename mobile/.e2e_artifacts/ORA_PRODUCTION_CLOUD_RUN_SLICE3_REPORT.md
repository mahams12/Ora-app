# Ora production hardening — slice 3 (Production Cloud Run foundation)

**Date/time:** 2026-09-30 (PKT, post-deploy verification)  
**Scope:** Infrastructure only. No N3/D1/ride/pricing logic/mobile UI changes. Slices 1–2 not reopened.

---

## 1. Production project

**`ora-app-d8112`** (same GCP/Firebase project as staging; separate Cloud Run / secrets / Redis / jobs / scheduler names per repo strategy).

---

## 2. Production Cloud Run service

**`ora-auth-service`**

---

## 3. Revision

**`ora-auth-service-00001-mwc`** (100% traffic at deploy time)

---

## 4. Region

**`us-central1`**

---

## 5. Production URL

- Service URL: `https://ora-auth-service-2zmxvrrs7a-uc.a.run.app`
- API base (written to `mobile/.production_api_url`): `https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/v1`
- Health: `GET /healthz/` → **200** `{"ok":true,"service":"ora-auth-service"}`

---

## 6. Runtime service account

**`firebase-adminsdk-fbsvc@ora-app-d8112.iam.gserviceaccount.com`**

Cloud Run env: `ORA_ENV=production`, `REQUIRE_APP_CHECK=true`, `NODE_ENV=production`, `FIREBASE_PROJECT_ID=ora-app-d8112`.

---

## 7. Secret Manager secret names (production)

| Env var | Secret |
|---------|--------|
| `REDIS_URL` | `ora-production-redis-url` |
| `GOOGLE_MAPS_SERVER_KEY` | `ora-production-google-maps-server-key` |
| `ORA_INTERNAL_WORKER_TOKEN` | `ora-production-internal-worker-token` |

Revision uses `secretKeyRef` for all three (no plaintext secret env on service).

---

## 8. IAM roles added (documented)

| Principal | Role | Purpose |
|-----------|------|---------|
| `firebase-adminsdk-fbsvc@…` | `roles/secretmanager.secretAccessor` | Per-secret binding on the three production secrets (via wire scripts) |
| `ora-prod-sched-invoker@ora-app-d8112.iam.gserviceaccount.com` | `roles/run.jobsExecutor` | Cloud Scheduler OAuth → Cloud Run Jobs API `:run` |

No project Owner/Editor grants added for this slice.  
**Note:** Initial scheduler wiring failed with SA id `ora-production-scheduler-invoker` (>30 chars); fixed to **`ora-prod-sched-invoker`**.

---

## 9. Redis target

- **Instance:** `ora-production-n3-redis` (Memorystore, `us-central1`, BASIC 1 GiB)
- **Endpoint:** private IP `10.52.25.131:6379` (via `ora-production-redis-url` secret)
- **VPC connector:** `ora-staging-vpc` (shared connector name with staging; separate Memorystore instances)

Staging Redis remains **`ora-staging-n3-redis`** / `ora-staging-redis-url` (distinct host).

---

## 10. Worker Cloud Run Jobs created

| Job | Internal path |
|-----|----------------|
| `ora-production-worker-expire-sweep` | `POST /v1/internal/rides/expire-sweep` |
| `ora-production-worker-offer-expire-sweep` | `POST /v1/internal/rides/offer-expire-sweep` |
| `ora-production-worker-dispatch-sweep` | `POST /v1/internal/rides/dispatch-sweep` |
| `ora-production-worker-dispatch-fcm-sweep` | `POST /v1/internal/outbox/dispatch-fcm-sweep` |
| `ora-production-worker-no-show-sweep` | `POST /v1/internal/rides/no-show-sweep` |
| `ora-production-worker-expires-at-cleanup` | `POST /v1/internal/storage/expires-at-cleanup` |

Jobs use image from `ora-auth-service`, runtime SA above, `ORA_INTERNAL_WORKER_TOKEN` from Secret Manager, `WORKER_API_BASE_URL` from `mobile/.production_api_url`, invoke via `scripts/staging_worker_http_invoke.mjs`.

---

## 11. Scheduler jobs created

| Scheduler | Target Run Job |
|-----------|----------------|
| `ora-production-sched-expire-sweep` | `ora-production-worker-expire-sweep` |
| `ora-production-sched-offer-expire-sweep` | `ora-production-worker-offer-expire-sweep` |
| `ora-production-sched-dispatch-sweep` | `ora-production-worker-dispatch-sweep` |
| `ora-production-sched-dispatch-fcm-sweep` | `ora-production-worker-dispatch-fcm-sweep` |
| `ora-production-sched-no-show-sweep` | `ora-production-worker-no-show-sweep` |
| `ora-production-sched-expires-at-cleanup` | `ora-production-worker-expires-at-cleanup` |

Location: `us-central1`, state **ENABLED**.

---

## 12. Scheduler cadences (UTC)

| Job | Cron |
|-----|------|
| expire / offer / dispatch / dispatch-fcm | `* * * * *` |
| no-show | `*/5 * * * *` |
| expires-at cleanup | `*/15 * * * *` |

---

## 13. Health check

**PASS** — `GET /healthz/` → **HTTP 200**

---

## 14. Auth smoke (unauthenticated)

**PASS** — proves request reaches app and gates are active:

- `GET /v1/auth/me` → **401** (`APP_CHECK_REQUIRED` — App Check enforced before Firebase auth on `/v1/*`)
- `POST /v1/auth/me` → **401** (same)

Response bodies contain `requestId` only; no secrets.

---

## 15. Pricing smoke (`POST /v1/pricing/estimate`)

**NOT FULLY VERIFIED (App Check gate — by design for production startup)**

Script: `npx tsx scripts/verify_production_smoke.ts`

| Check | Result |
|-------|--------|
| Authenticated custom token (existing test phone `+923012345678`) | OK |
| `POST /v1/pricing/estimate` | **HTTP 401**, `error.code` = **`APP_CHECK_REQUIRED`** |
| `PRODUCTION_APP_CHECK_DEBUG_TOKEN` in local `.env` | **Not set** |

Production requires `REQUIRE_APP_CHECK=true` (`production_guards.ts`). Full **HTTP 200** pricing proof (snapshot, fare, Routes-backed fields) is **Slice 4** work: register App Check debug token and/or ship mobile App Check — **not implemented in this slice**.

---

## 16. Worker manual execution (each job)

All six jobs: `gcloud run jobs execute … --wait` → **Completed / succeededCount=1**, invoke log `httpStatus: 200`, `ok: true` for paths such as `/internal/rides/dispatch-sweep`.

Production **service** logs (sample operations after runs):

- `RIDE_EXPIRE_SWEEP`, `RIDE_OFFER_EXPIRE_SWEEP`, `N4_DISPATCH_SWEEP`, `D1_DISPATCH_FCM_SWEEP`, `RIDE_NO_SHOW_SWEEP`, `EXPIRES_AT_CLEANUP` (with `requestId` values present in Cloud Logging).

---

## 17. Scheduler manual trigger

**PASS** — `gcloud scheduler jobs run ora-production-sched-expire-sweep` → execution `ora-production-worker-expire-sweep-h5tjw` **completed successfully** (`succeededCount: 1`).

---

## 18. Invalid / missing worker token (internal)

| Case | HTTP | Code |
|------|------|------|
| `POST /v1/internal/rides/dispatch-sweep` (no token) | **403** | `FORBIDDEN` |
| Same with `X-Ora-Worker-Token: invalid-token-test` | **403** | `FORBIDDEN` |

---

## 19. Secret-leak verification

| Check | Result |
|-------|--------|
| Scheduler HTTP target | OAuth + Run Jobs API URI only; **no** `X-Ora-Worker-Token`, Maps, or Redis |
| Cloud Run revision | Secrets via Secret Manager refs only |
| This report / scripts | No secret values printed or committed |
| Curl/auth error bodies | No secret material |

**Follow-up (ops):** Prefer a **production-dedicated, API-restricted** Google Maps server key; initial prod secret was bootstrapped from local `.env` (gitignored), not copied into git.

---

## 20. Staging / production isolation

| Dependency | Staging | Production | Shared? |
|------------|---------|------------|---------|
| GCP/Firebase project | `ora-app-d8112` | `ora-app-d8112` | **Yes** |
| Firestore | `(default)` | `(default)` | **Yes — ride/user data not env-isolated** |
| Firebase Auth users | same project | same project | **Yes** |
| Cloud Run service | `ora-auth-service-staging` | `ora-auth-service` | No |
| Revision (verified) | `ora-auth-service-staging-00024-4wv` | `ora-auth-service-00001-mwc` | No |
| Redis | `ora-staging-n3-redis` | `ora-production-n3-redis` | No |
| Redis secrets | `ora-staging-redis-url` | `ora-production-redis-url` | No |
| Maps secret | `ora-staging-google-maps-server-key` | `ora-production-google-maps-server-key` | No |
| Worker token secret | `ora-staging-internal-worker-token` | `ora-production-internal-worker-token` | No |
| Run Jobs | `ora-staging-worker-*` | `ora-production-worker-*` | No |
| Scheduler | `ora-staging-sched-*` | `ora-production-sched-*` | No |
| Scheduler SA | `ora-staging-scheduler-invoker@…` | `ora-prod-sched-invoker@…` | No |
| VPC connector | `ora-staging-vpc` | `ora-staging-vpc` (name) | **Same connector resource** |
| Runtime SA | `firebase-adminsdk-fbsvc@…` | same | **Yes** |

Staging regression: `GET …/healthz/` on **`ora-auth-service-staging`** → **200**; staging revision unchanged by prod deploy.

---

## 21. Backend tests

**391/391 PASS** — `npm test -- --run`

---

## 22. Build

**PASS** — `npm run build`

---

## 23. Blockers / risks

1. **Pricing smoke 200** — blocked on App Check token (Slice 4); prod correctly returns `APP_CHECK_REQUIRED`.
2. **Firestore / Auth** — production and staging share one database and user pool until a separate project or database strategy is chosen.
3. **Maps key** — ensure production key has correct API restrictions and rotation policy.
4. **VPC connector naming** — production uses `ora-staging-vpc`; acceptable for now but rename/document for clarity in a future ops pass.
5. **Mobile** — no `production_api_url` wiring in Flutter yet; prod backend URL file is ops-only until release slice.

---

## 24. Remaining work (Slice 4+)

- Firebase App Check: debug token for automated prod smokes and/or production mobile attestation.
- Re-run `verify_production_smoke.ts` for full **pricing/estimate 200** (snapshot, fare, distance/duration, rules version, Routes).
- Custom domain / `api.ora.app` if required for release.
- Production Flutter build pointing at `mobile/.production_api_url` (or flavor-specific config).
- Optional: dedicated Firebase project or Firestore database for true prod data isolation.
- Dedicated production Maps key restriction audit and worker token rotation runbook.

---

## 25. Artifacts added/updated

| Path | Role |
|------|------|
| `backend/auth-service/scripts/deploy_production_cloud_run.sh` | Prod Cloud Run deploy |
| `backend/auth-service/scripts/wire_production_redis.sh` | Prod Memorystore + redis secret |
| `backend/auth-service/scripts/wire_production_server_secrets.sh` | Prod Maps + worker secrets |
| `backend/auth-service/scripts/wire_production_cloud_scheduler.sh` | Prod jobs + scheduler (SA fix) |
| `backend/auth-service/scripts/verify_production_smoke.ts` | Health / auth / pricing smoke |
| `docs/operations/production-remote-backend.md` | Ops doc |
| `mobile/.production_api_url` | Generated HTTPS `/v1` base (not for staging) |

---

## Final verdict

**PRODUCTION CLOUD RUN SLICE = GREEN**

Evidence: production Cloud Run deployed with Secret Manager secrets and separate Redis; health **200**; unauthenticated `/v1/auth/me` **401**; internal worker **403** without token; six worker jobs and six schedulers wired (OAuth → Jobs API, no scheduler secrets); all manual job runs and one scheduler trigger **succeeded**; service logs show expected sweep operations; staging unchanged (**00024-4wv**, health **200**); **391/391** tests and build **PASS**.

**Caveat (documented, not infra failure):** Phase 6 pricing **200** not demonstrated until App Check is configured (Slice 4).
