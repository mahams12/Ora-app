# ORA GCP Resource Deletion Proof

**Date:** 2026-11-18 · **Method:** live Cloud Asset Inventory (`gcloud asset search-all-resources`) + service-specific API attempts + codebase grep
**Caller:** `vezeon.live@gmail.com` · **IAM on old project:** `roles/browser` + `roles/cloudasset.viewer` (read-only)
**Raw captures:** `/tmp/ora_old_assets.json` (14,172 assets), `/tmp/ora_new_assets.json` (74 assets)

> Classifications: `PRESENT` (directly observed in live inventory), `VERIFIED ABSENT` (asset type/query authoritatively returned nothing), `UNVERIFIED` (API blocked or permission denied — NOT treated as absent).

---

## 1. Old project `ora-app-d8112` (project # `498169438285`)

### Billing

| Item | Evidence | Status |
|---|---|---|
| Billing linkage | `cloudbilling.googleapis.com/ProjectBillingInfo` state **CLOSED** in CAI | **VERIFIED DISABLED** — stays disabled |

### Billable infrastructure — `PRESENT`

| # | Type | Resource | Location | State | Notes |
|---|---|---|---|---|---|
| 1 | `redis.googleapis.com/Instance` | `ora-production-n3-redis` | `us-central1` | **SUSPENDED** | created 2026-10-21T08:00:51Z. Tier/memory **UNVERIFIED** — `redis.instances.describe` blocked (billing-gated API). Suspended ≠ deleted; config + capacity reservation still exist. |
| 2 | `vpcaccess.googleapis.com/Connector` | `ora-staging-vpc` | `us-central1` | **READY** | The only connector. `vpcaccess.connectors.get` denied — details UNVERIFIED. |
| 3 | `secretmanager.googleapis.com/Secret` | `ora-production-redis-url` | global | ENABLED | 2 versions. Redis credential — obsolete. |
| 4 | `secretmanager.googleapis.com/Secret` | `ora-staging-redis-url` | global | ENABLED | 9 versions. Redis credential — obsolete. |
| 5 | `servicenetworking.googleapis.com/Connection` | private-services peering on `default` network | global | — | Memorystore private-access plumbing; only consumer was Redis. |
| 6 | `compute.googleapis.com/Address` | `google-managed-services-default` | global | RESERVED | Reserved range backing the peering above. |
| 7 | `compute.googleapis.com/Route` | `peering-route-f470eebd1a92ae6d` | global | — | Peering route for the connection. |

### Other old-environment resources — `PRESENT`, **not in deletion list**

| Type | Resources | Note |
|---|---|---|
| `run.googleapis.com/Service` | `ora-auth-service`, `ora-auth-service-staging` (`us-central1`) | Old prod/staging services. Billing closed → cannot serve. Env/connector wiring **UNVERIFIED** (`run.services.get` denied). Kept per "do not delete production services". |
| `run.googleapis.com/Job` | 15: `ora-{production,staging}-worker-{dispatch-fcm,dispatch,expire,no-show,offer-expire}-sweep`, `…-expires-at-cleanup`, `ora-staging-worker-ride-state-fcm-sweep`, `ora-n3-staging-{seed,benchmark}` | Inert while billing closed. |
| `run.googleapis.com/Execution` | 13,852 historical records | Log-like history; not separately billed. |
| `run.googleapis.com/Revision` | 30 revisions of the two services | Historical. |
| `cloudscheduler.googleapis.com/Job` | 14 jobs, **all PAUSED** (`ora-{production,staging}-sched-*`) | Paused = no invocations; job objects remain. |
| `artifactregistry.googleapis.com/Repository` + 21 `DockerImage` | `cloud-run-source-deploy` / `ora-auth-service-staging` images | Old build artifacts. |
| `storage.googleapis.com/Bucket` | `run-sources-ora-app-d8112-us-central1` | Cloud Run source archive bucket. |
| `firestore.googleapis.com/Database` | `(default)` in `asia-south1` | **DO NOT DELETE — application data.** |
| `identitytoolkit`/`firebase`/`firebaserules` | config, 2 Firebase apps, ruleset | **DO NOT DELETE — auth/users.** |
| `iam` | 4 service accounts, 3 SA keys | Inert; keys on `firebase-adminsdk-fbsvc`-era SA. |
| `secretmanager` (non-Redis) | `ora-{production,staging}-{google-maps-server-key,internal-worker-token}` | Non-Redis secrets; keep. |
| `compute` | `default` network, 4 default firewalls, 42 auto subnets, 45 routes | Default VPC fabric; no GCE instances (`compute.googleapis.com/Instance` absent), no disks. |
| `apikeys` | 6 API keys | Metadata only. |
| `logging` | `_Default`, `_Required` buckets/sinks | Platform defaults. |
| Enabled APIs | 72 incl. `redis`, `vpcaccess`, `servicenetworking`, `run`, `secretmanager`, `cloudscheduler` | API enablement is free; can be disabled after cleanup if desired. |

