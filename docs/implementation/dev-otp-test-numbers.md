# Dev OTP (free) — Firebase test phone numbers

Ora is **Pakistan-only**. Real SMS comes later (near deploy / Blaze).

## Free now?

| Mode | Cost | Needs Blaze? |
|---|---|---|
| Firebase **Phone numbers for testing** + fixed code `123456` | **Free** | No |
| Real SMS to +92 | Paid (per SMS) | **Yes** (Spark cannot send SMS) |

## One-time Console setup (required for test OTP)

1. Open [Firebase Console](https://console.firebase.google.com/project/ora-app-d8112/authentication/providers) → project **ora-app-d8112**
2. **Authentication** → **Sign-in method** → **Phone** → enabled
3. Scroll to **Phone numbers for testing** → **Add phone number**
   - Phone: `+923001234567` (exactly 13 chars: `+92` + 10 digits starting with `3`)
   - Code: `123456`
4. **Authentication** → **Settings** → **SMS region policy** → **Allow** → enable **Pakistan (PK)**  
   (Needed for real SMS later; test numbers usually work without sending SMS.)

## App phone rules

- Valid: `+923001234567` or `03001234567`
- Exactly **10** national digits after `+92`, must start with **3**
- Invalid lengths are rejected in the UI before Firebase is called

## Try it

```bash
# terminal 1
cd backend/auth-service && npm start

# terminal 2
cd mobile
flutter run -d emulator-5554 --dart-define=ORA_API_BASE_URL=http://10.0.2.2:8080/v1
```

In the app: enter `+923001234567` → Send code → enter `123456`.
