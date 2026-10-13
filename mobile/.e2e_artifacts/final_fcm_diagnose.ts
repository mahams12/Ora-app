/**
 * Diagnose D1 FCM skip/deliver for a disposable staging ride.
 * Does not change dispatch rules. Uses worker sweep with higher limit +
 * Firestore outbox inspection (no raw FCM tokens printed).
 *
 * Usage (from backend/auth-service):
 *   GOOGLE_APPLICATION_CREDENTIALS=secrets/service-account.json \
 *   npx tsx ../../mobile/.e2e_artifacts/final_fcm_diagnose.ts
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../..');
const backend = path.join(repoRoot, 'backend/auth-service');

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

function baseUrl(): string {
  return readFileSync(path.join(repoRoot, 'mobile/.staging_api_url'), 'utf8')
    .trim()
    .replace(/\/$/, '');
}

function workerToken(): string {
  const envPath = path.join(backend, '.env');
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    if (line.startsWith('ORA_INTERNAL_WORKER_TOKEN=')) {
      return line.slice('ORA_INTERNAL_WORKER_TOKEN='.length).trim();
    }
  }
  throw new Error('ORA_INTERNAL_WORKER_TOKEN missing');
}

function webApiKey(): string {
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  return JSON.parse(readFileSync(gs, 'utf8')).client[0].api_key[0].current_key;
}

async function idToken(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey()}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!res.ok) throw new Error(`token ${res.status}`);
  return ((await res.json()) as { idToken: string }).idToken;
}

async function api(
  base: string,
  method: string,
  route: string,
  opts: { bearer?: string; worker?: string; body?: unknown; idem?: string } = {},
) {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (opts.bearer) headers.Authorization = `Bearer ${opts.bearer}`;
  if (opts.worker) headers['X-Ora-Worker-Token'] = opts.worker;
  if (opts.body != null) headers['Content-Type'] = 'application/json';
  if (opts.idem) headers['Idempotency-Key'] = opts.idem;
  const res = await fetch(`${base}${route}`, {
    method,
    headers,
    body: opts.body != null ? JSON.stringify(opts.body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, json, at: new Date().toISOString() };
}

async function main(): Promise<void> {
  const sa =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ??
    path.join(backend, 'secrets/service-account.json');
  if (!getApps().length) initializeApp({ credential: cert(sa) });

  const base = baseUrl();
  const worker = workerToken();
  const driverUid = (await getAuth().getUserByPhoneNumber(DRIVER_PHONE)).uid;
  const passengerUid = (await getAuth().getUserByPhoneNumber(PASSENGER_PHONE)).uid;
  const driverToken = await idToken(driverUid);
  const passengerToken = await idToken(passengerUid);
  const db = getFirestore();

  const tokenSnap = await db
    .collection('driverDeviceTokens')
    .where('driverId', '==', driverUid)
    .limit(5)
    .get();

  const report: Record<string, unknown> = {
    startedAt: new Date().toISOString(),
    base,
    driverUid,
    passengerUid,
    tokenDocCount: tokenSnap.size,
    tokensHaveValue: tokenSnap.docs.map((d) => ({
      id: d.id,
      hasToken:
        typeof d.get('token') === 'string' &&
        String(d.get('token')).length > 16,
    })),
  };

  // Driver online + location
  await api(base, 'POST', '/drivers/go-online', {
    bearer: driverToken,
    body: {},
  });
  await api(base, 'POST', '/location/update', {
    bearer: driverToken,
    body: {
      locationSeq: 1,
      locationStreamId: `final-fcm-${Date.now()}`,
      lat: PICKUP.lat,
      lng: PICKUP.lng,
      accuracy: 8,
      heading: 90,
      speed: 0,
      timestamp: new Date().toISOString(),
      provider: 'gps',
    },
  });

  const estimate = await api(base, 'POST', '/pricing/estimate', {
    bearer: passengerToken,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      category: 'easy',
      city: 'lahore',
      serviceType: 'ride',
    },
  });
  if (estimate.status !== 200) {
    console.log(JSON.stringify({ ok: false, step: 'estimate', estimate }, null, 2));
    process.exit(1);
  }
  const est = estimate.json.data as {
    pricingSnapshotId: string;
    recommendedFareMinor: number;
  };

  const createAt = new Date().toISOString();
  const rideRes = await api(base, 'POST', '/rides', {
    bearer: passengerToken,
    idem: `final-fcm-${randomUUID()}`,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      city: 'lahore',
      category: 'easy',
      serviceType: 'ride',
      passengerOfferMinor: est.recommendedFareMinor,
      pricingSnapshotId: est.pricingSnapshotId,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
  });
  const rideId = (rideRes.json.data as { rideId?: string })?.rideId;
  report.createRide = {
    at: createAt,
    status: rideRes.status,
    rideId,
  };
  if (rideRes.status !== 201 || !rideId) {
    console.log(JSON.stringify({ ok: false, report }, null, 2));
    process.exit(1);
  }

  const tickAt = new Date().toISOString();
  const tick = await api(base, 'POST', `/internal/rides/${rideId}/dispatch-tick`, {
    worker,
  });
  report.dispatchTick = {
    at: tickAt,
    status: tick.status,
    data: tick.json.data ?? tick.json.error,
  };

  // Inspect outbox for this ride immediately after tick
  const outboxSnap = await db
    .collection('outboxEvents')
    .where('eventType', '==', 'ride.dispatch.wave_completed')
    .limit(100)
    .get();

  const related = outboxSnap.docs
    .map((d) => {
      const data = d.data();
      const payload = (data.payload ?? {}) as Record<string, unknown>;
      const payloadRide =
        (payload.rideId as string | undefined) ??
        (data.aggregateId as string | undefined) ??
        null;
      return {
        eventId: d.id,
        publishState: data.publishState,
        payloadRideId: payloadRide,
        aggregateId: data.aggregateId ?? null,
        createdAt: data.createdAt ?? null,
        nextAttemptAt: data.nextAttemptAt ?? null,
        matchesTarget: payloadRide === rideId,
      };
    })
    .filter((e) => e.matchesTarget || e.publishState === 'PENDING');

  const targetEvents = related.filter((e) => e.matchesTarget);
  report.outboxAfterTick = {
    scannedSample: outboxSnap.size,
    targetEventCount: targetEvents.length,
    targetEvents,
    pendingCount: related.filter((e) => e.publishState === 'PENDING').length,
  };

  const sweep1At = new Date().toISOString();
  const sweep1 = await api(base, 'POST', '/internal/outbox/dispatch-fcm-sweep?limit=100', {
    worker,
  });
  report.fcmSweepLimit100 = {
    at: sweep1At,
    status: sweep1.status,
    data: sweep1.json.data ?? sweep1.json.error,
  };

  // Re-read target events
  const after: unknown[] = [];
  for (const e of targetEvents) {
    const snap = await db.collection('outboxEvents').doc(e.eventId).get();
    after.push({
      eventId: e.eventId,
      publishState: snap.exists ? snap.get('publishState') : 'MISSING',
    });
  }
  report.outboxAfterSweep = after;

  const open = await api(base, 'GET', '/rides/open?limit=20', {
    bearer: driverToken,
  });
  const rides = ((open.json.data as { rides?: unknown[] })?.rides ?? []) as Array<{
    rideId: string;
  }>;
  report.openList = {
    status: open.status,
    containsRide: rides.some((r) => r.rideId === rideId),
    count: rides.length,
  };

  report.finishedAt = new Date().toISOString();
  report.ok = true;
  report.analysis = {
    priorSkipHypothesis:
      'Default sweep limit=25 with no orderBy often samples already-DELIVERED events → skipped++, never reaches new PENDING.',
    thisRunDelivered: (sweep1.json.data as { delivered?: number })?.delivered ?? null,
    thisRunProcessed: (sweep1.json.data as { processed?: number })?.processed ?? null,
    thisRunSkipped: (sweep1.json.data as { skipped?: number })?.skipped ?? null,
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