### Verified absent on old project

`redis.googleapis.com/Cluster`, `cloudtasks.googleapis.com/Queue`, `dns` zones, `compute.googleapis.com/Instance` (VMs), `compute.googleapis.com/Disk`, `spanner`, `sql`, `gke` clusters — **VERIFIED ABSENT** (no assets of these types in 14,172-item inventory).

### Old-project items that remain `UNVERIFIED`

- Redis instance tier/memory/GB (describe is billing-gated) → savings estimate only.
- Whether Cloud Run revisions still reference `ora-staging-vpc` connector or `*-redis-url` secrets (`run.services.get`/`revisions.get` denied). If connector deletion errors with "in use", we stop and report rather than deleting services.
- Billing/cost export data (no billing account linked) → **no billing figures available; savings below are estimates only.**

---

## 2. New project `oraapp-a9be5` (project # `853665950697`, billing **ACTIVE**)

| Category | Result | Evidence |
|---|---|---|
| Redis instances/clusters | **VERIFIED ABSENT** | 0 assets; `redis.googleapis.com` API not even enabled |
| VPC connectors / peering | **VERIFIED ABSENT** | 0 `vpcaccess`, 0 `servicenetworking`, 0 compute assets; `vpcaccess` API not enabled |
| Cloud Run (svc/job/exec/rev) | **VERIFIED ABSENT** | 0 assets — prior temporary E2E teardown confirmed complete |
| Cloud Scheduler / Cloud Tasks | **VERIFIED ABSENT** | 0 job/queue assets |
| Artifact Registry images | **VERIFIED ABSENT** | repo `cloud-run-source-deploy` exists, 0 `DockerImage` assets |
| Secrets | 1 present: `ora-test-worker-token` (3 enabled versions) | Leftover from prior temporary test — ~$0.18/mo, flagged for cleanup |
| Service accounts | 4: compute-default, `firebase-adminsdk-fbsvc`, **`ora-tasks-invoker`**, **`ora-test-deadman`** | Last two are prior-test leftovers (free); 1 SA key exists |
| Firebase core | Firestore `(default)`, FirebaseProject, Android + iOS apps, ruleset, IdentityToolkit config | Expected — application platform |
| Storage | `run-sources-oraapp-a9be5-asia-south1` | Near-empty source bucket |
| Enabled APIs | 52 — includes `cloudtasks`, `cloudscheduler`, `run`, `secretmanager`, `pubsub`, `cloudasset` | Needed for future E2E; **no `redis`/`vpcaccess`** |
| API keys | 3 | Metadata |

---

## 3. Codebase verification — no Redis runtime dependency

Verified 2026-11-18 on `backend/auth-service`:

| Check | Result |
|---|---|
| `redis`/`ioredis`/`@redis/*` in `package.json` | **NONE** |
| Redis imports/connections in `src/` | **NONE** — geo layer lives in `src/geo/` (`firestore_geo_client.ts`, `geo_projection.ts`, `memory_geo_store.ts`); the only `redis` strings are accurate comments ("Redis-shaped API kept for parity", "No Redis server exists") |
| `REDIS_URL` consumed at runtime | **NONE** — deploy scripts actively strip it: `deploy_production_cloud_run.sh`/`deploy_staging_cloud_run.sh` run `--clear-vpc-connector --remove-secrets=REDIS_URL`; `test_env_up.sh` uses `--clear-vpc-connector` |
| Redis/VPC secrets in new project | **NONE** |
| Re-creation path | **NONE** — no deploy script provisions Redis or VPC connectors; geo backend is `GEO_BACKEND=firestore` |

---

## 4. Deletion list (pending user confirmation)

All on **`ora-app-d8112`**, all obsolete Redis infrastructure:

| # | Resource | Type | Region | Irreversible? |
|---|---|---|---|---|
| D1 | `ora-production-n3-redis` | Memorystore Redis instance | `us-central1` | Yes — instance + its data gone permanently. Data is obsolete (system is Firestore-native). |
| D2 | `ora-staging-vpc` | Serverless VPC Access connector | `us-central1` | Yes. Only consumer was Redis access. |
| D3 | `ora-production-redis-url` (+2 versions) | Secret Manager secret | global | Yes — credentials for D1. |
| D4 | `ora-staging-redis-url` (+9 versions) | Secret Manager secret | global | Yes — credentials for a deleted staging Redis. |
| D5 (optional) | servicenetworking peering + `google-managed-services-default` range + `peering-route-f470eebd1a92ae6d` on `default` network | Redis private-access plumbing | global | Peering removal is reversible (can re-peer later); zero cost while idle — listed optional because compute mutation may be billing-gated. |

