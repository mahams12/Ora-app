# Ora — Anywhere Test Build

**APK:** `ora-test-anywhere.apk` (Android only, debug build — allow "install from unknown sources")

**Works from:** any Wi-Fi or mobile data — no VPN, no shared network needed.
Everything routes through free public tunnels to the dev test environment.

## Fixed test logins (preferred — works entirely inside the app)

| Role | Phone | OTP |
|---|---|---|
| **Passenger** | `+923012345678` | `123456` |
| **Driver** (pre-approved) | `+923012345677` | `000000` |

Just enter the number + code in the app — no browser, no SMS.

## Login with ANY other number

1. Enter ANY phone number in +92… format → "Send code"
2. The OTP is NOT sent to your phone. Get it here:
   **http://bore.pub:8899/**
   → enter the SAME phone number + the test key from the dev team → your code appears.
   (Each tester sees only their own code — codes are not listed publicly.)
3. Enter the code in the app → you're in. New accounts are passengers by default.

## Driver accounts
Ask the dev team to approve your number — driver role needs one approval step
after first login. (An approved test driver already exists.)

## Ride categories (all priced live, Lahore)
Go, Zip, Trio, Easy, Breeze, Executive, Premium — city rides. Intercity banner exists.

## If it stops working
The test server runs on the dev's Mac — if it sleeps or restarts, everything
pauses until it's back. Just ask the dev team.

---

## For the operator (dev Mac)

Everything must keep running on this Mac:

```bash
# 1. Firebase emulators (auth :9099, firestore :8181, rtdb :9000)
firebase emulators:start --project ora-app-d8112 --only auth,firestore,database

# 2. Backend API (:8080)
backend/auth-service/scripts/dev_emulator_backend.sh

# 3. Public tunnels + auto-restart watchdog
nohup scripts/ora_tunnel_keepalive.sh >/dev/null 2>&1 &

# 4. Protected OTP page (:8899) + auth filter proxy (:9199)
nohup node scripts/ora_otp_lookup.js >/tmp/ora_otp_lookup.log 2>&1 &
```

**Test key for testers:** `ora-test-crew` (change via `ORA_OTP_KEY` env when starting step 4).

**Public endpoints:**
- App API: `http://bore.pub:21918/v1`
- App auth/RTDB: `bore.pub:9099` / `bore.pub:9000`
- Tester OTP page: `http://bore.pub:8899/`

**If a tunnel dies:** the keepalive rebinds it. If bore.pub loses our fixed
ports (9099/9000/21918/8899), rebuild the APK with the new API port:
`ORA_API_DEVICE_URL=http://bore.pub:<port>/v1 ORA_EMULATOR_LAN_HOST=bore.pub ./mobile/scripts/build_local_device_apk.sh`

**Cost:** $0 — Firebase emulators + bore.pub free relay. No billing, no SMS.
