/**
 * LIVE Firestore emulator concurrency proof for Phase 2H ride close.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction.
 *
 * Usage:
 *   npm run test:ride-close-firestore-concurrency
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
  pricingSnapshotId: 'snap-close-live-1',
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
  await db.collection('pricingSnapshots').doc('snap-close-live-1').set({
    snapshotId: 'snap-close-live-1',
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

async function seedCompleted(
  db: Firestore,
  tag: string,
): Promise<{
  passengerId: string;
  driverId: string;
  rideId: string;
  version: number;
  agreedFareMinor: number;
}> {
  const passengerId = `p-${tag}-${randomUUID().slice(0, 8)}`;
  const driverId = `d-${tag}-${randomUUID().slice(0, 8)}`;
  await seedPassenger(db, passengerId);
  await seedDriver(db, driverId);
  await seedPricing(db);
  const create = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `create-${tag}-${randomUUID()}`)
    .send(createBody);
  assert(create.status === 201, `create ${create.status}`);
  const rideId = create.body.data.rideId as string;
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `offer-${tag}-${randomUUID()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(offer.status === 201, `offer ${offer.status}`);
  const select = await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `select-${tag}-${randomUUID()}`)
    .send({});
  assert(select.status === 200, `select ${select.status}`);
  for (const step of ['en-route', 'arrive', 'start', 'complete']) {
    const res = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${step}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${tag}-${step}-${randomUUID()}`)
      .send({});
    assert(res.status === 200, `${step} ${res.status}`);
  }
  const ride = (await db.collection('rides').doc(rideId).get()).data()!;
  assert(ride.state === 'RIDE_COMPLETED', `state=${ride.state}`);
  assert(ride.closedAt == null, 'closedAt null before close');
  return {
    passengerId,
    driverId,
    rideId,
    version: ride.version as number,
    agreedFareMinor: ride.agreedFareMinor as number,
  };
}

async function close(
  db: Firestore,
  uid: string,
  rideId: string,
  idem: string,
  body: Record<string, unknown> = {},
) {
  return request(appFor(db, uid))
    .post(`/v1/rides/${rideId}/close`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(body);
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
    `LIVE Firestore close concurrency — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);

  await test('happy path passenger close live', async () => {
    const seeded = await seedCompleted(db, 'happy');
    const res = await close(
      db,
      seeded.passengerId,
      seeded.rideId,
      `happy-${randomUUID()}`,
    );
    assert(res.status === 200, `status=${res.status}`);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_CLOSED', `state=${ride.state}`);
    assert(typeof ride.closedAt === 'string', 'closedAt');
    assert(ride.version === seeded.version + 1, 'version');
    assert(ride.agreedFareMinor === seeded.agreedFareMinor, 'fare');
    assert(ride.assignedDriverId === seeded.driverId, 'assignee');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'evt');
  });

  await test('close concurrency 2-way live', async () => {
    const before = { ...stats };
    const seeded = await seedCompleted(db, 'c2');
    const results = await Promise.all(
      [0, 1].map((i) =>
        close(
          db,
          seeded.passengerId,
          seeded.rideId,
          `c2-${i}-${randomUUID()}`,
        ),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_CLOSED', 'CLOSED');
    assert(ride.version === seeded.version + 1, 'version +1');
    assert(results.every((r) => r.status === 200 || r.status === 409), 'ok');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'one evt');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('close concurrency 10-way live', async () => {
    const before = { ...stats };
    const seeded = await seedCompleted(db, 'c10');
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        close(db, seeded.driverId, seeded.rideId, `c10-${i}-${randomUUID()}`),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_CLOSED', 'CLOSED');
    assert(ride.version === seeded.version + 1, 'version');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'one');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('close concurrency 50-way mixed actors live', async () => {
    const before = { ...stats };
    const seeded = await seedCompleted(db, 'c50');
    await Promise.all(
      Array.from({ length: 50 }, (_, i) =>
        close(
          db,
          i % 2 === 0 ? seeded.passengerId : seeded.driverId,
          seeded.rideId,
          `c50-${i}-${randomUUID()}`,
        ),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_CLOSED', 'CLOSED');
    assert(ride.version === seeded.version + 1, `v=${ride.version}`);
    assert(ride.agreedFareMinor === seeded.agreedFareMinor, 'fare');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'one');
    notes.push(
      `50-way: contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }`,
    );
  });

  await test('same idempotency key concurrent close live', async () => {
    const seeded = await seedCompleted(db, 'idem');
    const key = `same-${randomUUID()}`;
    const results = await Promise.all(
      [0, 1].map(() => close(db, seeded.passengerId, seeded.rideId, key)),
    );
    assert(results.every((r) => r.status === 200), 'both 200');
    assert(
      results[0]!.body.data.version === results[1]!.body.data.version,
      'same version',
    );
    assert(
      results[0]!.body.data.closedAt === results[1]!.body.data.closedAt,
      'same closedAt',
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.version === seeded.version + 1, 'once');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'one');
  });

  await test('different keys after close no second mutation live', async () => {
    const seeded = await seedCompleted(db, 'diff');
    const first = await close(
      db,
      seeded.passengerId,
      seeded.rideId,
      `diff-a-${randomUUID()}`,
    );
    assert(first.status === 200, 'first');
    const second = await close(
      db,
      seeded.driverId,
      seeded.rideId,
      `diff-b-${randomUUID()}`,
    );
    assert(second.status === 200, 'second snapshot');
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.version === seeded.version + 1, 'no second bump');
    assert((await countOutbox(db, seeded.rideId, 'ride.closed')) === 1, 'one evt');
  });

  await test('reject close from STARTED live', async () => {
    const passengerId = `p-rej-${randomUUID().slice(0, 8)}`;
    const driverId = `d-rej-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const create = await request(appFor(db, passengerId))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `rej-c-${randomUUID()}`)
      .send(createBody);
    const rideId = create.body.data.rideId as string;
    const offer = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `rej-o-${randomUUID()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    await request(appFor(db, passengerId))
      .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `rej-s-${randomUUID()}`)
      .send({});
    for (const step of ['en-route', 'arrive', 'start']) {
      await request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/${step}`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `rej-${step}-${randomUUID()}`)
        .send({});
    }
    const res = await close(db, passengerId, rideId, `rej-close-${randomUUID()}`);
    assert(res.status === 409, `status=${res.status}`);
    assert(res.body.error.code === 'STATE_CONFLICT', 'code');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'RIDE_STARTED', 'unchanged');
    assert(ride.closedAt == null, 'no closedAt');
  });

  console.log('\n---');
  console.log(`passed=${passed} failed=${failed}`);
  console.log(
    `txnStarts=${stats.transactionStarts} fnInvocations=${stats.transactionFnInvocations} contendedTxns=${stats.contendedTransactions}`,
  );
  for (const n of notes) console.log(n);
  if (stats.contendedTransactions > 0) {
    console.log(
      'FIRESTORE_CONTENTION_OBSERVED=yes (updateFunction invoked >1 for some txns)',
    );
  } else {
    console.log(
      'FIRESTORE_CONTENTION_OBSERVED=no (no multi-attempt transactions counted)',
    );
  }

  const apps = getApps();
  await Promise.all(apps.map((a) => deleteApp(a)));
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