**Minimum temporary IAM needed for D1–D4:** `roles/redis.admin`, `roles/vpcaccess.admin`, `roles/secretmanager.admin` on `ora-app-d8112`. D5 additionally needs `roles/compute.networkAdmin` — only grant if D5 approved.

**Not deleting:** Firestore `(default)`, IdentityToolkit/Auth, Firebase apps/rulesets, RTDB, Cloud Run services/jobs, Scheduler jobs, AR repo, buckets, non-Redis secrets, service accounts, API keys, enabled APIs.

**Risks:** (a) Redis/VPC deletes on a billing-closed project may be rejected by the API — if so, reported as blocked, not bypassed; (b) D2 may report "in use" by a Cloud Run revision — if so, we stop and report; (c) savings are **estimates** — suspended Redis ≈ $0 compute but reserves capacity; typical basic-tier ~$35–50/mo when running — no billing export exists to confirm.

**Status:** D1–D4 confirmed by user 2026-11-18 — awaiting temporary role grants.

### D5 dependency analysis (requested proof before confirmation)

Scanned all 14,172 assets on `ora-app-d8112` for every resource type capable of consuming private-services access on the `default` VPC:

| PSA-capable consumer | Assets found | Verdict |
|---|---|---|
| `redis.googleapis.com/Instance` | 1 — `ora-production-n3-redis` (SUSPENDED, D1) | Only live consumer |
| `file.googleapis.com` (Filestore) | API enabled, **0 instances** | No consumer |
| `sqladmin` / Cloud SQL | API **not enabled**, 0 instances | No consumer |
| AlloyDB, Memcache, TPU, Notebooks, Data Fusion, NetApp, VMware, Managed Kafka | 0 assets, APIs not enabled | No consumer |

Dependency chain, all on `default` network: `servicenetworking.googleapis.com/Connection` ← reserved range `google-managed-services-default` (RESERVED) ← `peering-route-f470eebd1a92ae6d`. After D1 deletion this chain has **zero consumers** — it is exclusively Redis plumbing. It costs $0 while idle; removal is reversible (re-peering is free). Compute mutations may be billing-gated on a closed-billing project — will attempt and report the exact result; the `default` network itself and its standard routes/firewalls are NOT in scope.

### `ora-test-worker-token` on `oraapp-a9be5` (investigated)

Created by `scripts/test_env_up.sh:58` for temporary E2E; `test_env_down.sh:52` and `test_env_deadman.sh:56` delete it — the 3 enabled versions are a partial-teardown leftover. Next test recreates it fresh, so removal is safe (idempotent). Recommendation: delete (saves ~$0.18/mo, removes a stale credential). Same for leftover SAs `ora-test-deadman` and `ora-tasks-invoker` (free, but stale).

---

## 5. Execution log — 2026-11-18

### New project `oraapp-a9be5` cleanup — **COMPLETE, VERIFIED**

| Item | Result | Evidence |
|---|---|---|
| `ora-test-worker-token` secret | **Already absent** — `gcloud secrets list` → `Listed 0 items`. The 3 CAI SecretVersion records were stale index entries; authoritative API confirms 0 secrets. | 2026-11-18T11:43Z |
| `ora-test-deadman` SA | **DELETED** — held 4 project bindings (scheduler/tasks/run/secretmanager admin); all removed cleanly first, then SA deleted | `deleted service account [ora-test-deadman@...]` |
| `ora-tasks-invoker` SA | **DELETED** — verified zero Tasks queues (`us-central1`, `asia-south1`) and zero Scheduler jobs before deletion | `deleted service account [ora-tasks-invoker@...]` |
| Post-delete verification | `iam service-accounts list` → only `firebase-adminsdk-fbsvc` + `853665950697-compute@developer` remain; `NO STALE BINDINGS` | 2026-11-18T11:43:42Z |

Note: the SA key in CAI belongs to `firebase-adminsdk-fbsvc` (uniqueId 104370260981069033633) — Firebase-managed, intentionally kept.

### Old project `ora-app-d8112` — D1–D4 attempted 2026-11-18, **BLOCKED BY `BILLING_DISABLED`**

