# Production remote backend (Cloud Run)

Same Firebase/GCP project as staging: **`ora-app-d8112`**. Production uses **separate** Cloud Run, secrets, Redis, jobs, and scheduler names.

## Deploy

```bash
cd backend/auth-service
# .env must include (never commit):
#   PRODUCTION_GOOGLE_MAPS_SERVER_KEY
#   PRODUCTION_ORA_INTERNAL_WORKER_TOKEN
chmod +x scripts/deploy_production_cloud_run.sh
./scripts/deploy_production_cloud_run.sh
```

Writes `mobile/.production_api_url`.

Production Cloud Run env: `ORA_ENV=production`, `REQUIRE_APP_CHECK=true` (required by startup guards).

## Workers + Scheduler

```bash
./scripts/wire_production_cloud_scheduler.sh
```

Architecture matches staging slice 2: Scheduler OAuth → Run Job → Secret Manager worker token → HTTPS internal POST.

Scheduler invoker SA: `ora-prod-sched-invoker@ora-app-d8112.iam.gserviceaccount.com` (`roles/run.jobsExecutor` on project).

## Smoke

```bash
# Register debug secret once (UUID in .env only): bash scripts/register_production_app_check_debug.sh
# Smoke exchanges debug secret → App Check JWT → pricing/estimate 200
npx tsx scripts/verify_production_smoke.ts
```

## Isolation notes

| Resource | Staging | Production |
|----------|---------|------------|
| Cloud Run | `ora-auth-service-staging` | `ora-auth-service` |
| Redis | `ora-staging-n3-redis` / `ora-staging-redis-url` | `ora-production-n3-redis` / `ora-production-redis-url` |
| Firestore | `(default)` database — **shared project** | same |
| Firebase Auth users | shared | same |

Ride data is not isolated by environment until a separate Firebase project or database is introduced.
