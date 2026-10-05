#!/usr/bin/env python3
"""Create a DRIVER_ASSIGNED ride on staging via public APIs (no Places UI)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BACKEND = REPO / "backend/auth-service"
MOBILE = REPO / "mobile"
SA = BACKEND / "secrets/service-account.json"
OUT = Path(__file__).resolve().parent / "l1_assigned_ride.json"

DRIVER_PHONE = "+923012345677"
PASSENGER_PHONE = "+923012345678"
PICKUP = {"lat": 31.4127578, "lng": 74.1725224, "address": "Liberty Market Lahore"}
DEST = {"lat": 31.51058, "lng": 74.34445, "address": "Gulberg Lahore"}


def base_url() -> str:
    env = os.environ.get("STAGING_API_BASE_URL") or os.environ.get("ORA_API_BASE_URL")
    if env:
        return env.rstrip("/")
    return (MOBILE / ".staging_api_url").read_text().strip().rstrip("/")


def web_api_key() -> str:
    gs = json.loads((MOBILE / "android/app/google-services.json").read_text())
    return gs["client"][0]["api_key"][0]["current_key"]


def run_node(expr: str) -> str:
    env = {
        **os.environ,
        "GOOGLE_APPLICATION_CREDENTIALS": str(SA),
    }
    return subprocess.check_output(
        [
            str(BACKEND / "node_modules/.bin/tsx"),
            "-e",
            expr,
        ],
        cwd=str(BACKEND),
        env=env,
        text=True,
    ).strip()


def uid_and_token(phone: str) -> tuple[str, str]:
    script = f"""
import {{ initializeApp, cert, getApps }} from 'firebase-admin/app';
import {{ getAuth }} from 'firebase-admin/auth';
import {{ readFileSync }} from 'node:fs';
const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS!, 'utf8'));
if (!getApps().length) initializeApp({{ credential: cert(sa) }});
const auth = getAuth();
const phone = {json.dumps(phone)};
const user = await auth.getUserByPhoneNumber(phone);
const custom = await auth.createCustomToken(user.uid);
const apiKey = {json.dumps(web_api_key())};
const res = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${{apiKey}}`,
  {{
    method: 'POST',
    headers: {{ 'Content-Type': 'application/json' }},
    body: JSON.stringify({{ token: custom, returnSecureToken: true }}),
  }},
);
if (!res.ok) throw new Error('token_exchange ' + res.status);
const body = await res.json();
console.log(JSON.stringify({{ uid: user.uid, idToken: body.idToken }}));
"""
    path = BACKEND / ".tmp_l1_token.mts"
    path.write_text(script)
    try:
        # Prefer node --import tsx: the tsx CLI IPC listen() fails under some sandboxes (EPERM).
        out = subprocess.check_output(
            ["node", "--import", "tsx", str(path)],
            cwd=str(BACKEND),
            env={**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": str(SA)},
            text=True,
        ).strip()
    finally:
        path.unlink(missing_ok=True)
    data = json.loads(out)
    return data["uid"], data["idToken"]


def api(base: str, method: str, route: str, bearer: str, body=None, idempotency=None):
    import urllib.request

    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {bearer}",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    if idempotency:
        headers["Idempotency-Key"] = idempotency
    req = urllib.request.Request(
        f"{base}{route}", data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except Exception as e:
        if hasattr(e, "read"):
            raw = e.read().decode()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return getattr(e, "code", 0), {"raw": raw[:500]}
        raise


def main() -> None:
    if not SA.exists():
        print(json.dumps({"ok": False, "error": "service_account_missing"}))
        sys.exit(2)
    base = base_url()
    steps = {"base": base}
    driver_uid, driver_token = uid_and_token(DRIVER_PHONE)
    passenger_uid, passenger_token = uid_and_token(PASSENGER_PHONE)
    steps["driverUid"] = driver_uid
    steps["passengerUid"] = passenger_uid

    st, body = api(base, "POST", "/drivers/go-online", driver_token, {})
    steps["goOnline"] = {"status": st}

    st, estimate = api(
        base,
        "POST",
        "/pricing/estimate",
        passenger_token,
        {
            "pickup": PICKUP,
            "destination": DEST,
            "category": "easy",
            "city": "lahore",
            "serviceType": "ride",
        },
    )
    steps["pricing"] = {"status": st}
    if st != 200:
        print(json.dumps({"ok": False, "steps": steps, "pricing": estimate}, indent=2))
        sys.exit(1)
    data = estimate["data"]
    fare = data["recommendedFareMinor"]
    snap = data["pricingSnapshotId"]

    st, ride = api(
        base,
        "POST",
        "/rides",
        passenger_token,
        {
            "pickup": PICKUP,
            "destination": DEST,
            "city": "lahore",
            "category": "easy",
            "serviceType": "ride",
            "passengerOfferMinor": fare,
            "pricingSnapshotId": snap,
            "paymentMethod": "CASH",
            "passengerCount": 1,
        },
        idempotency=f"l1-{uuid.uuid4()}",
    )
    steps["createRide"] = {"status": st}
    if st not in (200, 201):
        print(json.dumps({"ok": False, "steps": steps, "ride": ride}, indent=2))
        sys.exit(1)
    ride_id = ride["data"]["rideId"]
    steps["rideId"] = ride_id
    version = ride["data"].get("version", 1)

    st, offer = api(
        base,
        "POST",
        f"/rides/{ride_id}/offers",
        driver_token,
        {
            "amountMinor": fare,
            "type": "PASSENGER_PRICE_ACCEPTED",
            "expectedRequestVersion": ride["data"].get("requestVersion", 1),
        },
        idempotency=f"l1-offer-{uuid.uuid4()}",
    )
    steps["createOffer"] = {"status": st, "body": offer.get("data") or offer.get("error")}
    if st not in (200, 201):
        print(json.dumps({"ok": False, "steps": steps}, indent=2))
        sys.exit(1)
    offer_id = offer["data"]["offerId"]
    expected_version = offer["data"].get("rideVersion") or (version + 1)

    st, selected = api(
        base,
        "POST",
        f"/rides/{ride_id}/offers/{offer_id}/select",
        passenger_token,
        {"expectedVersion": expected_version},
        idempotency=f"l1-select-{uuid.uuid4()}",
    )
    steps["selectOffer"] = {"status": st, "body": selected.get("data") or selected.get("error")}
    state = None
    if isinstance(selected.get("data"), dict):
        state = selected["data"].get("state")
    ok = st in (200, 201) and state == "DRIVER_ASSIGNED"
    result = {"ok": ok, "rideId": ride_id, "state": state, "steps": steps}
    OUT.write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
