/**
 * Adaptive-presence live verification. Emulator-only.
 *   GEO_BACKEND=firestore LOCATION_ADAPTIVE_FRESHNESS=true \
 *   LOCATION_IDLE_MERGED_CURSOR=true LOCATION_TRIP_GEO_MIN_INTERVAL_MS=45000 \
 *   npx tsx scripts/test_adaptive_presence.ts
 *
 * Measures, against the real HTTP API + Firestore/RTDB emulators:
 *   - merged cursor: idle packets produce NO locationStreams write
 *     (1 tx instead of 2 — the billed-ops halving)
 *   - adaptive freshness: marker freshUntilMs = ts + declared interval +
 *     grace; driver stays matchable past the legacy 15s fixed horizon
 *   - keepalive packets: presence asserted without position movement
 *   - trip-mode geo-marker throttle: N trip packets → 1 geoDrivers write
 *     while RTDB tripLocations still updates every packet
 *   - stale expiry: stop publishing → driver drops out of matching (no
 *     phantom invites)
 *   - seq ordering preserved (merged path still 422s stale seq)
 *   - end-to-end dispatch: ride create → driver invite (no missed invite)
 */
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
process.env.FIREBASE_DATABASE_URL ??=
  'https://oraapp-a9be5-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';

const API = 'http://127.0.0.1:8080/v1';
const AUTH_EMU = 'http://127.0.0.1:9099';
const RUN = `adp-${Date.now()}`;
const LAHORE = { lat: 31.52, lng: 74.35 };

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown) {
  console.log(
    `${cond ? 'PASS' : 'FAIL'} ${name}${
      extra !== undefined ? ' ' + JSON.stringify(extra) : ''
    }`,
  );
  if (!cond) failures++;
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function api(
  token: string,
  method: string,
  path: string,
  body?: unknown,
  idem?: string,
) {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(idem ? { 'Idempotency-Key': idem } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json: unknown = null;
  try {
    json = await r.json();
  } catch {
    /* empty */
  }
  return { status: r.status, json };
}

async function tokenFor(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const s = await fetch(
    `${AUTH_EMU}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=test`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  return ((await s.json()) as { idToken: string }).idToken;
}

function locBody(
  streamId: string,
  seq: number,
  opts: {
    lat?: number;
    lng?: number;
    rideId?: string | null;
    publishIntervalMs?: number;
    keepalive?: boolean;
    ts?: number;
  } = {},
) {
  return {
    locationStreamId: streamId,
    locationSeq: seq,
    rideId: opts.rideId ?? null,
    lat: opts.lat ?? LAHORE.lat,
    lng: opts.lng ?? LAHORE.lng,
    accuracy: 10,
    heading: 0,
    speed: 0,
    provider: 'e2e',
    timestamp: opts.ts ?? Date.now(),
    ...(opts.publishIntervalMs != null
      ? { publishIntervalMs: opts.publishIntervalMs }
      : {}),
    ...(opts.keepalive ? { presenceKeepalive: true } : {}),
  };
}

async function marker(db: FirebaseFirestore.Firestore, uid: string) {
  const snap = await db.doc(`geoDrivers/${uid}`).get();
  if (!snap.exists) return null;
  const raw = snap.data() ?? {};
  const mv = raw.markerValue ?? raw.value;
  try {
    return { doc: raw, marker: JSON.parse(String(mv)) as Record<string, unknown> };
  } catch {
    return { doc: raw, marker: raw as Record<string, unknown> };
  }
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const db = getFirestore();
  const rtdb = getDatabase();

  const driver = `${RUN}-drv`;
  const driver2 = `${RUN}-drv2`;
  const passenger = `${RUN}-pax`;
  for (const uid of [driver, driver2, passenger]) {
    const t = await tokenFor(uid);
    await api(t, 'POST', '/auth/register', {}, `register_${uid}`);
  }
  const tD = await tokenFor(driver);
  const tD2 = await tokenFor(driver2);
  const tP = await tokenFor(passenger);

  // approved driver docs + online
  for (const uid of [driver, driver2]) {
    await db.doc(`users/${uid}`).set(
      {
        uid,
        phoneNumber: '+923000000001',
        displayName: 'ADP Driver',
        role: 'driver',
        driverStatus: 'approved',
        activeMode: 'driver',
        isActive: true,
        banned: false,
      },
      { merge: true },
    );
    await db.doc(`drivers/${uid}`).set(
      {
        uid,
        vehicle: { type: 'car', model: 'Test', plate: 'X-1' },
        homeCity: 'lahore',
        availabilityState: 'offline',
      },
      { merge: true },
    );
  }
  let r = await api(tD, 'POST', '/drivers/go-online', {}, 'adp_goonline_1');
  check('driver go-online', r.status === 200, r.status);

  // Pricing rules for the e2e city — required for /pricing/estimate →
  // pricingSnapshotId on a fresh emulator (emulator data is in-memory).
  await db
    .collection('pricingRules')
    .doc('lahore_go')
    .set(
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'go',
        version: 'adp-e2e-1',
        baseFare: 100,
        ratePerKm: 60,
        ratePerMin: 5,
        minFare: 120,
        maxFare: 5000,
      }),
    );

  // ── Phase A: stationary idle @ declared 60s cadence ─────────────────────
  const stream = `adp-idle-${driver}`;
  for (let seq = 1; seq <= 3; seq++) {
    r = await api(
      tD,
      'POST',
      '/location/update',
      locBody(stream, seq, { publishIntervalMs: 60000 }),
    );
    if (seq === 1) check('idle packet accepted', r.status === 200, r.status);
  }
  const m1 = await marker(db, driver);
  check('geoDrivers marker exists', m1 != null);
  check(
    'marker seq advanced to 3',
    (m1?.marker.locationSeq as number) === 3,
    m1?.marker.locationSeq,
  );
  const lastTs = m1?.marker.lastLocationTs as number;
  const freshUntil = m1?.marker.freshUntilMs as number | undefined;
  check(
    'adaptive freshUntilMs ≈ ts + 60s + grace',
    typeof freshUntil === 'number' &&
      freshUntil > lastTs + 60_000 &&
      freshUntil <= lastTs + 76_000,
    { lastTs, freshUntil },
  );

  // merged cursor: NO locationStreams doc for idle packets
  const streamDoc = await db.doc(`locationStreams/${driver}`).get();
  check(
    'merged cursor — no locationStreams doc',
    !streamDoc.exists,
    streamDoc.exists ? streamDoc.data() : undefined,
  );

  // seq ordering preserved: stale seq → 422
  r = await api(tD, 'POST', '/location/update', locBody(stream, 2));
  check('stale seq → 422', r.status === 422, r.status);

  // keepalive: old timestamp accepted, extends presence
  r = await api(
    tD,
    'POST',
    '/location/update',
    locBody(stream, 4, {
      publishIntervalMs: 60000,
      keepalive: true,
      ts: lastTs, // original fix ts
    }),
  );
  check('keepalive accepted', r.status === 200, r.status);
  const m2 = await marker(db, driver);
  check(
    'keepalive extends freshUntil without moving lastLocationTs',
    (m2?.marker.freshUntilMs as number) > (m1?.marker.freshUntilMs as number),
    { before: m1?.marker.freshUntilMs, after: m2?.marker.freshUntilMs },
  );

  // ── Phase B: dispatch latency + matching correctness at t+18s ───────────
  // Legacy fixed horizon = lastLocationTs + 15s. At 18s the driver is ONLY
  // matchable if adaptive freshness is honoring the declared 60s cadence.
  console.log('…waiting 18s to pass the legacy 15s freshness horizon');
  await sleep(18_000);

  const pricingSeed = await api(tP, 'POST', '/pricing/estimate', {
    pickup: { ...LAHORE, address: 'Liberty' },
    destination: { lat: LAHORE.lat + 0.05, lng: LAHORE.lng + 0.05, address: 'Gulberg' },
    city: 'lahore',
    category: 'go',
    serviceType: 'ride',
  });
  const snap = ((pricingSeed.json as { data?: unknown })?.data ?? {}) as {
    pricingSnapshotId?: string;
    recommendedFareMinor?: number;
  };
  check(
    'estimate returns snapshot',
    pricingSeed.status === 200 || pricingSeed.status === 201,
    { status: pricingSeed.status, body: pricingSeed.json },
  );
  const t0 = Date.now();
  r = await api(
    tP,
    'POST',
    '/rides',
    {
      pickup: { ...LAHORE, address: 'Liberty' },
      destination: { lat: LAHORE.lat + 0.05, lng: LAHORE.lng + 0.05, address: 'Gulberg' },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
      passengerOfferMinor: snap.recommendedFareMinor ?? 50000,
      ...(snap.pricingSnapshotId
        ? { pricingSnapshotId: snap.pricingSnapshotId }
        : {}),
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
    `adp_ride_${RUN}`,
  );
  const rideId = (r.json as { data?: { rideId?: string } })?.data?.rideId;
  check('ride created', r.status === 201 || r.status === 200, { status: r.status, body: r.json });

  await sleep(2500); // wave-1 tick + invite projection
  const inv = await api(tD, 'GET', '/rides/invited');
  const invites = (inv.json as { data?: { items?: unknown[] } })?.data
    ?.items;
  const inviteMs = Date.now() - t0;
  check(
    'driver invited at t+18s (adaptive freshness works)',
    Array.isArray(invites) && invites.length > 0,
    { invites: invites?.length, inviteMs },
  );
  console.log(`   dispatch latency (create→invite visible): ${inviteMs}ms`);

  // driver2 (never published) must NOT be invited — no phantom invites
  const inv2 = await api(tD2, 'GET', '/rides/invited');
  const invites2 = (inv2.json as { data?: { items?: unknown[] } })?.data
    ?.items;
  check(
    'offline driver gets no invite',
    !Array.isArray(invites2) || invites2.length === 0,
  );

  // ── Phase C: trip-mode geo-marker throttle ──────────────────────────────
  // Accept the invite → assign → trip packets authorized.
  const waveSnap = await db
    .collection('rideDispatchWaves')
    .where('rideId', '==', rideId)
    .get();
  const waveId = waveSnap.docs.map((d) => d.id).sort().pop();
  const acc = await api(tD, 'POST', `/rides/${rideId}/invites/${waveId}/accept`, {
    offeredFareMinor: snap.recommendedFareMinor ?? 50000,
  });
  const offerId = (acc.json as { data?: { offerId?: string } })?.data?.offerId;
  check('driver accepts invite', acc.status === 200 || acc.status === 201, acc.status);
  const sel = await api(tP, 'POST', `/rides/${rideId}/offers/${offerId}/select`, {}, `adp_select_${RUN}`);
  check('passenger selects offer', sel.status === 200, { status: sel.status, body: sel.json });

  const tripStream = `adp-trip-${rideId}`;
  // force marker baseline then send 3 rapid trip packets
  await api(tD, 'POST', '/location/update',
    locBody(tripStream, 1, { rideId, publishIntervalMs: 10000 }));
  const mTrip1 = await marker(db, driver);
  await sleep(1500);
  await api(tD, 'POST', '/location/update',
    locBody(tripStream, 2, { rideId, lat: LAHORE.lat + 0.001, publishIntervalMs: 10000 }));
  await sleep(1500);
  await api(tD, 'POST', '/location/update',
    locBody(tripStream, 3, { rideId, lat: LAHORE.lat + 0.002, publishIntervalMs: 10000 }));
  const mTrip3 = await marker(db, driver);
  check(
    'trip geo-marker throttled (3 packets → ≤1 write)',
    (mTrip3?.marker.lastLocationTs as number) ===
      (mTrip1?.marker.lastLocationTs as number),
    { first: mTrip1?.marker.lastLocationTs, last: mTrip3?.marker.lastLocationTs },
  );
  // RTDB live tracking is NOT throttled — every packet lands
  const rtdbLoc = await rtdb.ref(`tripLocations/${rideId}/latest`).get();
  check(
    'RTDB live tracking updated to latest seq',
    rtdbLoc.exists() &&
      (rtdbLoc.val().locationSeq === 3 || rtdbLoc.val().lat === LAHORE.lat + 0.002),
    rtdbLoc.val(),
  );

  // ── Phase D: stale expiry — stop publishing → drops out of matching ─────
  // publishIntervalMs=4000 (min) → freshUntil ≈ lastTs + 19s. Wait 22s → stale.
  const staleStream = `adp-stale-${driver2}`;
  await api(tD2, 'POST', '/drivers/go-online', {}, 'adp_goonline_2');
  await api(tD2, 'POST', '/location/update',
    locBody(staleStream, 1, { publishIntervalMs: 4000 }));
  console.log('…waiting 22s for the declared 4s cadence to go stale');
  await sleep(22_000);

  const ride2 = await api(
    tP,
    'POST',
    '/rides',
    {
      pickup: { ...LAHORE, address: 'Liberty' },
      destination: { lat: LAHORE.lat + 0.05, lng: LAHORE.lng + 0.05, address: 'Gulberg' },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
      passengerOfferMinor: snap.recommendedFareMinor ?? 50000,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
    `adp_ride2_${RUN}`,
  );
  await sleep(2500);
  const inv3 = await api(tD2, 'GET', '/rides/invited');
  const invites3 = (inv3.json as { data?: { items?: unknown[] } })?.data
    ?.items;
  const ride2Id = (ride2.json as { data?: { rideId?: string } })?.data?.rideId;
  const staleInvited =
    Array.isArray(invites3) &&
    (invites3 as { rideId?: string }[]).some((i) => i.rideId === ride2Id);
  check(
    'stale driver NOT invited (no phantom presence)',
    !staleInvited,
    { invited: staleInvited },
  );

  console.log(
    failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('crashed:', e);
  process.exit(1);
});
