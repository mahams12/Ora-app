/**
 * Zero-cost local E2E — exercises the full passenger/driver ride flow over HTTP
 * against the emulator-backed auth-service. No cloud calls, no billing.
 *
 * Prereqs:
 *   1. firebase emulators:start --project ora-app-d8112 --only auth,firestore,database
 *   2. ./scripts/dev_emulator_backend.sh   (auth-service on :8080)
 *   3. ./scripts/dev_local_ticks.sh        (local scheduler replacement)
 *
 * Run:  ./node_modules/.bin/tsx scripts/run_local_emulator_e2e.ts
 *
 * Exit 0 = all checks passed. Every assertion prints PASS/FAIL evidence.
 */

// ORA_CLOUD=1 targets the real deployed stack — skip emulator defaults so
// admin SDK writes land in real Firestore/RTDB.
if (process.env.ORA_CLOUD !== '1') {
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
  process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
}
process.env.FIREBASE_PROJECT_ID ??= 'ora-app-d8112';
process.env.FIREBASE_DATABASE_URL ??=
  'https://ora-app-d8112-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';

const API = process.env.ORA_API ?? 'http://127.0.0.1:8080';
const AUTH_EMU =
  process.env.ORA_AUTH_BASE ??
  `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com`;
const AUTH_KEY = process.env.ORA_AUTH_KEY ?? 'emulator';
const WORKER = process.env.ORA_INTERNAL_WORKER_TOKEN ?? 'local-dev-worker-token-xx';

let passed = 0;
let failed = 0;
function check(name: string, cond: boolean, detail = '') {
  if (cond) {
    passed++;
    console.log(`  PASS ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name} ${detail}`);
  }
}

