# Phase 2B — Secret Hygiene Report (pre-git)

**Date:** 2026-08-20  
**Workspace:** `/Users/jazimsaeed/Desktop/Ora App`

## Findings

| # | Check | Result |
|---|---|---|
| 1 | Git initialized? | **YES** (Phase 2B) |
| 2 | `service-account.json` tracked? | **NO** — ignored; on disk at `backend/auth-service/secrets/service-account.json` |
| 3 | Firebase Admin credential tracked? | **NO** |
| 4 | `.env` tracked? | **NO**; local `backend/auth-service/.env` present |
| 5 | Private keys/certs tracked? | **NO** — SA JSON only under ignored `secrets/` |
| 6 | Secrets in source? | **Not found** in app/source (Admin path via env only) |
| 7 | Secrets in build artifacts? | Flutter APK must never contain Admin SA (client Firebase config is public-by-design) |
| 8 | Secrets in logs? | Auth paths redact tokens/OTP (security tests) |
| 9 | Root `.gitignore` | Protects `secrets/`, `*service-account*`, `.env`, `node_modules`, `build`, google-services |
| 10 | Backend `.gitignore` | Protects `.env`, `service-account*.json`, `secrets/` |
| 11 | Mobile `.gitignore` | Protects google-services, `.env`, SA patterns |

## Production secret strategy

- **Local/dev:** `GOOGLE_APPLICATION_CREDENTIALS` → ignored JSON under `backend/auth-service/secrets/`
- **Cloud Run / production:** Workload Identity or Secret Manager — **never** bake JSON into images or Flutter

## Safe to initialize git?

**YES**, if and only if:
1. `.gitignore` is in place before `git add`
2. Initial commit excludes `secrets/`, `.env`, SA JSON
3. Verified with `git status` / `git ls-files` after first commit
