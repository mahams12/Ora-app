/**
 * One-shot cloud E2E for the temporary oraapp-a9be5 test window.
 * Synthetic accounts only (+92300 555xxx). Appends data; never deletes.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=.tmp/ora-test-adminsdk-key.json \
 *   ./node_modules/.bin/esbuild scripts/test_cloud_e2e.ts --bundle \
 *     --platform=node --format=cjs --outfile=.tmp/cloud_e2e.cjs \
 *     --external:firebase-admin --external:google-auth-library && \
 *   node .tmp/cloud_e2e.cjs
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { randomUUID } from 'crypto';
import * as fs from 'fs';

const BASE = process.env.TEST_BASE_URL ??
  'https://ora-auth-service-odo4zr22dq-el.a.run.app/v1';
const PROJECT = 'oraapp-a9be5';
const RTDB_URL =
  'https://oraapp-a9be5-default-rtdb.asia-southeast1.firebasedatabase.app';
const API_KEY = JSON.parse(
  fs.readFileSync('../../mobile/android/app/google-services.json', 'utf8'),
).client[0].api_key[0].current_key;

const app = initializeApp({
  credential: cert(process.env.GOOGLE_APPLICATION_CREDENTIALS!),
  projectId: PROJECT,
  databaseURL: RTDB_URL,
});
const auth = getAuth(app);
const db = getFirestore(app);
const rtdb = getDatabase(app);

const P_PHONE = '+923005550001';
const D_PHONES = ['+923005551001', '+923005551002', '+923005551003'];
// Lahore — pickup near Liberty Market; drivers at 0.3km, 1.5km, offline.
const PICKUP = { lat: 31.5102, lng: 74.3448 };
const DEST = { lat: 31.5204, lng: 74.3587 };
const D_LOC = [
  { lat: 31.5105, lng: 74.3460 },
  { lat: 31.4980, lng: 74.3400 },
];

const ts = () => new Date().toISOString();
const log = (m: string, o?: unknown) =>
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${m}`, o ?? '');

async function ensureUser(phone: string, name: string) {
  try {
    return await auth.getUserByPhoneNumber(phone);
  } catch {
    return auth.createUser({ phoneNumber: phone, displayName: name });
  }
}

async function idToken(uid: string): Promise<string> {
  const custom = await auth.createCustomToken(uid);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  const j = (await res.json()) as { idToken?: string; error?: unknown };
  if (!j.idToken) throw new Error(`signIn failed: ${JSON.stringify(j)}`);
  return j.idToken;
}

async function api(
  token: string,
  method: string,
  path: string,
  body?: unknown,
) {
  const t0 = Date.now();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(method === 'POST' ? { 'Idempotency-Key': randomUUID() } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = (await res.json().catch(() => null)) as { data?: unknown };
  return { status: res.status, ms: Date.now() - t0, json };
}

async function main() {
  const t0 = Date.now();
  log('== cloud E2E start ==', BASE);

  // ── 1. Synthetic users + profiles ────────────────────────────────
  const pUser = await ensureUser(P_PHONE, 'E2E Passenger');
  const dUsers = await Promise.all(
    D_PHONES.map((p, i) => ensureUser(p, `E2E Driver ${i + 1}`)),
  );
  log(`users ok: p=${pUser.uid} d=[${dUsers.map((u) => u.uid)}]`);

  await db.collection('users').doc(pUser.uid).set(
    { uid: pUser.uid, phoneNumber: P_PHONE, displayName: 'E2E Passenger',
      role: 'passenger', driverStatus: 'none', isActive: true,
      banned: false, profileComplete: true, updatedAt: ts() },
    { merge: true },
  );
  for (const u of dUsers) {
    await db.collection('users').doc(u.uid).set(
      { uid: u.uid, phoneNumber: D_PHONES[dUsers.indexOf(u)],
        displayName: 'E2E Driver', role: 'driver',
        driverStatus: 'approved', isActive: true, banned: false,
        profileComplete: true, updatedAt: ts() },
      { merge: true },
    );
    await db.collection('drivers').doc(u.uid).set(
      { uid: u.uid, vehicle: { type: 'car', model: 'E2E', plate: 'TST-1' },
        homeCity: 'lahore', availabilityState: 'offline', updatedAt: ts() },
      { merge: true },
    );
  }

  // ── 2. ID tokens ──────────────────────────────────────────────────
  const pTok = await idToken(pUser.uid);
  const dToks = await Promise.all(dUsers.map((u) => idToken(u.uid)));
  log('tokens minted + exchanged');

  // ── 3. Drivers 1+2 online + fake FCM token on driver 1 ───────────
  for (const i of [0, 1]) {
    const r = await api(dToks[i], 'POST', '/drivers/go-online', {});
    log(`driver${i + 1} go-online: ${r.status}`, r.json);
  }
  const tk = await api(dToks[0], 'POST', '/drivers/device-tokens', {
    token: `e2e-synthetic-fcm-token-${randomUUID()}-ab12`,
  });
  log(`driver1 device-token: ${tk.status}`, tk.json);

  // ── 4. Location publishes → geoDrivers markers ────────────────────
  const runTag = Date.now();
  for (const i of [0, 1]) {
    const r = await api(dToks[i], 'POST', '/location/update', {
      locationStreamId: `e2e-${dUsers[i].uid}-${runTag}`,
      locationSeq: 1,
      rideId: null,
      lat: D_LOC[i].lat, lng: D_LOC[i].lng,
      accuracy: 10, heading: 0, speed: 0,
      provider: 'e2e', timestamp: Date.now(),
      publishIntervalMs: 60000,
    });
    log(`driver${i + 1} loc update: ${r.status}`, JSON.stringify(r.json ?? {}).slice(0, 200));
  }
  const geo = await db.collection('geoDrivers').get();
  log(`geoDrivers docs: ${geo.size}`);

  // ── 5. Passenger: estimate + ride create → wave 1 ────────────────
  const est = await api(pTok, 'POST', '/pricing/estimate', {
    pickup: { ...PICKUP, address: 'Liberty Market' },
    destination: { ...DEST, address: 'Gulberg' },
    city: 'lahore', category: 'zip', serviceType: 'ride',
  });
  log(`estimate: ${est.status} (${est.ms}ms)`, JSON.stringify(est.json ?? {}).slice(0, 200));
  const snap = (est.json?.data ?? {}) as {
    pricingSnapshotId?: string;
    recommendedFareMinor?: number;
  };

  const createT0 = Date.now();
  const ride = await api(pTok, 'POST', '/rides', {
    pickup: { ...PICKUP, address: 'Liberty Market' },
    destination: { ...DEST, address: 'Gulberg' },
    city: 'lahore', category: 'zip', serviceType: 'ride',
    passengerOfferMinor: snap.recommendedFareMinor ?? 50000,
    pricingSnapshotId: snap.pricingSnapshotId,
    paymentMethod: 'CASH', passengerCount: 1,
  });
  log(`ride create: ${ride.status} (${ride.ms}ms)`, JSON.stringify(ride.json ?? {}).slice(0, 300));
  const rideId = (ride.json?.data as { rideId?: string })?.rideId;
  if (!rideId) throw new Error('ride create failed');

  // ── 6. Driver view: invited list ──────────────────────────────────
  await new Promise((r) => setTimeout(r, 1500));
  for (const i of [0, 1]) {
    const inv = await api(dToks[i], 'GET', '/rides/invited');
    log(`driver${i + 1} invited: ${inv.status}`, JSON.stringify(inv.json ?? {}).slice(0, 250));
  }

  // ── 7. Wave docs + outbox + RTDB check ────────────────────────────
  const waves = await db.collection('rideDispatchWaves')
    .where('rideId', '==', rideId).get();
  for (const w of waves.docs) {
    const d = w.data();
    log(`wave ${d.waveNumber}: drivers=${(d.driverIds ?? []).length} radius=${d.radiusKm} expires=${d.inviteExpiresAt}`);
  }
  const rtdbSnap = await rtdb.ref(`tripLocations/${rideId}/latest`).get();
  log(`rtdb tripLocations/${rideId}: ${rtdbSnap.exists() ? JSON.stringify(rtdbSnap.val()).slice(0, 150) : 'absent (pre-assign, expected)'}`);

  // ── 8. Driver 1 accepts → ASSIGNED ────────────────────────────────
  const waveId = waves.docs.map((d) => d.id).sort().pop();
  const acc = await api(dToks[0], 'POST',
    `/rides/${rideId}/invites/${waveId}/accept`,
    { offeredFareMinor: snap.recommendedFareMinor ?? 50000 });
  log(`driver1 accept: ${acc.status} (${acc.ms}ms)`, JSON.stringify(acc.json ?? {}).slice(0, 250));

  const rideDoc = await db.collection('rides').doc(rideId).get();
  const rd = rideDoc.data() ?? {};
  log(`ride state=${rd.state} assigned=${rd.assignedDriverId} (t+${Date.now() - createT0}ms from create)`);

  // ── 8b. Passenger selects the offer → ASSIGNED ────────────────────
  const offerId = (acc.json?.data as { offerId?: string })?.offerId;
  const sel = await api(pTok, 'POST',
    `/rides/${rideId}/offers/${offerId}/select`, {});
  log(`passenger select: ${sel.status} (${sel.ms}ms)`, JSON.stringify(sel.json ?? {}).slice(0, 250));
  const rd2 = (await db.collection('rides').doc(rideId).get()).data() ?? {};
  log(`ride state=${rd2.state} assigned=${rd2.assignedDriverId}`);

  // ── 9. Trip-mode location → RTDB projection ───────────────────────
  const trip = await api(dToks[0], 'POST', '/location/update', {
    locationStreamId: `e2e-trip-${rideId}`,
    locationSeq: 1, rideId,
    lat: PICKUP.lat, lng: PICKUP.lng,
    accuracy: 10, heading: 90, speed: 15,
    provider: 'e2e', timestamp: Date.now(),
    publishIntervalMs: 10000,
  });
  log(`trip loc update: ${trip.status}`, JSON.stringify(trip.json ?? {}).slice(0, 150));
  await new Promise((r) => setTimeout(r, 1500));
  const rtdb2 = await rtdb.ref(`tripLocations/${rideId}/latest`).get();
  log(`rtdb latest: ${rtdb2.exists() ? JSON.stringify(rtdb2.val()).slice(0, 200) : 'MISSING'}`);

  log(`== cloud E2E done (${Date.now() - t0}ms) ==`);
  process.exit(0);
}

main().catch((e) => {
  console.error('E2E FAILED:', e);
  process.exit(1);
});
