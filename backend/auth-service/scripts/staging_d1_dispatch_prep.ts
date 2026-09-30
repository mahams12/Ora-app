/**
 * Staging D1 happy-path prep via public APIs (no Firestore hacks).
 * Driver go-online + location, passenger pricing + ride, dispatch-tick + FCM sweep.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=secrets/service-account.json \
 *   ORA_INTERNAL_WORKER_TOKEN=... \
 *   npx tsx scripts/staging_d1_dispatch_prep.ts
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');

const DRIVER_PHONE = '+923012345677';
const PASSENGER_PHONE = '+923012345678';

const PICKUP = {
  lat: 31.4127578,
  lng: 74.1725224,
  address: 'Liberty Market Lahore',
};
const DESTINATION = {
  lat: 31.51058,
  lng: 74.34445,
  address: 'Gulberg Lahore',
};

function readBaseUrl(): string {
  const fromEnv = process.env.STAGING_API_BASE_URL?.trim();
  if (fromEnv) return fromEnv.replace(/\/$/, '');
  const file = path.join(repoRoot, 'mobile/.staging_api_url');
  return readFileSync(file, 'utf8').trim().replace(/\/$/, '');
}

function readFirebaseWebApiKey(): string {
  const fromEnv = process.env.FIREBASE_WEB_API_KEY?.trim();
  if (fromEnv) return fromEnv;
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  const data = JSON.parse(readFileSync(gs, 'utf8')) as {
    client: Array<{ api_key: Array<{ current_key: string }> }>;
  };
  return data.client[0]!.api_key[0]!.current_key;
}

async function idTokenForUid(uid: string): Promise<string> {
  const auth = getAuth();
  const custom = await auth.createCustomToken(uid);
  const apiKey = readFirebaseWebApiKey();
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!res.ok) {
    throw new Error(`custom_token_exchange_failed status=${res.status}`);
  }
  const body = (await res.json()) as { idToken: string };
  return body.idToken;
}

async function uidForPhone(phone: string): Promise<string> {
  const auth = getAuth();
  const user = await auth.getUserByPhoneNumber(phone);
  return user.uid;
}

type Json = Record<string, unknown>;

async function apiJson(
  base: string,
  method: string,
  route: string,
  opts: {
    bearer?: string;
    worker?: string;
    body?: unknown;
    idempotencyKey?: string;
  } = {},
): Promise<{ status: number; json: Json }> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  };
  if (opts.bearer) headers.Authorization = `Bearer ${opts.bearer}`;
  if (opts.worker) headers['X-Ora-Worker-Token'] = opts.worker;
  if (opts.body != null) headers['Content-Type'] = 'application/json';
  if (opts.idempotencyKey) headers['Idempotency-Key'] = opts.idempotencyKey;

  const res = await fetch(`${base}${route}`, {
    method,
    headers,
    body: opts.body != null ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  let json: Json = {};
  try {
    json = text ? (JSON.parse(text) as Json) : {};
  } catch {
    json = { raw: text.slice(0, 500) };
  }
  return { status: res.status, json };
}

function locBody(seq: number) {
  return {
    locationSeq: seq,
    locationStreamId: `d1-proof-${Date.now()}`,
    lat: PICKUP.lat,
    lng: PICKUP.lng,
    accuracy: 8,
    heading: 90,
    speed: 0,
    timestamp: new Date().toISOString(),
    provider: 'gps',
  };
}

async function main(): Promise<void> {
  const worker = process.env.ORA_INTERNAL_WORKER_TOKEN?.trim();
  if (!worker) {
    console.error(
      JSON.stringify({
        ok: false,
        error: 'ORA_INTERNAL_WORKER_TOKEN required',
      }),
    );
    process.exit(2);
  }

  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ??
    path.join(here, '../secrets/service-account.json');
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }

  const base = readBaseUrl();
  const driverUid = await uidForPhone(DRIVER_PHONE);
  const passengerUid = await uidForPhone(PASSENGER_PHONE);
  const driverToken = await idTokenForUid(driverUid);
  const passengerToken = await idTokenForUid(passengerUid);

  const steps: Record<string, unknown> = {
    base,
    driverUid,
    passengerUid,
  };

  let goOnline = await apiJson(base, 'POST', '/drivers/go-online', {
    bearer: driverToken,
    body: {},
  });
  steps.goOnline = { status: goOnline.status, data: goOnline.json.data ?? goOnline.json.error };

  let loc = await apiJson(base, 'POST', '/location/update', {
    bearer: driverToken,
    body: locBody(1),
  });
  steps.locationUpdate1 = { status: loc.status, data: loc.json.data ?? loc.json.error };

  if (loc.status !== 200) {
    loc = await apiJson(base, 'POST', '/location/update', {
      bearer: driverToken,
      body: locBody(2),
    });
    steps.locationUpdate2 = { status: loc.status, data: loc.json.data ?? loc.json.error };
  }

  const estimate = await apiJson(base, 'POST', '/pricing/estimate', {
    bearer: passengerToken,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      category: 'easy',
      city: 'lahore',
      serviceType: 'ride',
    },
  });
  steps.pricingEstimate = {
    status: estimate.status,
    data: estimate.json.data ?? estimate.json.error,
  };
  if (estimate.status !== 200) {
    console.log(JSON.stringify({ ok: false, steps }, null, 2));
    process.exit(1);
  }

  const estData = estimate.json.data as {
    pricingSnapshotId: string;
    recommendedFareMinor: number;
  };

  const rideRes = await apiJson(base, 'POST', '/rides', {
    bearer: passengerToken,
    idempotencyKey: `d1-proof-${randomUUID()}`,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      city: 'lahore',
      category: 'easy',
      serviceType: 'ride',
      passengerOfferMinor: estData.recommendedFareMinor,
      pricingSnapshotId: estData.pricingSnapshotId,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
  });
  steps.createRide = {
    status: rideRes.status,
    data: rideRes.json.data ?? rideRes.json.error,
  };
  if (rideRes.status !== 201) {
    console.log(JSON.stringify({ ok: false, steps }, null, 2));
    process.exit(1);
  }

  const rideId = (rideRes.json.data as { rideId: string }).rideId;
  steps.rideId = rideId;

  const tick = await apiJson(base, 'POST', `/internal/rides/${rideId}/dispatch-tick`, {
    worker,
  });
  steps.dispatchTick = {
    status: tick.status,
    data: tick.json.data ?? tick.json.error,
  };

  const sweep = await apiJson(base, 'POST', '/internal/outbox/dispatch-fcm-sweep', {
    worker,
  });
  steps.fcmSweep = {
    status: sweep.status,
    data: sweep.json.data ?? sweep.json.error,
  };

  const n4 = await apiJson(base, 'POST', '/internal/rides/dispatch-sweep', { worker });
  steps.dispatchSweep = {
    status: n4.status,
    data: n4.json.data ?? n4.json.error,
  };

  const ok =
    goOnline.status === 200 &&
    (steps.locationUpdate2 ? (steps.locationUpdate2 as { status: number }).status === 200 : loc.status === 200) &&
    tick.status === 200 &&
    sweep.status === 200;

  console.log(JSON.stringify({ ok, rideId, steps }, null, 2));
  if (!ok) process.exit(1);
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
