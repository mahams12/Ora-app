# Ora Auth Service (Phase 2A)

Minimal Cloud Run–ready API for Firebase Auth session → Ora user bootstrap.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| `GET` | `/healthz` | none | Liveness |
| `POST` | `/v1/auth/register` | Bearer Firebase ID token + `Idempotency-Key: register_{uid}` | Idempotent user create |
| `GET` | `/v1/auth/me` | Bearer Firebase ID token | Server-derived profile |

Identity is **always** taken from `admin.auth().verifyIdToken()`. Client-supplied `uid` / `role` / `?userId=` are ignored.

## Local run

1. Firebase Console → Project settings → Service accounts → Generate new private key.
2. Store it **outside** `mobile/` (e.g. `backend/auth-service/secrets/service-account.json`).
3. Copy `.env.example` → `.env` and set `GOOGLE_APPLICATION_CREDENTIALS`.
4. Enable Firestore in the Firebase project (Native mode).
5. Install and start:

```bash
cd backend/auth-service
npm install
npm test
npm run dev
```

Point the Flutter app at it:

```bash
cd mobile
flutter run --dart-define=ORA_API_BASE_URL=http://10.0.2.2:8080/v1
```

(`10.0.2.2` is the Android emulator host loopback. Use your machine LAN IP for a physical device.)

## Security notes

- Never put the service-account JSON in the Flutter project.
- `REQUIRE_APP_CHECK=true` for production (ADR-014). Phase 2A defaults to `false` until App Check is wired on the client.
- Ban / disable is enforced on `/register` and `/me` after the Firestore document is loaded.
