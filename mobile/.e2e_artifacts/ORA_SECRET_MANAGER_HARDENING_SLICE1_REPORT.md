# Ora production hardening — slice 1 (Secret Manager + Cloud Run)

**Date:** 2026-09-30  
**Prior revision:** `ora-auth-service-staging-00022-bkc`  
**New revision:** `ora-auth-service-staging-00023-rvf`  
**Service URL:** `https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app`  
**Traffic:** 100% → `00023-rvf`

No changes to N3, D1, ride lifecycle, pricing logic, auth middleware, mobile UI, Firestore schema, or Redis behavior.

---

## A. Secrets created/reused (names only)

| Secret | Action |
|--------|--------|
| `ora-staging-google-maps-server-key` | **Created** (version 1) |
| `ora-staging-internal-worker-token` | **Created** (version 1) |
| `ora-staging-redis-url` | **Reused** (unchanged) |

---

## B. Secret versions / status (no values)

| Secret | Latest version | State |
|--------|----------------|-------|
| `ora-staging-google-maps-server-key` | 1 | enabled |
| `ora-staging-internal-worker-token` | 1 | enabled |
| `ora-staging-redis-url` | (existing) | enabled |

Runtime SA `firebase-adminsdk-fbsvc@ora-app-d8112.iam.gserviceaccount.com` has `roles/secretmanager.secretAccessor` on the new Maps and worker secrets (same pattern as Redis).

---

## C. Cloud Run revision

`ora-auth-service-staging-00023-rvf`

---

## D. Secret-backed env verification

Revision env (no plaintext for sensitive keys):

| Env var | Binding |
|---------|---------|
| `REDIS_URL` | Secret `ora-staging-redis-url:latest` |
| `GOOGLE_MAPS_SERVER_KEY` | Secret `ora-staging-google-maps-server-key:latest` |
| `ORA_INTERNAL_WORKER_TOKEN` | Secret `ora-staging-internal-worker-token:latest` |
| `FIREBASE_PROJECT_ID`, `REQUIRE_APP_CHECK`, `ORA_ENV`, `NODE_ENV` | Plain (non-secret config) |

**No plaintext** `GOOGLE_MAPS_SERVER_KEY` or `ORA_INTERNAL_WORKER_TOKEN` on revision `00023-rvf`.

---

## E. Health

`GET /healthz/` → **HTTP 200** (`{"ok":true,"service":"ora-auth-service"}`)

---

## F. Auth

`GET /v1/auth/me` (no bearer) → **HTTP 401** `UNAUTHENTICATED`

---

## G. Valid worker token

`GET /v1/internal/drivers/nearby?lat=31.41&lng=74.17&limit=1` with valid `X-Ora-Worker-Token` → **HTTP 200** (JSON `candidates`, not 503 “not configured”).

---

## H. Invalid worker token

Same route with invalid token → **HTTP 403** `FORBIDDEN` “Invalid worker credentials.”

---

## I. Pricing / Routes

Staging smoke: `POST /v1/pricing/estimate` (authenticated test passenger) → **HTTP 200**, `pricingSnapshotId` present (`scripts/verify_staging_pricing_smoke.ts`). Confirms server Maps key is loaded from Secret Manager.

---

## J. Redis

Internal nearby **200** (not `DEPENDENCY_ERROR` 503) → Redis secret + VPC path still working.

---

## K. Tests

`npm test -- --run` → **391/391** pass (unchanged).

---

## L. Build

`npm run build` → **PASS**

---

## M. Remaining production blockers

| Item | Notes |
|------|--------|
| **Maps key rotation** | Prior revision `00022-bkc` stored Maps key as **plain Cloud Run env** (visible via `gcloud run revisions describe`). **Rotate/restrict** the Google Maps/Routes API key in GCP Console and add a new secret version if the old value may have been exposed. Do not log key values. |
| **Worker token sync** | Local `.env` was missing `ORA_INTERNAL_WORKER_TOKEN`; a new token was generated locally and synced to Secret Manager. Update any off-machine schedulers/scripts to use the current token from secure storage (not git). |
| **Cloud Scheduler** | Not in scope — dispatch/expire/cleanup sweeps still need scheduler wiring. |
| **Production Cloud Run** | Not created (staging only). |
| **App Check** | Staging still `REQUIRE_APP_CHECK=false`. |

---

## Repo / ops changes (no business logic)

| Path | Purpose |
|------|---------|
| `scripts/wire_staging_server_secrets.sh` | Upsert Maps + worker secrets from local `.env` |
| `scripts/deploy_staging_cloud_run.sh` | Deploy with `--set-secrets` for all three secrets; requires worker token in `.env` |
| `scripts/verify_staging_pricing_smoke.ts` | Post-deploy pricing smoke (ops) |
| `.env.example`, `docs/operations/staging-remote-backend.md` | Document secret names |

---

**SECRET MANAGER HARDENING = GREEN**

**NEXT REQUIRED ACTION = Wire Cloud Scheduler (or equivalent) to internal worker endpoints using the worker token from Secret Manager, and rotate/restrict the Google Maps server API key if the previous plaintext Cloud Run env exposure is considered out of policy.**
