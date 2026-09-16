/**
 * LIVE Firestore emulator proof for Phase 2L arrivedAt wait-clock.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Inspects persisted documents.
 *
 * Usage:
 *   npm run test:ride-arrived-at-firestore-concurrency
 */
import { randomUUID } from 'node:crypto';
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';

type Stats = {
  transactionStarts: number;
  transactionFnInvocations: number;
  contendedTransactions: number;
};

let passed = 0;
let failed = 0;
const notes: string[] = [];

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(err);
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function requireEmulator(): void {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      'FIRESTORE_EMULATOR_HOST is not set. Run via firebase emulators:exec.',
    );
  }
}

function isIso(s: unknown): boolean {
  return typeof s === 'string' && Number.isFinite(Date.parse(s));
}

function instrumentRunTransaction(db: Firestore): Stats {
  const stats: Stats = {
    transactionStarts: 0,
    transactionFnInvocations: 0,
    contendedTransactions: 0,
  };
  const original = db.runTransaction.bind(db);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (db as any).runTransaction = async (
    updateFunction: (tx: unknown) => Promise<unknown>,
    transactionOptions?: unknown,
  ) => {
    stats.transactionStarts += 1;
    let invocations = 0;
    const wrapped = async (tx: unknown) => {
      invocations += 1;
      stats.transactionFnInvocations += 1;
      if (invocations === 2) {
        stats.contendedTransactions += 1;
      }
      return updateFunction(tx);
    };
    if (transactionOptions === undefined) {
      return original(wrapped);
    }
    return original(wrapped, transactionOptions as never);
  };
  return stats;
}

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
  } as never;
}

function appFor(db: Firestore, uid: string) {
  return createApp({
    auth: authFor(uid),
    db,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 100_000 },
  });
}

