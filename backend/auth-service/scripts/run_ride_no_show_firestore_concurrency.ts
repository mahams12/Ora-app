/**
 * LIVE Firestore emulator proof for Phase 2M NO_SHOW sweeper.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Inspects persisted documents.
 *
 * Usage:
 *   npm run test:ride-no-show-firestore-concurrency
 */
import { randomUUID } from 'node:crypto';
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';
import { RideService } from '../src/rides/ride_service';
import { RIDE_NO_SHOW_WAIT_MS } from '../src/rides/types';

const WORKER_TOKEN = 'live-worker-token-16chars-min';

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
    internalWorkerToken: WORKER_TOKEN,
  });
}

function workerApp(db: Firestore) {
  return createApp({
    auth: authFor('worker'),
    db,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 100_000 },
    internalWorkerToken: WORKER_TOKEN,
  });
}

const SNAP = 'snap-noshow-live-1';
const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'Pickup' },
  destination: { lat: 24.9, lng: 67.1, address: 'Destination' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: SNAP,
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
  await db.collection('pricingSnapshots').doc(SNAP).set({
    snapshotId: SNAP,
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

async function seedToArrived(
  db: Firestore,
  tag: string,
): Promise<{
  passengerId: string;
  driverId: string;
  rideId: string;
  version: number;
  arrivedAt: string;
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
  await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `s-${tag}-${randomUUID()}`)
    .send({});
  for (const step of ['en-route', 'arrive'] as const) {
    const res = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${step}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${step}-${tag}-${randomUUID()}`)
      .send({});
    assert(res.status === 200, `${step} ${res.status}`);
  }
  const ride = (await db.collection('rides').doc(rideId).get()).data()!;
  assert(ride.state === 'DRIVER_ARRIVED', 'ARRIVED');
  assert(typeof ride.arrivedAt === 'string', 'arrivedAt');
  return {
    passengerId,
    driverId,
    rideId,
    version: ride.version as number,
    arrivedAt: ride.arrivedAt as string,
  };
}

async function setArrivedAt(
  db: Firestore,
  rideId: string,
  arrivedAt: string | null,
): Promise<void> {
  await db.collection('rides').doc(rideId).update({ arrivedAt });
}

async function sweep(db: Firestore, limit?: number) {
  const req = request(workerApp(db))
    .post('/v1/internal/rides/no-show-sweep')
    .set('X-Ora-Worker-Token', WORKER_TOKEN);
  if (limit != null) req.query({ limit: String(limit) });
  return req;
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

async function noShowPayload(
  db: Firestore,
  rideId: string,
): Promise<Record<string, unknown> | null> {
  const snap = await db.collection('outboxEvents').get();
  const doc = snap.docs.find(
    (d) =>
      d.data().aggregateId === rideId && d.data().eventType === 'ride.no_show',
  );
  return doc ? (doc.data().payload as Record<string, unknown>) : null;
}

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore NO_SHOW proof — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  for (const app of getApps()) {
    await deleteApp(app);
  }
  const app = initializeApp({ projectId: 'ora-app-d8112' });
  const db = getFirestore(app);
  const stats = instrumentRunTransaction(db);

  await test('normal NO_SHOW live', async () => {
    const seeded = await seedToArrived(db, 'norm');
    const clock = new Date(
      Date.now() - RIDE_NO_SHOW_WAIT_MS - 60_000,
    ).toISOString();
    await setArrivedAt(db, seeded.rideId, clock);
    const before = stats.contendedTransactions;
    const res = await sweep(db);
    assert(res.status === 200, `sweep ${res.status}`);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'NO_SHOW', 'state');
    assert(ride.version === seeded.version + 1, 'version');
    assert(ride.arrivedAt === clock, 'arrivedAt');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'evt');
    const payload = await noShowPayload(db, seeded.rideId);
    assert(payload != null, 'payload');
    assert(payload!.rideId === seeded.rideId, 'p.rideId');
    assert(payload!.fromState === 'DRIVER_ARRIVED', 'p.from');
    assert(payload!.toState === 'NO_SHOW', 'p.to');
    assert(payload!.reason === 'arrived_wait_ttl_elapsed', 'p.reason');
    assert(payload!.arrivedAt === clock, 'p.arrivedAt');
    notes.push(`normal: contended+=${stats.contendedTransactions - before}`);
  });

  await test('exact 5m boundary live', async () => {
    const seeded = await seedToArrived(db, 'bound');
    const clock = new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS).toISOString();
    await setArrivedAt(db, seeded.rideId, clock);
    await sweep(db);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'NO_SHOW', 'eligible at boundary');
  });

  await test('not due remains ARRIVED live', async () => {
    const seeded = await seedToArrived(db, 'notdue');
    const clock = new Date(
      Date.now() - RIDE_NO_SHOW_WAIT_MS + 60_000,
    ).toISOString();
    await setArrivedAt(db, seeded.rideId, clock);
    await sweep(db);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'DRIVER_ARRIVED', 'still ARRIVED');
    assert(ride.arrivedAt === clock, 'clock');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 0, 'no evt');
  });

  await test('legacy null arrivedAt skipped live', async () => {
    const seeded = await seedToArrived(db, 'legacy');
    await setArrivedAt(db, seeded.rideId, null);
    await sweep(db);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'DRIVER_ARRIVED', 'state');
    assert(ride.arrivedAt == null, 'null');
    assert(ride.version === seeded.version, 'version');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 0, 'no evt');
  });

  await test('NO_SHOW concurrency 2-way live', async () => {
    const seeded = await seedToArrived(db, 'c2');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    const before = stats.contendedTransactions;
    const svc = new RideService(db);
    const [a, b] = await Promise.all([
      svc.markNoShow({ rideId: seeded.rideId, correlationId: 'c2a' }),
      svc.markNoShow({ rideId: seeded.rideId, correlationId: 'c2b' }),
    ]);
    const outcomes = [a.outcome, b.outcome].sort();
    assert(
      outcomes.includes('no_show') &&
        (outcomes.includes('already_no_show') || outcomes.includes('no_show')),
      `outcomes=${outcomes.join(',')}`,
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'NO_SHOW', 'state');
    assert(ride.version === seeded.version + 1, 'version +1');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'one evt');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before}`,
    );
  });

  await test('NO_SHOW concurrency 10-way live', async () => {
    const seeded = await seedToArrived(db, 'c10');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    const before = stats.contendedTransactions;
    const svc = new RideService(db);
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        svc.markNoShow({
          rideId: seeded.rideId,
          correlationId: `c10-${i}`,
        }),
      ),
    );
    assert(
      results.filter((r) => r.outcome === 'no_show').length === 1,
      'one winner',
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.version === seeded.version + 1, 'version');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'one evt');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before}`,
    );
  });

  await test('NO_SHOW vs cancel live', async () => {
    const seeded = await seedToArrived(db, 'race-c');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    const svc = new RideService(db);
    const [ns, cancel] = await Promise.all([
      svc.markNoShow({ rideId: seeded.rideId, correlationId: 'race-ns' }),
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-c-${randomUUID()}`)
        .send({}),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    if (ride.state === 'NO_SHOW') {
      assert(ns.outcome === 'no_show' || ns.outcome === 'already_no_show', 'ns');
      assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'ns evt');
      assert(
        (await countOutbox(db, seeded.rideId, 'ride.cancelled')) === 0,
        'no cancel evt',
      );
      notes.push('NO_SHOW vs cancel: NO_SHOW won');
    } else if (ride.state === 'CANCELLED') {
      assert(cancel.status === 200, 'cancel won');
      assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 0, 'no ns');
      assert(
        (await countOutbox(db, seeded.rideId, 'ride.cancelled')) === 1,
        'cancel evt',
      );
      notes.push('NO_SHOW vs cancel: CANCEL won');
    } else {
      throw new Error(`invalid ${ride.state}`);
    }
  });

  await test('NO_SHOW vs start live', async () => {
    const seeded = await seedToArrived(db, 'race-s');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    const svc = new RideService(db);
    const [ns, start] = await Promise.all([
      svc.markNoShow({ rideId: seeded.rideId, correlationId: 'race-start-ns' }),
      request(appFor(db, seeded.driverId))
        .post(`/v1/rides/${seeded.rideId}/start`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-st-${randomUUID()}`)
        .send({}),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    if (ride.state === 'NO_SHOW') {
      assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'ns');
      assert(start.status === 409 || start.status === 200, `start=${start.status}`);
      notes.push('NO_SHOW vs start: NO_SHOW won');
    } else if (ride.state === 'RIDE_STARTED') {
      assert(start.status === 200, 'start won');
      assert(ride.startedAt != null, 'startedAt');
      assert(
        ns.outcome === 'skipped' || ns.outcome === 'already_no_show',
        `ns=${ns.outcome}`,
      );
      assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 0, 'no ns');
      notes.push('NO_SHOW vs start: START won');
    } else {
      throw new Error(`invalid ${ride.state}`);
    }
  });

  await test('duplicate worker retry live', async () => {
    const seeded = await seedToArrived(db, 'retry');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    await sweep(db);
    const afterFirst = (
      await db.collection('rides').doc(seeded.rideId).get()
    ).data()!;
    assert(afterFirst.state === 'NO_SHOW', 'first');
    const v = afterFirst.version as number;
    await sweep(db);
    const afterSecond = (
      await db.collection('rides').doc(seeded.rideId).get()
    ).data()!;
    assert(afterSecond.version === v, 'no second bump');
    assert(afterSecond.arrivedAt === afterFirst.arrivedAt, 'clock');
    assert(await countOutbox(db, seeded.rideId, 'ride.no_show') === 1, 'one evt');
  });

  await test('history NO_SHOW under all only live', async () => {
    const seeded = await seedToArrived(db, 'hist');
    await setArrivedAt(
      db,
      seeded.rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    await sweep(db);
    const all = await request(appFor(db, seeded.passengerId))
      .get('/v1/rides?status=all')
      .set('Authorization', 'Bearer t');
    assert(all.status === 200, 'all');
    assert(
      (all.body.data.rides as Array<{ rideId: string; state: string }>).some(
        (r) => r.rideId === seeded.rideId && r.state === 'NO_SHOW',
      ),
      'in all',
    );
    for (const status of ['completed', 'cancelled'] as const) {
      const res = await request(appFor(db, seeded.passengerId))
        .get(`/v1/rides?status=${status}`)
        .set('Authorization', 'Bearer t');
      assert(
        !(res.body.data.rides as Array<{ rideId: string }>).some(
          (r) => r.rideId === seeded.rideId,
        ),
        `not in ${status}`,
      );
    }
  });

  console.log('\n--- contention notes ---');
  for (const n of notes) console.log(n);
  console.log(`\nPhase 2M live proof: ${passed} passed, ${failed} failed`);
  await deleteApp(app);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
