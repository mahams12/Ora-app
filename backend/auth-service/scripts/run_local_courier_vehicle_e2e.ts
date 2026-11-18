/**
 * Zero-cost local E2E — courierVehicle (bike/car/rickshaw) matching.
 * Verifies dispatch invites ONLY same-class drivers, mismatched offers are
 * rejected, and a matched offer → select → assignment still works.
 *
 * Prereqs:
 *   1. firebase emulators running (auth:9099, firestore:8181, database:9000)
 *   2. ./scripts/run_local_device_backend.sh  (auth-service on :8080)
 *
 * Run:  ./node_modules/.bin/tsx scripts/run_local_courier_vehicle_e2e.ts
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
process.env.FIREBASE_DATABASE_URL ??=
  'https://oraapp-a9be5-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';

const API = process.env.ORA_API ?? 'http://127.0.0.1:8080';
const AUTH_EMU =
  process.env.ORA_AUTH_BASE ??
  `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com`;
const AUTH_KEY = process.env.ORA_AUTH_KEY ?? 'emulator';

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
    idempotencyKey?: string;
  } = {},
): Promise<{ status: number; json: any }> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
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
    const res = await fetch(`${AUTH_EMU}/v1/${endpoint}?key=${AUTH_KEY}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email,
        password: 'localdev-pass-1',
        returnSecureToken: true,
      }),
    });
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
const LHE = { lat: 31.5204, lng: 74.3587 };
const RUN = Date.now();

function mkParcel() {
  return {
    senderName: 'Ali Sender',
    senderPhone: '+923001111111',
    receiverName: 'Bilal Receiver',
    receiverPhone: '+923009999999',
    parcelCategory: 'documents',
    size: 'SMALL',
    weightKg: 1.5,
    quantity: 1,
    description: 'Office papers',
  };
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const db = getFirestore();

  console.log('== setup: pax + bike driver + car driver ==');
  const pax = await signUp(`cv_pax_${RUN}@local.dev`);
  const bike = await signUp(`cv_bike_${RUN}@local.dev`);
  const car = await signUp(`cv_car_${RUN}@local.dev`);
  const reg = await api('/v1/auth/register', {
    method: 'POST',
    token: pax.idToken,
    body: {},
    idempotencyKey: `register_${pax.uid}`,
  });
  check('passenger registered', reg.status === 200 || reg.status === 201,
    JSON.stringify(reg.json));
  for (const [uid, vehicle] of [
    [bike.uid, { type: 'bike', model: 'Seed 70cc', plate: 'LBB-11' }],
    [car.uid, { type: 'car', model: 'Seed Sedan', plate: 'LCA-22' }],
  ] as const) {
    await db.collection('users').doc(uid).set({
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    await db.collection('drivers').doc(uid).set({ uid, vehicle });
  }
  await db
    .collection('pricingRules')
    .doc('lahore_courier')
    .set(
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'courier',
        version: 'cv-e2e-1',
        baseFare: 150,
        ratePerKm: 70,
        ratePerMin: 5,
        minFare: 150,
        maxFare: 8000,
        perStopFeeMinor: 5000,
      }),
    );

  for (const d of [bike, car]) {
    const go = await api('/v1/drivers/go-online', {
      method: 'POST',
      token: d.idToken,
      body: {},
    });
    check(`driver online (${d.uid.slice(0, 6)})`, go.status === 200,
      JSON.stringify(go.json));
  }

  let seq = 1;
  const locFor = (token: string, uid: string) =>
    api('/v1/location/update', {
      method: 'POST',
      token,
      body: {
        locationSeq: seq++,
        locationStreamId: `cv-${uid}-${RUN}`,
        lat: LHE.lat,
        lng: LHE.lng,
        accuracy: 10,
        heading: 0,
        speed: 0,
        provider: 'gps',
        timestamp: Date.now(),
      },
    });
  await locFor(bike.idToken, bike.uid);
  await locFor(car.idToken, car.uid);

  async function estimate(token: string, drop: { lat: number; lng: number }) {
    const r = await api('/v1/pricing/estimate', {
      method: 'POST',
      token,
      body: {
        pickup: LHE,
        destination: drop,
        city: 'lahore',
        category: 'courier',
        serviceType: 'courier',
        stops: [LHE, drop],
      },
    });
    check('pricing estimate 200', r.status === 200, JSON.stringify(r.json));
    return r.json?.data as {
      pricingSnapshotId: string;
      recommendedFareMinor: number;
    };
  }

  async function createCourier(
    token: string,
    tag: string,
    drop: { lat: number; lng: number },
    vehicle?: string,
  ) {
    const est = await estimate(token, drop);
    const r = await api('/v1/rides', {
      method: 'POST',
      token,
      body: {
        pickup: { ...LHE, address: 'Pickup' },
        destination: { ...drop, address: 'Drop' },
        city: 'Lahore',
        category: 'courier',
        serviceType: 'courier',
        paymentMethod: 'CASH',
        passengerCount: 1,
        pricingSnapshotId: est?.pricingSnapshotId,
        passengerOfferMinor: est?.recommendedFareMinor,
        parcel: mkParcel(),
        ...(vehicle ? { courierVehicle: vehicle } : {}),
        stops: [
          { type: 'PICKUP', location: LHE },
          { type: 'DROPOFF', location: drop },
        ],
      },
      idempotencyKey: `cv_${tag}_${RUN}`,
    });
    return r;
  }

  async function pollFor(
    token: string,
    uid: string,
    rideId: string,
    waitMs: number,
  ) {
    const deadline = Date.now() + waitMs;
    while (Date.now() < deadline) {
      const r = await api('/v1/rides/invited', { token });
      const item = (r.json?.data?.items ?? []).find(
        (i: any) => i.rideId === rideId,
      );
      if (item) return item;
      await locFor(token, uid);
      await sleep(800);
    }
    return null;
  }

  console.log('== case 1: courierVehicle=car — only car driver invited ==');
  const c1 = await createCourier(
    pax.idToken,
    'car_ride',
    { lat: LHE.lat + 0.05, lng: LHE.lng + 0.05 },
    'car',
  );
  check('car request created', c1.status === 201, JSON.stringify(c1.json));
  const ride1 = c1.json?.data?.rideId as string;
  check(
    'create response carries courierVehicle',
    c1.json?.data?.courierVehicle === 'car',
    JSON.stringify(c1.json?.data?.courierVehicle),
  );

  const [bikeInv1, carInv1] = await Promise.all([
    pollFor(bike.idToken, bike.uid, ride1, 12_000),
    pollFor(car.idToken, car.uid, ride1, 20_000),
  ]);
  check('car driver invited', !!carInv1, 'no invite within 20s');
  check('bike driver NOT invited', !bikeInv1, 'bike driver saw car-only job');
  check(
    'invite carries courierVehicle=car',
    carInv1?.courierVehicle === 'car',
    JSON.stringify(carInv1?.courierVehicle),
  );

  // Mismatched driver attempts a direct counter-offer anyway → hard 422.
  await sleep(600);
  const badOffer = await api(`/v1/rides/${ride1}/offers`, {
    method: 'POST',
    token: bike.idToken,
    body: {
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 32000,
      expectedRequestVersion: 1,
    },
    idempotencyKey: `cv_bad_offer_${RUN}`,
  });
  check(
    'bike driver cannot offer on car request',
    badOffer.status === 422 &&
      badOffer.json?.error?.code === 'DRIVER_VEHICLE_MISMATCH',
    `${badOffer.status} ${JSON.stringify(badOffer.json)}`,
  );

  // Matched driver accepts invite (creates offer) → passenger selects.
  await sleep(600);
  const acc = await api(
    `/v1/rides/${ride1}/invites/${carInv1?.waveId}/accept`,
    {
      method: 'POST',
      token: car.idToken,
      body: {},
      idempotencyKey: `cv_car_acc_${RUN}`,
    },
  );
  check('car driver accepts invite → offer', acc.status === 200 || acc.status === 201,
    JSON.stringify(acc.json));
  const offers = await api(`/v1/rides/${ride1}/offers`, {
    token: pax.idToken,
  });
  const offerId =
    offers.json?.data?.items?.[0]?.offerId ??
    offers.json?.data?.offers?.[0]?.offerId;
  await sleep(600);
  const sel = await api(`/v1/rides/${ride1}/offers/${offerId}/select`, {
    method: 'POST',
    token: pax.idToken,
    body: {},
    idempotencyKey: `cv_car_sel_${RUN}`,
  });
  check('passenger selects car offer', sel.status === 200,
    JSON.stringify(sel.json));
  const rideSnap = await api(`/v1/rides/${ride1}`, { token: pax.idToken });
  check(
    'ride assigned to car driver',
    rideSnap.json?.data?.state === 'DRIVER_ASSIGNED' &&
      rideSnap.json?.data?.assignedDriverId === car.uid,
    JSON.stringify(rideSnap.json?.data),
  );
  check(
    'publicRide carries courierVehicle',
    rideSnap.json?.data?.courierVehicle === 'car',
    JSON.stringify(rideSnap.json?.data?.courierVehicle),
  );

  console.log('== case 2: courierVehicle=bike — only bike driver invited ==');
  const c2 = await createCourier(
    pax.idToken,
    'bike_ride',
    { lat: LHE.lat + 0.04, lng: LHE.lng + 0.04 },
    'bike',
  );
  check('bike request created', c2.status === 201, JSON.stringify(c2.json));
  const ride2 = c2.json?.data?.rideId as string;
  const [bikeInv2, carInv2] = await Promise.all([
    pollFor(bike.idToken, bike.uid, ride2, 20_000),
    pollFor(car.idToken, car.uid, ride2, 12_000),
  ]);
  check('bike driver invited', !!bikeInv2, 'no invite within 20s');
  check('car driver NOT invited', !carInv2, 'car driver saw bike-only job');

  await sleep(600);
  const badOffer2 = await api(`/v1/rides/${ride2}/offers`, {
    method: 'POST',
    token: car.idToken,
    body: {
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 32000,
      expectedRequestVersion: 1,
    },
    idempotencyKey: `cv_bad_offer2_${RUN}`,
  });
  check(
    'car driver cannot offer on bike request',
    badOffer2.status === 422 &&
      badOffer2.json?.error?.code === 'DRIVER_VEHICLE_MISMATCH',
    `${badOffer2.status} ${JSON.stringify(badOffer2.json)}`,
  );

  console.log('== case 3: no courierVehicle — any vehicle invited (legacy) ==');
  const c3 = await createCourier(
    pax.idToken,
    'any_ride',
    { lat: LHE.lat + 0.03, lng: LHE.lng + 0.03 },
    undefined,
  );
  check('legacy request created', c3.status === 201, JSON.stringify(c3.json));
  const ride3 = c3.json?.data?.rideId as string;
  const [bikeInv3, carInv3] = await Promise.all([
    pollFor(bike.idToken, bike.uid, ride3, 20_000),
    pollFor(car.idToken, car.uid, ride3, 20_000),
  ]);
  check('no-filter invite reaches a driver', !!bikeInv3 || !!carInv3);

  console.log(`\n== summary: ${passed} passed, ${failed} failed ==`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('E2E crashed', e);
  process.exit(1);
});