const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'Pickup' },
  destination: { lat: 24.9, lng: 67.1, address: 'Destination' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-arrived-live-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

async function seedPassenger(db: Firestore, uid: string): Promise<void> {
  await db.collection('users').doc(uid).set({
    uid,
    phoneNumber: '+923001111111',
    displayName: 'P',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
  });
}

async function seedDriver(db: Firestore, uid: string): Promise<void> {
  await db.collection('users').doc(uid).set({
    uid,
    phoneNumber: '+923002222222',
    displayName: 'D',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
}

async function seedPricing(db: Firestore): Promise<void> {
  await db.collection('pricingSnapshots').doc('snap-arrived-live-1').set({
    snapshotId: 'snap-arrived-live-1',
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'live-fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    inputs: { distanceKm: 5.2, durationMin: 18 },
  });
}

async function seedToEnRoute(
  db: Firestore,
  tag: string,
): Promise<{
  passengerId: string;
  driverId: string;
  rideId: string;
  version: number;
}> {
  const passengerId = `p-${tag}-${randomUUID().slice(0, 8)}`;
  const driverId = `d-${tag}-${randomUUID().slice(0, 8)}`;
  await seedPassenger(db, passengerId);
  await seedDriver(db, driverId);
  await seedPricing(db);
  const create = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `c-${tag}-${randomUUID()}`)
    .send(createBody);
  assert(create.status === 201, `create ${create.status}`);
  const rideId = create.body.data.rideId as string;
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `o-${tag}-${randomUUID()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(offer.status === 201, `offer ${offer.status}`);
  const select = await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `s-${tag}-${randomUUID()}`)
    .send({});
  assert(select.status === 200, `select ${select.status}`);
  const en = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/en-route`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `er-${tag}-${randomUUID()}`)
    .send({});
  assert(en.status === 200, `en-route ${en.status}`);
  return {
    passengerId,
    driverId,
    rideId,
    version: en.body.data.version as number,
  };
}

async function countOutbox(
  db: Firestore,
  rideId: string,
  eventType: string,
): Promise<number> {
  const snap = await db.collection('outboxEvents').get();
  return snap.docs.filter(
    (d) =>
      d.data().aggregateId === rideId && d.data().eventType === eventType,
  ).length;
}

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore arrivedAt proof — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);

  await test('normal arrive persists arrivedAt live', async () => {
    const { driverId, rideId, version } = await seedToEnRoute(db, 'norm');
    const before = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(before.arrivedAt == null, 'pre null');
    const arrive = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `arr-${randomUUID()}`)
      .send({});
    assert(arrive.status === 200, `arrive ${arrive.status}`);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'DRIVER_ARRIVED', `state=${ride.state}`);
    assert(ride.version === version + 1, 'version +1');
    assert(isIso(ride.arrivedAt), 'iso');
    assert(arrive.body.data.arrivedAt === ride.arrivedAt, 'dto match');
    assert((await countOutbox(db, rideId, 'ride.driver.arrived')) === 1, 'evt');
  });

  await test('arrive concurrency 2-way live', async () => {
    const before = { ...stats };
    const { driverId, rideId, version } = await seedToEnRoute(db, 'c2');
    const results = await Promise.all([
      request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/arrive`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `c2a-${randomUUID()}`)
        .send({}),
      request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/arrive`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `c2b-${randomUUID()}`)
        .send({}),
    ]);
    assert(
      results.every((r) => r.status === 200),
      `statuses=${results.map((r) => r.status).join(',')}`,
    );
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'DRIVER_ARRIVED', 'ARRIVED');
    assert(ride.version === version + 1, 'version +1 once');
    assert(isIso(ride.arrivedAt), 'arrivedAt');
    assert(
      results[0]!.body.data.arrivedAt === results[1]!.body.data.arrivedAt,
      'same clock',
    );
    assert(results[0]!.body.data.arrivedAt === ride.arrivedAt, 'match store');
    assert((await countOutbox(db, rideId, 'ride.driver.arrived')) === 1, 'one evt');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('arrive concurrency 10-way live', async () => {
    const before = { ...stats };
    const { driverId, rideId, version } = await seedToEnRoute(db, 'c10');
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        request(appFor(db, driverId))
          .post(`/v1/rides/${rideId}/arrive`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `c10-${i}-${randomUUID()}`)
          .send({}),
      ),
    );
    assert(
      results.every((r) => r.status === 200),
      'all 200 (idempotent already-arrived)',
    );
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.version === version + 1, 'version +1');
    assert(isIso(ride.arrivedAt), 'arrivedAt');
    const clocks = new Set(results.map((r) => r.body.data.arrivedAt as string));
    assert(clocks.size === 1, `clocks=${clocks.size}`);
    assert((await countOutbox(db, rideId, 'ride.driver.arrived')) === 1, 'one evt');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('arrive vs cancel live', async () => {
    const { passengerId, driverId, rideId } = await seedToEnRoute(db, 'race');
    const [arriveRes, cancelRes] = await Promise.all([
      request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/arrive`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-a-${randomUUID()}`)
        .send({}),
      request(appFor(db, passengerId))
        .post(`/v1/rides/${rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-c-${randomUUID()}`)
        .send({}),
    ]);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    // Legal outcomes (cancel remains allowed post-ARRIVED):
    // 1) ARRIVED exclusive: DRIVER_ARRIVED + arrivedAt
    // 2) Cancel beat arrive from EN_ROUTE: CANCELLED + arrivedAt null
    // 3) Arrive then cancel: CANCELLED + arrivedAt preserved (immutability)
    // Invalid: ARRIVED without clock; other states; clearing arrivedAt on cancel.
    if (ride.state === 'DRIVER_ARRIVED') {
      assert(isIso(ride.arrivedAt), 'arrivedAt set');
      assert(arriveRes.status === 200, 'arrive won');
      notes.push('arrive-vs-cancel: ARRIVED exclusive');
    } else if (ride.state === 'CANCELLED' && ride.arrivedAt == null) {
      assert(cancelRes.status === 200, 'cancel won');
      assert(
        arriveRes.status === 409 || arriveRes.status === 200,
        `arrive=${arriveRes.status}`,
      );
      notes.push('arrive-vs-cancel: CANCEL from EN_ROUTE (no clock)');
    } else if (ride.state === 'CANCELLED' && isIso(ride.arrivedAt)) {
      assert(arriveRes.status === 200, 'arrive committed');
      assert(cancelRes.status === 200, 'cancel after arrive');
      assert(
        (await countOutbox(db, rideId, 'ride.driver.arrived')) === 1,
        'arrived evt once',
      );
      notes.push('arrive-vs-cancel: ARRIVED then CANCEL (clock preserved)');
    } else {
      throw new Error(
        `invalid race outcome state=${ride.state} arrivedAt=${String(ride.arrivedAt)}`,
      );
    }
  });

  await test('idempotency replay live', async () => {
    const { driverId, rideId, version } = await seedToEnRoute(db, 'idem');
    const key = `idem-${randomUUID()}`;
    const first = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(first.status === 200, 'first');
    const t1 = first.body.data.arrivedAt as string;
    const second = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(second.status === 200, 'replay');
    assert(second.body.data.arrivedAt === t1, 'same dto');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.arrivedAt === t1, 'store');
    assert(ride.version === version + 1, 'version');
    assert((await countOutbox(db, rideId, 'ride.driver.arrived')) === 1, 'one evt');
  });

  await test('lifecycle preserves arrivedAt live', async () => {
    const { passengerId, driverId, rideId } = await seedToEnRoute(db, 'life');
    const arrive = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `life-a-${randomUUID()}`)
      .send({});
    assert(arrive.status === 200, 'arrive');
    const t1 = arrive.body.data.arrivedAt as string;
    for (const step of ['start', 'complete'] as const) {
      const res = await request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/${step}`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `life-${step}-${randomUUID()}`)
        .send({});
      assert(res.status === 200, step);
      const ride = (await db.collection('rides').doc(rideId).get()).data()!;
      assert(ride.arrivedAt === t1, `${step} store`);
    }
    const close = await request(appFor(db, passengerId))
      .post(`/v1/rides/${rideId}/close`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `life-close-${randomUUID()}`)
      .send({});
    assert(close.status === 200, 'close');
    const closed = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(closed.state === 'RIDE_CLOSED', 'CLOSED');
    assert(closed.arrivedAt === t1, 'preserved');
  });

  console.log('\n--- contention notes ---');
  for (const n of notes) console.log(n);
  console.log(`\nPhase 2L live proof: ${passed} passed, ${failed} failed`);

  const apps = getApps();
  if (apps[0]) await deleteApp(apps[0]);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