async function api(
  path: string,
  opts: {
    method?: string;
    token?: string;
    body?: unknown;
    worker?: boolean;
    idempotencyKey?: string;
  } = {},
): Promise<{ status: number; json: any }> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  if (opts.worker) headers['x-ora-worker-token'] = WORKER;
  if (opts.idempotencyKey) headers['idempotency-key'] = opts.idempotencyKey;
  const res = await fetch(`${API}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body == null ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function signUp(email: string): Promise<{ uid: string; idToken: string }> {
  const call = async (endpoint: string) => {
    const res = await fetch(
      `${AUTH_EMU}/v1/${endpoint}?key=${AUTH_KEY}`,
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          email,
          password: 'localdev-pass-1',
          returnSecureToken: true,
        }),
      },
    );
    return res.json();
  };
  let j = await call('accounts:signUp');
  if (j.error?.message === 'EMAIL_EXISTS') {
    j = await call('accounts:signInWithPassword');
  }
  if (!j.idToken) throw new Error(`signUp failed: ${JSON.stringify(j)}`);
  return { uid: j.localId, idToken: j.idToken };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function pollInvited(
  token: string,
  rideId: string,
  timeoutMs: number,
  keepAlive?: () => Promise<unknown>,
): Promise<any | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const r = await api('/v1/rides/invited', { token });
    const item = (r.json?.data?.items ?? []).find(
      (i: any) => i.rideId === rideId,
    );
    if (item) return { item, serverNowMs: r.json.data.serverNowMs };
    // Cloud sweeps run ~60s apart; driver freshness floors are shorter, so a
    // single stale marker yields zero candidates. Refresh like a real device.
    if (keepAlive) await keepAlive().catch(() => undefined);
    await sleep(700);
  }
  return null;
}

const LAHORE = { lat: 31.5204, lng: 74.3587 };
const RUN_ID = Date.now();
// Cloud Scheduler ticks at most once/minute — local ticks are ~2s.
const INVITE_WAIT_MS = process.env.ORA_CLOUD === '1' ? 75_000 : 20_000;

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const db = getFirestore();
  const rtdb = getDatabase();

  console.log('== setup: auth users + profiles + pricing rule ==');
  const passenger = await signUp('passenger@local.dev');
  const driver = await signUp('driver@local.dev');
  const driver2 = await signUp('driver2@local.dev');
  const outsider = await signUp('outsider@local.dev');
  // Run-unique email: the auth emulator persists accounts between runs, and a
  // reused uid could carry an already-approved users doc that poisons the
  // switch assertions below.
  const passenger2 = await signUp(`switcher_${RUN_ID}@local.dev`);

  // Passenger registers through the real API path.
  const reg = await api('/v1/auth/register', {
    method: 'POST',
    token: passenger.idToken,
    body: {},
    idempotencyKey: `register_${passenger.uid}`,
  });
  check('passenger register', reg.status === 200 || reg.status === 201, JSON.stringify(reg.json));

  // Driver approval is an ops action — seed users doc directly (admin role).
  await db.collection('users').doc(driver.uid).set({
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  await db.collection('users').doc(driver2.uid).set({
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  await db.collection('users').doc(outsider.uid).set({
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });

  await db
    .collection('pricingRules')
    .doc('lahore_go')
    .set(
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'go',
        version: 'local-e2e-1',
        baseFare: 100,
        ratePerKm: 60,
        ratePerMin: 5,
        minFare: 120,
        maxFare: 5000,
      }),
    );

  // Ora Courier — same-day parcel pricing for the local e2e city.
  await db
    .collection('pricingRules')
    .doc('lahore_courier')
    .set(
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'courier',
        version: 'local-e2e-1',
        baseFare: 150,
        ratePerKm: 70,
        ratePerMin: 5,
        minFare: 150,
        maxFare: 8000,
      }),
    );

  console.log('== driver availability + geo presence ==');
  const online = await api('/v1/drivers/go-online', {
    method: 'POST',
    token: driver.idToken,
    body: {},
  });
  check('driver go-online', online.status === 200, JSON.stringify(online.json));
  const online2 = await api('/v1/drivers/go-online', {
    method: 'POST',
    token: driver2.idToken,
    body: {},
  });
  check('driver2 go-online', online2.status === 200, JSON.stringify(online2.json));

  for (const [d, lat] of [
    [driver, LAHORE.lat],
    [driver2, LAHORE.lat + 0.02],
  ] as const) {
    const loc = await api('/v1/location/update', {
      method: 'POST',
      token: d.idToken,
      body: {
        locationSeq: 1,
        locationStreamId: `stream-${d.uid}-${RUN_ID}`,
        lat,
        lng: LAHORE.lng,
        accuracy: 10,
        heading: 0,
        speed: 0,
        provider: 'gps',
        timestamp: Date.now(),
      },
    });
    check(`location update ${d.uid === driver.uid ? 'driver' : 'driver2'}`, loc.status === 200, JSON.stringify(loc.json));
  }
  const geoBackend = (process.env.GEO_BACKEND ?? 'firestore').trim().toLowerCase();
  if (geoBackend === 'rtdb') {
    const geoSnap = await rtdb.ref(`geoPresence/${driver.uid}`).get();
    const node = geoSnap.val() as { g?: string; expiresAtMs?: number } | null;
    check(
      'geoPresence node written (RTDB geo store)',
      geoSnap.exists() &&
        typeof node?.g === 'string' &&
        (node?.expiresAtMs ?? 0) > Date.now(),
      JSON.stringify(node),
    );
  } else {
    const geoDoc = await db.collection('geoDrivers').doc(driver.uid).get();
    check('geoDrivers doc written (Firestore geo store)', geoDoc.exists);
  }

  console.log('== pricing estimate (haversine routing — zero cost) ==');
  const est = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.55, lng: 74.33 },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
    },
  });
  check('estimate 200 + snapshotId', est.status === 200 && !!est.json?.data?.pricingSnapshotId, JSON.stringify(est.json));
  const snapId = est.json?.data?.pricingSnapshotId;
  const recommended = est.json?.data?.recommendedFareMinor;

  console.log('== ride create + dispatch wave ==');
  const create = await api('/v1/rides', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.55, lng: 74.33 },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
      paymentMethod: 'CASH',
      passengerCount: 1,
      pricingSnapshotId: snapId,
      passengerOfferMinor: recommended,
    },
    idempotencyKey: `ride_${passenger.uid}_${Date.now()}`,
  });
  check('ride created', create.status === 201 || create.status === 200, JSON.stringify(create.json));
  const rideId = create.json?.data?.rideId ?? create.json?.data?.id;

  let drvSeq = 3;
  const drvKeepAlive = () =>
    api('/v1/location/update', {
      method: 'POST',
      token: driver.idToken,
      body: {
        locationSeq: drvSeq++,
        locationStreamId: `stream-${driver.uid}-${RUN_ID}`,
        lat: LAHORE.lat,
        lng: LAHORE.lng,
        accuracy: 10,
        heading: 0,
        speed: 0,
        provider: 'gps',
        timestamp: Date.now(),
      },
    });
  const inv = await pollInvited(
    driver.idToken,
    rideId,
    INVITE_WAIT_MS,
    drvKeepAlive,
  );
  check('driver invited via /v1/rides/invited', !!inv, 'no invite in 20s');
  const inviteExpiresMs = inv ? Date.parse(inv.item.inviteExpiresAt) : 0;
  const ttlMs = inv ? inviteExpiresMs - inv.serverNowMs : 0;
  check(
    'invite TTL ≈ 20s server-authoritative',
    inv != null && ttlMs > 14_000 && ttlMs <= 21_000,
    `ttlMs=${ttlMs}`,
  );

  console.log('== invite guardrails ==');
  const badAccept = await api(
    `/v1/rides/${rideId}/invites/${inv?.item?.waveId}/accept`,
    { method: 'POST', token: outsider.idToken, body: {} },
  );
  check('outsider accept rejected', badAccept.status === 403 || badAccept.status === 404 || badAccept.status === 422, JSON.stringify(badAccept.json));

  const decline2 = await api(
    `/v1/rides/${rideId}/invites/${inv?.item?.waveId}/decline`,
    { method: 'POST', token: driver2.idToken, body: {} },
  );
  check('driver2 decline', decline2.status === 200, JSON.stringify(decline2.json));
  const decline2b = await api(
    `/v1/rides/${rideId}/invites/${inv?.item?.waveId}/decline`,
    { method: 'POST', token: driver2.idToken, body: {} },
  );
  check('decline idempotent', decline2b.status === 200, JSON.stringify(decline2b.json));

  console.log('== accept → offer → passenger select (invite accept ≠ assign) ==');
  const accept = await api(
    `/v1/rides/${rideId}/invites/${inv?.item?.waveId}/accept`,
    { method: 'POST', token: driver.idToken, body: {} },
  );
  check('driver accept → offer created', accept.status === 200 || accept.status === 201, JSON.stringify(accept.json));

  const acceptAgain = await api(
    `/v1/rides/${rideId}/invites/${inv?.item?.waveId}/accept`,
    { method: 'POST', token: driver.idToken, body: {} },
  );
  check('accept idempotent (no dup offer)', acceptAgain.status === 200 || acceptAgain.status === 201, JSON.stringify(acceptAgain.json));

  const offers = await api(`/v1/rides/${rideId}/offers`, { token: passenger.idToken });
  const offerList = offers.json?.data?.items ?? offers.json?.data?.offers ?? [];
  check('one offer visible to passenger', offerList.length === 1, JSON.stringify(offers.json));
  const offerId = offerList[0]?.offerId ?? offerList[0]?.id;

  const sel = await api(`/v1/rides/${rideId}/offers/${offerId}/select`, {
    method: 'POST',
    token: passenger.idToken,
    body: {},
    idempotencyKey: `sel_${rideId}`,
  });
  check('passenger select → assigned', sel.status === 200 && /assign/i.test(JSON.stringify(sel.json)), JSON.stringify(sel.json));

  console.log('== lifecycle: en-route → arrive → start → complete ==');
  const rideSnap = async () =>
    (await api(`/v1/rides/${rideId}`, { token: passenger.idToken })).json?.data;

  const locTrip = await api('/v1/location/update', {
    method: 'POST',
    token: driver.idToken,
    body: {
      rideId,
      locationSeq: 2,
      locationStreamId: `stream-${driver.uid}-${RUN_ID}`,
      lat: LAHORE.lat + 0.001,
      lng: LAHORE.lng + 0.001,
      accuracy: 10,
      heading: 90,
      speed: 30,
      provider: 'gps',
      timestamp: Date.now(),
    },
  });
  check('trip location update accepted', locTrip.status === 200, JSON.stringify(locTrip.json));
  await sleep(500);
  const rtdbSnap = await rtdb.ref(`tripLocations/${rideId}/latest`).get();
  check('RTDB tripLocations latest projected', rtdbSnap.exists());

  for (const step of ['en-route', 'arrive', 'start', 'complete'] as const) {
    const r = await api(`/v1/rides/${rideId}/${step}`, {
      method: 'POST',
      token: driver.idToken,
      body: {},
      idempotencyKey: `${step}_${rideId}`,
    });
    check(`POST /${step}`, r.status === 200, JSON.stringify(r.json));
  }
  const finalRide = await rideSnap();
  check('ride state COMPLETED', /COMPLETED|completed/i.test(JSON.stringify(finalRide)));

  console.log('== rating persistence ==');
  const rate = await api(`/v1/rides/${rideId}/ratings`, {
    method: 'POST',
    token: passenger.idToken,
    body: { stars: 5 },
    idempotencyKey: `rate_${rideId}_${passenger.uid}`,
  });
  check('rate driver', rate.status === 200 || rate.status === 201, JSON.stringify(rate.json));
  const ratings = await api(`/v1/rides/${rideId}/ratings`, { token: passenger.idToken });
  check('ratings readable', ratings.status === 200, JSON.stringify(ratings.json));

  console.log('== expired invite cannot be accepted (real 20s wait) ==');
  // An online driver republishes every ~10s; refresh presence so the invite
  // check does not race the 15s freshness gate after the ride-1 lifecycle.
  // Refresh on the SAME stream with a higher seq — a new streamId here would
  // push the keep-alive stream into previousStreamIds and every subsequent
  // keep-alive would be rejected as a replaced stream.
  const relog = await drvKeepAlive();
  check('driver presence refresh for ride2', relog.status === 200, JSON.stringify(relog.json));
  const est2 = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.56, lng: 74.32 },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
    },
  });
  const create2 = await api('/v1/rides', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.56, lng: 74.32 },
      city: 'lahore',
      category: 'go',
      serviceType: 'ride',
      paymentMethod: 'CASH',
      passengerCount: 1,
      pricingSnapshotId: est2.json?.data?.pricingSnapshotId,
      passengerOfferMinor: est2.json?.data?.recommendedFareMinor,
    },
    idempotencyKey: `ride_${passenger.uid}_${Date.now()}_b`,
  });
  const ride2 = create2.json?.data?.rideId ?? create2.json?.data?.id;
  const inv2 = await pollInvited(
    driver.idToken,
    ride2,
    INVITE_WAIT_MS,
    drvKeepAlive,
  );
  check('ride2 invite delivered', !!inv2);
  if (inv2) {
    const waitMs = Math.max(0, Date.parse(inv2.item.inviteExpiresAt) - Date.now() + 1500);
    console.log(`  … waiting ${Math.round(waitMs / 1000)}s for server-side expiry`);
    await sleep(waitMs);
    const late = await api(
      `/v1/rides/${ride2}/invites/${inv2.item.waveId}/accept`,
      { method: 'POST', token: driver.idToken, body: {} },
    );
    check(
      'expired accept rejected INVITE_EXPIRED',
      late.json?.error?.code === 'INVITE_EXPIRED',
      JSON.stringify(late.json),
    );
  }

  // ── Ora Courier — Send Parcel leg ──────────────────────────────────────
  console.log('== courier: estimate → create with parcel → dispatch ==');
  // The 21s expiry wait above leaves the driver geo marker beyond the 15s
  // freshness window — refresh presence before creating the courier booking
  // so the first dispatch wave sees a live driver.
  const cRelog = await drvKeepAlive();
  check(
    'driver presence refresh for courier leg',
    cRelog.status === 200,
    JSON.stringify(cRelog.json),
  );
  const cEst = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.57, lng: 74.31 },
      city: 'lahore',
      category: 'courier',
      serviceType: 'courier',
    },
  });
  check(
    'courier estimate 200 + snapshotId',
    cEst.status === 200 && !!cEst.json?.data?.pricingSnapshotId,
    JSON.stringify(cEst.json),
  );
  const cCreate = await api('/v1/rides', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: LAHORE,
      destination: { lat: 31.57, lng: 74.31 },
      city: 'lahore',
      category: 'courier',
      serviceType: 'courier',
      paymentMethod: 'CASH',
      passengerCount: 1,
      pricingSnapshotId: cEst.json?.data?.pricingSnapshotId,
      passengerOfferMinor: cEst.json?.data?.recommendedFareMinor,
      parcel: {
        senderName: 'E2E Sender',
        senderPhone: '+923001112233',
        receiverName: 'E2E Receiver',
        receiverPhone: '+923004445566',
        parcelCategory: 'documents',
        size: 'SMALL',
        weightKg: 1.5,
        quantity: 1,
        description: 'E2E test documents',
        handlingInstructions: 'keep flat',
      },
    },
    idempotencyKey: `courier_${passenger.uid}_${Date.now()}`,
  });
  check(
    'courier booking created',
    cCreate.status === 201 || cCreate.status === 200,
    JSON.stringify(cCreate.json),
  );
  const courierRideId = cCreate.json?.data?.rideId ?? cCreate.json?.data?.id;

  const cInv = await pollInvited(
    driver.idToken,
    courierRideId,
    INVITE_WAIT_MS,
    drvKeepAlive,
  );
  check('courier invite delivered', !!cInv);
  if (cInv) {
    check(
      'invite carries parcel summary (no contacts)',
      !!cInv.item?.parcel && !('senderPhone' in (cInv.item.parcel ?? {})),
      JSON.stringify(cInv.item?.parcel),
    );
    const cAccept = await api(
      `/v1/rides/${courierRideId}/invites/${cInv.item.waveId}/accept`,
      { method: 'POST', token: driver.idToken, body: {} },
    );
    check('courier accept → offer', cAccept.status === 200 || cAccept.status === 201, JSON.stringify(cAccept.json));
    const cOffers = await api(`/v1/rides/${courierRideId}/offers`, {
      token: passenger.idToken,
    });
    const cOfferId =
      cOffers.json?.data?.items?.[0]?.offerId ??
      cOffers.json?.data?.offers?.[0]?.offerId;
    const cSel = await api(
      `/v1/rides/${courierRideId}/offers/${cOfferId}/select`,
      {
        method: 'POST',
        token: passenger.idToken,
        body: {},
        idempotencyKey: `sel_${courierRideId}`,
      },
    );
    check('courier select → assigned', cSel.status === 200, JSON.stringify(cSel.json));

    const cRide = async () =>
      (await api(`/v1/rides/${courierRideId}`, { token: passenger.idToken }))
        .json?.data;
    const cData = await cRide();
    check(
      'passenger sees OTP codes',
      !!cData?.otpCodes?.pickup && !!cData?.otpCodes?.delivery,
      JSON.stringify(cData?.otpCodes),
    );

    for (const step of ['en-route', 'arrive'] as const) {
      const r = await api(`/v1/rides/${courierRideId}/${step}`, {
        method: 'POST',
        token: driver.idToken,
        body: {},
        idempotencyKey: `c_${step}_${courierRideId}`,
      });
      check(`courier POST /${step}`, r.status === 200, JSON.stringify(r.json));
    }

    // Wrong pickup code → rejected; real code → RIDE_STARTED.
    const badOtp = await api(`/v1/rides/${courierRideId}/start`, {
      method: 'POST',
      token: driver.idToken,
      body: { otp: '000000x' },
      idempotencyKey: `c_start_bad_${courierRideId}`,
    });
    check(
      'wrong pickup OTP rejected',
      badOtp.status === 400 ||
        badOtp.status === 403 ||
        badOtp.status === 409 ||
        badOtp.status === 422,
      JSON.stringify(badOtp.json),
    );
    const goodStart = await api(`/v1/rides/${courierRideId}/start`, {
      method: 'POST',
      token: driver.idToken,
      body: { otp: cData.otpCodes.pickup },
      idempotencyKey: `c_start_${courierRideId}`,
    });
    check('pickup OTP → RIDE_STARTED', goodStart.status === 200, JSON.stringify(goodStart.json));

    // Cancel after pickup must be refused — parcel cannot be abandoned.
    const cancelInTransit = await api(`/v1/rides/${courierRideId}/cancel`, {
      method: 'POST',
      token: passenger.idToken,
      body: { reason: 'test' },
      idempotencyKey: `c_cancel_${courierRideId}`,
    });
    check(
      'cancel after pickup refused',
      cancelInTransit.status === 409 || cancelInTransit.status === 400,
      JSON.stringify(cancelInTransit.json),
    );

    const goodComplete = await api(`/v1/rides/${courierRideId}/complete`, {
      method: 'POST',
      token: driver.idToken,
      body: { otp: cData.otpCodes.delivery },
      idempotencyKey: `c_complete_${courierRideId}`,
    });
    check(
      'delivery OTP → RIDE_COMPLETED',
      goodComplete.status === 200,
      JSON.stringify(goodComplete.json),
    );
    const cFinal = await cRide();
    check(
      'courier ride COMPLETED + codes consumed',
      cFinal?.state === 'RIDE_COMPLETED' &&
        cFinal?.otpCodes?.pickupUsedAt != null &&
        cFinal?.otpCodes?.deliveryUsedAt != null,
      JSON.stringify({ state: cFinal?.state, otp: cFinal?.otpCodes }),
    );
  }

  // ── Switch to Driver / Passenger leg ───────────────────────────────────
  console.log('== mode switch: onboard → approve → switch both ways ==');
  // Fresh user goes through the real endpoints (register → onboard →
  // ops-approve → /mode) — never a second account.
  const switcher = await api('/v1/auth/register', {
    method: 'POST',
    token: passenger2.idToken,
    body: {},
    idempotencyKey: `register_${passenger2.uid}`,
  });
  check('switcher register', switcher.status === 200, JSON.stringify(switcher.json));

  const earlySwitch = await api('/v1/auth/mode', {
    method: 'POST',
    token: passenger2.idToken,
    body: { mode: 'driver' },
    idempotencyKey: `mode_switch_${Date.now()}_a`,
  });
  check(
    'switch→driver blocked before onboarding',
    earlySwitch.status === 409 &&
      earlySwitch.json?.error?.code === 'DRIVER_ONBOARDING_REQUIRED',
    JSON.stringify(earlySwitch.json),
  );

  const onboard = await api('/v1/drivers/onboarding', {
    method: 'POST',
    token: passenger2.idToken,
    body: { vehicleType: 'car', vehicleModel: 'Corolla', plateNumber: 'LEA-1', homeCity: 'lahore' },
    idempotencyKey: `onboard_${passenger2.uid}_${Date.now()}`,
  });
  check(
    'driver onboarding → pending',
    onboard.status === 200 && onboard.json?.data?.driverStatus === 'pending',
    JSON.stringify(onboard.json),
  );

  const pendingSwitch = await api('/v1/auth/mode', {
    method: 'POST',
    token: passenger2.idToken,
    body: { mode: 'driver' },
    idempotencyKey: `mode_switch_${Date.now()}_b`,
  });
  check(
    'switch→driver blocked while pending',
    pendingSwitch.status === 409 &&
      pendingSwitch.json?.error?.code === 'DRIVER_APPROVAL_PENDING',
    JSON.stringify(pendingSwitch.json),
  );

  // Ops approval — write users doc directly (same as driver seeding above).
  await db.collection('users').doc(passenger2.uid).update({
    role: 'driver',
    driverStatus: 'approved',
  });

  const toDriver = await api('/v1/auth/mode', {
    method: 'POST',
    token: passenger2.idToken,
    body: { mode: 'driver' },
    idempotencyKey: `mode_switch_${Date.now()}_c`,
  });
  check(
    'switch→driver ok after approval',
    toDriver.status === 200 && toDriver.json?.activeMode === 'driver' &&
      toDriver.json?.role === 'driver',
    JSON.stringify(toDriver.json),
  );

  const goOnline = await api('/v1/drivers/go-online', {
    method: 'POST',
    token: passenger2.idToken,
    body: {},
  });
  check('switched driver can go online', goOnline.status === 200, JSON.stringify(goOnline.json));

  const toPassenger = await api('/v1/auth/mode', {
    method: 'POST',
    token: passenger2.idToken,
    body: { mode: 'passenger' },
    idempotencyKey: `mode_switch_${Date.now()}_d`,
  });
  check(
    'switch→passenger ok',
    toPassenger.status === 200 && toPassenger.json?.activeMode === 'passenger' &&
      toPassenger.json?.role === 'driver',
    JSON.stringify(toPassenger.json),
  );
  const drvDoc = await db.collection('drivers').doc(passenger2.uid).get();
  check(
    'driver durably offline after passenger switch (no ghost presence)',
    drvDoc.exists && drvDoc.data()?.availabilityState === 'offline',
    JSON.stringify(drvDoc.data()),
  );

  console.log(`\n==== RESULT: ${passed} passed, ${failed} failed ====`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('E2E crashed:', e);
  process.exit(1);
});