IAM verified pre-flight 2026-11-18T11:53:08Z: `roles/redis.admin` + `roles/vpcaccess.admin` + `roles/secretmanager.admin` active on `vezeon.live@gmail.com` (plus browser/cloudasset.viewer).

| Item | Command result | Outcome |
|---|---|---|
| D1 `ora-production-n3-redis` | `gcloud redis instances delete` → `PERMISSION_DENIED: BILLING_DISABLED` (service `redis.googleapis.com`) | **BLOCKED — still exists** (SUSPENDED) |
| D2 `ora-staging-vpc` | Request accepted → operation `aba4178b-3d0c-41df-9a4a-e90c7ae787d8` ran 11:53:28–11:53:53Z → `done:true, error code 7: "Operation failed: This API method requires billing to be enabled."` | **BLOCKED — still exists**, state changed READY → **ERROR** by the failed op |
| D3 `ora-production-redis-url` | `gcloud secrets delete` → `BILLING_DISABLED` (`secretmanager.googleapis.com`) | **BLOCKED — still exists** |
| D4 `ora-staging-redis-url` | `gcloud secrets delete` → `BILLING_DISABLED` (`secretmanager.googleapis.com`) | **BLOCKED — still exists** |

**Conclusion:** GCP hard-blocks mutations on billing-closed projects for these services — even deletions. Per user instruction, stopped and reported; no billing was enabled and no workaround attempted. The resources remain but **cannot accrue charges while billing is closed**; risk exists only if billing is re-enabled later (Redis would resume ~$35–50/mo estimate).

D5 remains pending — blocked transitively (requires D1 verified-deleted first) and its compute/servicenetworking mutations would face the same gate.

**Recommended IAM hygiene:** the 3 temporary deletion roles are unusable while billing is closed — safe to revoke now and re-grant if deletion becomes possible.

### Official no-billing-reactivation deletion path — researched 2026-11-18

**None exists.** Per Google Cloud documentation and observed API behavior:

- Disabling billing stops services but does **not** delete resources; GCP docs note only that "some resources might be deleted" opportunistically over time — not prompt, not reliable, not targetable.
- All targeted deletion APIs (`redis.instances.delete`, `secrets.delete`, `vpcaccess connectors delete`) enforce billing at request or operation level — verified live above.
- The only official mechanism that removes resources without billing is **project shutdown** (`gcloud projects delete` → `DELETE_REQUESTED` → permanent deletion of **everything** after 30 days, including Firestore/Auth/Storage). This is all-or-nothing and explicitly out of scope — Firebase data must be preserved.
- Cloud Billing support cannot perform in-project resource deletion; the documented remedy for gated deletions is re-enabling billing.

**Therefore D1–D5 are BLOCKED BY `BILLING_DISABLED` — not deleted, not completed.** Residual risk is latent only: zero cost while billing stays closed; costs resume only if billing is ever re-enabled (Redis est. ~$35–50/mo, connector ~$15/mo est. — estimates, no billing export exists).

### Old-project production-traffic check — 2026-11-18T11:5xZ (read-only)

| Probe | Result | Interpretation |
|---|---|---|
| `https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/` | HTTP **500** | Service object exists but cannot function under closed billing |
| `https://ora-auth-service-staging-...a.run.app/` | HTTP **500** | Same |
| `api.ora.app` DNS | resolves to `216.150.16.193`, `216.150.1.65`, `216.150.16.1`, `216.150.16.129` — **not** Google/Cloud Run anycast ranges | Production DNS does **not** route to old Cloud Run services |

No modification made. Old environment is inert; nothing in the new project depends on it (see §6).

## 6. Cloud E2E readiness — old resources confirmed not required

| Check | Evidence | Verdict |
|---|---|---|
| Backend geo runtime | `GEO_BACKEND=firestore`; `src/geo/` (Firestore + RTDB implementations); zero redis packages/imports/`REDIS_URL` | Old Redis never referenced by new-project code path |
| Deploy scripts | `deploy_*_cloud_run.sh` use `--clear-vpc-connector --remove-secrets=REDIS_URL`, target `oraapp-a9be5` | Cannot recreate or depend on old infra |
| New project APIs | `redis`, `vpcaccess`, `servicenetworking` **not enabled** on `oraapp-a9be5` | No dependency possible |
| New project secrets | `secrets list` → 0; `test_env_up.sh` creates `ora-test-worker-token` + maps key fresh per test | Self-contained |
| New project networking | 0 compute/vpcaccess/servicenetworking assets | Clean |

**D1–D5 status: BLOCKED BY `BILLING_DISABLED`.** Old suspended Redis/connector remain dormant at $0; deletion requires billing re-enablement (user decision) or project shutdown (out of scope).
