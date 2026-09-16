/**
 * LIVE Firestore emulator concurrency proof for Phase 2J ride expiry sweeper.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction.
 *
 * Usage:
 *   npm run test:ride-expire-firestore-concurrency
 */
import { randomUUID } from 'node:crypto';
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';
import { RideService } from '../src/rides/ride_service';

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

const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'Pickup' },
  destination: { lat: 24.9, lng: 67.1, address: 'Destination' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-expire-live-1',
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
  await db.collection('pricingSnapshots').doc('snap-expire-live-1').set({
    snapshotId: 'snap-expire-live-1',
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

async function createRideLive(
  db: Firestore,
  passengerId: string,
  tag: string,
): Promise<{ rideId: string; version: number }> {
  const create = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `create-${tag}-${randomUUID()}`)
    .send(createBody);
  assert(create.status === 201, `create ${create.status}`);
  return {
    rideId: create.body.data.rideId as string,
    version: create.body.data.version as number,
  };
}

async function backdateExpiry(db: Firestore, rideId: string): Promise<void> {
  await db.collection('rides').doc(rideId).update({
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
}

async function expireSweep(db: Firestore, limit?: number) {
  const req = request(workerApp(db))
    .post('/v1/internal/rides/expire-sweep')
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

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore expire concurrency — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);
  const rides = new RideService(db);

  await test('sweeper query index SEARCHING due ride live', async () => {
    const passengerId = `p-q-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'q');
    await backdateExpiry(db, rideId);
    const sweep = await expireSweep(db);
    assert(sweep.status === 200, `sweep ${sweep.status}`);
    assert(sweep.body.data.expired === 1, 'expired count');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'EXPIRED', `state=${ride.state}`);
    assert(ride.version === version + 1, 'version +1');
    assert(typeof ride.updatedAt === 'string', 'updatedAt');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 1, 'one evt');
  });

  await test('OFFERS_AVAILABLE expiry live', async () => {
    const passengerId = `p-oa-${randomUUID().slice(0, 8)}`;
    const driverId = `d-oa-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'oa');
    const offer = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `offer-oa-${randomUUID()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    assert(offer.status === 201, `offer ${offer.status}`);
    const versionBeforeExpire = (
      await db.collection('rides').doc(rideId).get()
    ).data()!.version as number;
    await backdateExpiry(db, rideId);
    const sweep = await expireSweep(db);
    assert(sweep.status === 200, 'sweep');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'EXPIRED', 'EXPIRED');
    assert(ride.version === versionBeforeExpire + 1, 'version');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 1, 'evt');
    void version;
  });

  await test('non-expired ride unchanged live', async () => {
    const passengerId = `p-fut-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'fut');
    const sweep = await expireSweep(db);
    assert(sweep.status === 200, 'sweep');
    assert(sweep.body.data.expired === 0, 'none expired');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'SEARCHING', 'unchanged');
    assert(ride.version === version, 'version');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 0, 'no evt');
  });

  await test('expire concurrency 2-way live', async () => {
    const before = { ...stats };
    const passengerId = `p-c2-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'c2');
    await backdateExpiry(db, rideId);
    await Promise.all([
      rides.expireRide({ rideId, correlationId: `c2-a-${randomUUID()}` }),
      rides.expireRide({ rideId, correlationId: `c2-b-${randomUUID()}` }),
    ]);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'EXPIRED', 'EXPIRED');
    assert(ride.version === version + 1, 'version +1');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 1, 'one evt');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('expire concurrency 10-way live', async () => {
    const before = { ...stats };
    const passengerId = `p-c10-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'c10');
    await backdateExpiry(db, rideId);
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        rides.expireRide({
          rideId,
          correlationId: `c10-${i}-${randomUUID()}`,
        }),
      ),
    );
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'EXPIRED', 'EXPIRED');
    assert(ride.version === version + 1, 'version');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 1, 'one');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('expire vs select live', async () => {
    const passengerId = `p-race-s-${randomUUID().slice(0, 8)}`;
    const driverId = `d-race-s-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'race-s');
    const offer = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `race-s-off-${randomUUID()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    assert(offer.status === 201, 'offer');
    await backdateExpiry(db, rideId);
    const [selectRes] = await Promise.all([
      request(appFor(db, passengerId))
        .post(
          `/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`,
        )
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-s-sel-${randomUUID()}`)
        .send({}),
      rides.expireRide({ rideId, correlationId: `race-s-exp-${randomUUID()}` }),
    ]);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    if (ride.state === 'DRIVER_ASSIGNED') {
      assert(selectRes.status === 200, 'select won');
    } else {
      assert(ride.state === 'EXPIRED', 'expire won');
      assert(selectRes.status === 409, 'select conflict');
    }
    assert((await countOutbox(db, rideId, 'ride.expired')) <= 1, 'at most one evt');
  });

  await test('expire vs cancel live', async () => {
    const passengerId = `p-race-c-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'race-c');
    await backdateExpiry(db, rideId);
    const [cancelRes] = await Promise.all([
      request(appFor(db, passengerId))
        .post(`/v1/rides/${rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `race-c-${randomUUID()}`)
        .send({}),
      rides.expireRide({ rideId, correlationId: `race-c-exp-${randomUUID()}` }),
    ]);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(['CANCELLED', 'EXPIRED'].includes(ride.state as string), 'terminal');
    if (ride.state === 'CANCELLED') {
      assert(cancelRes.status === 200, 'cancel won');
    }
    assert((await countOutbox(db, rideId, 'ride.expired')) <= 1, 'evt cap');
  });

  await test('offer create after expire rejected live', async () => {
    const passengerId = `p-post-${randomUUID().slice(0, 8)}`;
    const driverId = `d-post-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'post');
    await backdateExpiry(db, rideId);
    const sweep = await expireSweep(db);
    assert(sweep.status === 200, 'sweep');
    const offer = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `post-off-${randomUUID()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 2,
      });
    assert(offer.status === 409, `offer ${offer.status}`);
    assert(offer.body.error.code === 'STATE_CONFLICT', 'code');
  });

  await test('retry after successful expire live', async () => {
    const passengerId = `p-retry-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'retry');
    await backdateExpiry(db, rideId);
    const first = await rides.expireRide({
      rideId,
      correlationId: `retry-1-${randomUUID()}`,
    });
    assert(first.outcome === 'expired', 'first');
    const second = await rides.expireRide({
      rideId,
      correlationId: `retry-2-${randomUUID()}`,
    });
    assert(second.outcome === 'already_expired', 'second');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.version === version + 1, 'single bump');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 1, 'one evt');
  });

  await test('assigned ride not overwritten live', async () => {
    const passengerId = `p-asg-${randomUUID().slice(0, 8)}`;
    const driverId = `d-asg-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId, version } = await createRideLive(db, passengerId, 'asg');
    const offer = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `asg-off-${randomUUID()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    await request(appFor(db, passengerId))
      .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `asg-sel-${randomUUID()}`)
      .send({});
    const versionAfterSelect = (
      await db.collection('rides').doc(rideId).get()
    ).data()!.version as number;
    await backdateExpiry(db, rideId);
    const sweep = await expireSweep(db);
    assert(sweep.status === 200, 'sweep');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.state === 'DRIVER_ASSIGNED', 'assigned');
    assert(ride.version === versionAfterSelect, 'select bump only');
    assert((await countOutbox(db, rideId, 'ride.expired')) === 0, 'no evt');
    void version;
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
