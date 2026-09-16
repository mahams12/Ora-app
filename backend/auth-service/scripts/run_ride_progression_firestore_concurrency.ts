/**
 * LIVE Firestore emulator concurrency proof for Phase 2G ride progression.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction.
 *
 * Usage:
 *   npm run test:ride-progression-firestore-concurrency
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
  pricingSnapshotId: 'snap-prog-live-1',
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
  await db.collection('pricingSnapshots').doc('snap-prog-live-1').set({
    snapshotId: 'snap-prog-live-1',
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

async function seedAssigned(
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
  return {
    passengerId,
    driverId,
    rideId,
    version: select.body.data.version as number,
    agreedFareMinor: select.body.data.agreedFareMinor as number,
  };
}

async function progress(
  db: Firestore,
  driverId: string,
  rideId: string,
  path: string,
  idem: string,
  body: Record<string, unknown> = {},
) {
  return request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/${path}`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(body);
}

async function advanceTo(
  db: Firestore,
  driverId: string,
  rideId: string,
  steps: string[],
  tag: string,
): Promise<number> {
  let version = 0;
  for (const step of steps) {
    const res = await progress(db, driverId, rideId, step, `${tag}-${step}-${randomUUID()}`);
    assert(res.status === 200, `${step} ${res.status} ${JSON.stringify(res.body)}`);
    version = res.body.data.version as number;
  }
  return version;
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
    `LIVE Firestore progression concurrency — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);

  await test('happy path assign→complete live', async () => {
    const seeded = await seedAssigned(db, 'happy');
    await advanceTo(
      db,
      seeded.driverId,
      seeded.rideId,
      ['en-route', 'arrive', 'start', 'complete'],
      'happy',
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_COMPLETED', `state=${ride.state}`);
    assert(ride.agreedFareMinor === seeded.agreedFareMinor, 'fare immutable');
    assert(ride.assignedDriverId === seeded.driverId, 'assignee');
    assert(typeof ride.startedAt === 'string', 'startedAt');
    assert(typeof ride.completedAt === 'string', 'completedAt');
    assert((await countOutbox(db, seeded.rideId, 'ride.completed')) === 1, 'completed evt');
  });

  await test('en-route concurrency 2-way live', async () => {
    const before = { ...stats };
    const seeded = await seedAssigned(db, 'en2');
    const results = await Promise.all(
      [0, 1].map((i) =>
        progress(
          db,
          seeded.driverId,
          seeded.rideId,
          'en-route',
          `en2-${i}-${randomUUID()}`,
        ),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'DRIVER_EN_ROUTE', `state=${ride.state}`);
    assert(ride.version === seeded.version + 1, `version=${ride.version}`);
    assert(
      results.every((r) => r.status === 200 || r.status === 409),
      'resolved',
    );
    assert(
      (await countOutbox(db, seeded.rideId, 'ride.driver.en_route')) === 1,
      'one en_route event',
    );
    notes.push(
      `2-way en-route: version+1; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }`,
    );
  });

  await test('en-route concurrency 10-way live', async () => {
    const before = { ...stats };
    const seeded = await seedAssigned(db, 'en10');
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        progress(
          db,
          seeded.driverId,
          seeded.rideId,
          'en-route',
          `en10-${i}-${randomUUID()}`,
        ),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'DRIVER_EN_ROUTE', 'EN_ROUTE');
    assert(ride.version === seeded.version + 1, 'version +1');
    assert(
      (await countOutbox(db, seeded.rideId, 'ride.driver.en_route')) === 1,
      'one event',
    );
    notes.push(
      `10-way en-route: contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }`,
    );
  });

  await test('complete concurrency 50-way live', async () => {
    const before = { ...stats };
    const seeded = await seedAssigned(db, 'co50');
    const versionBefore = await advanceTo(
      db,
      seeded.driverId,
      seeded.rideId,
      ['en-route', 'arrive', 'start'],
      'co50-prep',
    );
    await Promise.all(
      Array.from({ length: 50 }, (_, i) =>
        progress(
          db,
          seeded.driverId,
          seeded.rideId,
          'complete',
          `co50-${i}-${randomUUID()}`,
        ),
      ),
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_COMPLETED', `state=${ride.state}`);
    assert(ride.version === versionBefore + 1, `version=${ride.version}`);
    assert(ride.agreedFareMinor === seeded.agreedFareMinor, 'fare');
    assert(
      (await countOutbox(db, seeded.rideId, 'ride.completed')) === 1,
      'one completed',
    );
    notes.push(
      `50-way complete: contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }`,
    );
  });

  await test('same idempotency key concurrent en-route live', async () => {
    const seeded = await seedAssigned(db, 'idem');
    const key = `same-${randomUUID()}`;
    const results = await Promise.all(
      [0, 1].map(() =>
        progress(db, seeded.driverId, seeded.rideId, 'en-route', key),
      ),
    );
    assert(results.every((r) => r.status === 200), 'both 200');
    assert(
      results[0]!.body.data.version === results[1]!.body.data.version,
      'same version',
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.version === seeded.version + 1, 'bumped once');
    assert(
      (await countOutbox(db, seeded.rideId, 'ride.driver.en_route')) === 1,
      'one event',
    );
  });

  await test('en-route vs cancel live', async () => {
    const seeded = await seedAssigned(db, 'race');
    const [prog, cancel] = await Promise.all([
      progress(
        db,
        seeded.driverId,
        seeded.rideId,
        'en-route',
        `race-en-${randomUUID()}`,
      ),
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-can-${randomUUID()}`)
        .send({ reason: 'race' }),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(
      ride.state === 'DRIVER_EN_ROUTE' || ride.state === 'CANCELLED',
      `state=${ride.state}`,
    );
    if (ride.state === 'CANCELLED') {
      assert(cancel.status === 200, 'cancel won');
      assert(prog.status === 200 || prog.status === 409, `prog=${prog.status}`);
      assert(ride.assignedDriverId === seeded.driverId, 'retain assignee');
      assert(
        (await countOutbox(db, seeded.rideId, 'ride.cancelled')) === 1,
        'cancel evt',
      );
    } else {
      assert(prog.status === 200, 'en-route won');
      assert(cancel.status === 409, `cancel=${cancel.status}`);
      assert(
        (await countOutbox(db, seeded.rideId, 'ride.driver.en_route')) === 1,
        'en_route evt',
      );
    }
  });

  await test('driver cancel after start live', async () => {
    const seeded = await seedAssigned(db, 'dcan');
    await advanceTo(
      db,
      seeded.driverId,
      seeded.rideId,
      ['en-route', 'arrive', 'start'],
      'dcan',
    );
    const cancel = await request(appFor(db, seeded.driverId))
      .post(`/v1/rides/${seeded.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `dcan-${randomUUID()}`)
      .send({});
    assert(cancel.status === 200, `cancel ${cancel.status}`);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'CANCELLED', 'CANCELLED');
    assert(ride.cancelledBy === 'driver', 'cancelledBy driver');
    assert(ride.assignedDriverId === seeded.driverId, 'retain');
  });

  await test('reject skip and completed cancel live', async () => {
    const seeded = await seedAssigned(db, 'neg');
    const skip = await progress(
      db,
      seeded.driverId,
      seeded.rideId,
      'complete',
      `skip-${randomUUID()}`,
    );
    assert(skip.status === 409, `skip ${skip.status}`);
    await advanceTo(
      db,
      seeded.driverId,
      seeded.rideId,
      ['en-route', 'arrive', 'start', 'complete'],
      'neg',
    );
    const cancel = await request(appFor(db, seeded.passengerId))
      .post(`/v1/rides/${seeded.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `neg-can-${randomUUID()}`)
      .send({});
    assert(cancel.status === 409, `cancel after complete ${cancel.status}`);
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
