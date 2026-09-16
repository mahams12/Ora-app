/**
 * LIVE Firestore emulator proof for Phase 2N ratings.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction.
 *
 * Usage:
 *   npm run test:ride-rating-firestore-concurrency
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

async function seedUsers(db: Firestore, passengerId: string, driverId: string) {
  await db.collection('users').doc(passengerId).set({
    uid: passengerId,
    phoneNumber: '+923001111111',
    displayName: 'Passenger',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
  });
  await db.collection('users').doc(driverId).set({
    uid: driverId,
    phoneNumber: '+923002222222',
    displayName: 'Driver',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  await db.collection('drivers').doc(driverId).set({
    driverId,
    userId: driverId,
    rating: 4.5,
    ratingCount: 10,
    noShowCount: 2,
  });
  await db.collection('pricingSnapshots').doc('snap-1').set({
    snapshotId: 'snap-1',
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    inputs: { distanceKm: 5.2, durationMin: 18 },
  });
}

async function seedToCompleted(
  db: Firestore,
  passengerId: string,
  driverId: string,
): Promise<{ rideId: string; version: number; updatedAt: string }> {
  await seedUsers(db, passengerId, driverId);
  const create = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `c-${randomUUID()}`)
    .send({
      pickup: { lat: 24.86, lng: 67.0, address: 'A' },
      destination: { lat: 24.9, lng: 67.1, address: 'B' },
      category: 'economy',
      serviceType: 'ride',
      passengerOfferMinor: 25000,
      pricingSnapshotId: 'snap-1',
      paymentMethod: 'CASH',
      passengerCount: 1,
    });
  assert(create.status === 201, `create ${create.status}`);
  const rideId = create.body.data.rideId as string;
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `o-${randomUUID()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(offer.status === 201, `offer ${offer.status}`);
  const select = await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `s-${randomUUID()}`)
    .send({});
  assert(select.status === 200, `select ${select.status}`);
  for (const step of ['en-route', 'arrive', 'start', 'complete'] as const) {
    const res = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${step}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${step}-${randomUUID()}`)
      .send({});
    assert(res.status === 200, `${step} ${res.status}`);
  }
  const snap = await db.collection('rides').doc(rideId).get();
  const ride = snap.data()!;
  assert(ride.state === 'RIDE_COMPLETED', 'COMPLETED');
  return {
    rideId,
    version: ride.version as number,
    updatedAt: ride.updatedAt as string,
  };
}

async function countOutbox(
  db: Firestore,
  ratingId: string,
): Promise<number> {
  const snap = await db.collection('outboxEvents').get();
  return snap.docs.filter(
    (d) =>
      d.data().eventType === 'ride.rating.submitted' &&
      d.data().aggregateId === ratingId,
  ).length;
}

async function outboxPayload(
  db: Firestore,
  ratingId: string,
): Promise<Record<string, unknown> | null> {
  const snap = await db.collection('outboxEvents').get();
  const doc = snap.docs.find(
    (d) =>
      d.data().eventType === 'ride.rating.submitted' &&
      d.data().aggregateId === ratingId,
  );
  return doc ? (doc.data().payload as Record<string, unknown>) : null;
}

async function main(): Promise<void> {
  requireEmulator();
  process.env.FIRESTORE_EMULATOR_HOST =
    process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8181';
  console.log(
    `LIVE Firestore ratings proof — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  for (const app of getApps()) {
    await deleteApp(app);
  }
  const app = initializeApp({ projectId: 'ora-app-d8112' });
  const db = getFirestore(app);
  const stats = instrumentRunTransaction(db);

  await test('normal passenger rating live', async () => {
    const p = `p-n-${randomUUID().slice(0, 8)}`;
    const d = `d-n-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const before = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    const res = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `rate-${randomUUID()}`)
      .send({ stars: 5 });
    assert(res.status === 201, `status ${res.status}`);
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    const rating = (await db.collection('ratings').doc(ratingId).get()).data();
    assert(rating != null, 'doc');
    assert(rating!.rideId === seeded.rideId, 'rideId');
    assert(rating!.raterId === p, 'rater');
    assert(rating!.ratedId === d, 'rated');
    assert(rating!.ratingType === 'passenger_rates_driver', 'type');
    assert(rating!.stars === 5, 'stars');
    assert(typeof rating!.createdAt === 'string', 'createdAt');
    assert(await countOutbox(db, ratingId) === 1, 'evt');
    const payload = await outboxPayload(db, ratingId);
    assert(payload != null, 'payload');
    assert(payload!.rideId === seeded.rideId, 'p.ride');
    assert(payload!.ratingId === ratingId, 'p.id');
    assert(payload!.ratingType === 'passenger_rates_driver', 'p.type');
    assert(payload!.raterId === p, 'p.rater');
    assert(payload!.ratedId === d, 'p.rated');
    assert(payload!.stars === 5, 'p.stars');
    assert(Object.keys(payload!).length === 6, 'exact keys');
    const after = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(after.state === before.state, 'state');
    assert(after.version === before.version, 'version');
    assert(after.updatedAt === before.updatedAt, 'updatedAt');
    assert(after.passengerRating == null, 'no denorm');
    const driver = (await db.collection('drivers').doc(d).get()).data()!;
    assert(driver.rating === 4.5 && driver.ratingCount === 10, 'aggregates');
    assert(driver.noShowCount === 2, 'noShow');
  });

  await test('normal driver rating + RIDE_CLOSED eligibility live', async () => {
    const p = `p-c-${randomUUID().slice(0, 8)}`;
    const d = `d-c-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const close = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/close`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `close-${randomUUID()}`)
      .send({});
    assert(close.status === 200, 'close');
    const res = await request(appFor(db, d))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `rate-${randomUUID()}`)
      .send({ stars: 4 });
    assert(res.status === 201, `status ${res.status}`);
    const ratingId = `${seeded.rideId}_driver_rates_passenger`;
    const rating = (await db.collection('ratings').doc(ratingId).get()).data();
    assert(rating?.ratingType === 'driver_rates_passenger', 'type');
    assert(rating?.stars === 4, 'stars');
  });

  await test('idempotency same-key / different-body / already-rated live', async () => {
    const p = `p-i-${randomUUID().slice(0, 8)}`;
    const d = `d-i-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const key = `idem-${randomUUID()}`;
    const first = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 5 });
    assert(first.status === 201, 'first');
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    const replay = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 5 });
    assert(replay.status === 201, 'replay');
    assert(await countOutbox(db, ratingId) === 1, 'one evt');
    const reused = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 1 });
    assert(reused.status === 409, 'reuse');
    assert(reused.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'reuse code');
    const dup = await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `idem2-${randomUUID()}`)
      .send({ stars: 5 });
    assert(dup.status === 409 && dup.body.error.code === 'ALREADY_RATED', 'already');
  });

  await test('NO_SHOW / CANCELLED / EXPIRED rejection live', async () => {
    for (const state of ['NO_SHOW', 'CANCELLED', 'EXPIRED'] as const) {
      const p = `p-${state.slice(0, 3)}-${randomUUID().slice(0, 6)}`;
      const d = `d-${state.slice(0, 3)}-${randomUUID().slice(0, 6)}`;
      const seeded = await seedToCompleted(db, p, d);
      await db.collection('rides').doc(seeded.rideId).update({ state });
      const res = await request(appFor(db, p))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `rej-${randomUUID()}`)
        .send({ stars: 5 });
      assert(res.status === 409, `${state} ${res.status}`);
      const ratingId = `${seeded.rideId}_passenger_rates_driver`;
      assert(!(await db.collection('ratings').doc(ratingId).get()).exists, 'no doc');
    }
  });

  await test('unauthorized participant live', async () => {
    const p = `p-u-${randomUUID().slice(0, 8)}`;
    const d = `d-u-${randomUUID().slice(0, 8)}`;
    const x = `x-u-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    await db.collection('users').doc(x).set({
      uid: x,
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
    });
    const res = await request(appFor(db, x))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `unauth-${randomUUID()}`)
      .send({ stars: 5 });
    assert(res.status === 403, 'forbidden');
  });

  await test('GET own rating; counterpart denied live', async () => {
    const p = `p-g-${randomUUID().slice(0, 8)}`;
    const d = `d-g-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    await request(appFor(db, p))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `get-${randomUUID()}`)
      .send({ stars: 5 });
    const mine = await request(appFor(db, p))
      .get(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t');
    assert(mine.status === 200 && mine.body.data.stars === 5, 'mine');
    const other = await request(appFor(db, d))
      .get(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t');
    assert(other.status === 404, 'no counterpart');
    assert(other.body.error.code === 'RATING_NOT_FOUND', 'code');
  });

  await test('rating concurrency 2-way live', async () => {
    const p = `p-2-${randomUUID().slice(0, 8)}`;
    const d = `d-2-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const before = stats.contendedTransactions;
    const results = await Promise.all(
      [0, 1].map((i) =>
        request(appFor(db, p))
          .post(`/v1/rides/${seeded.rideId}/ratings`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `c2-${i}-${randomUUID()}`)
          .send({ stars: 5 }),
      ),
    );
    const ok = results.filter((r) => r.status === 201).length;
    const conflict = results.filter(
      (r) => r.status === 409 && r.body.error?.code === 'ALREADY_RATED',
    ).length;
    assert(ok === 1 && conflict === 1, `ok=${ok} conflict=${conflict}`);
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    assert(await countOutbox(db, ratingId) === 1, 'one evt');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before}`,
    );
  });

  await test('rating concurrency 10-way live', async () => {
    const p = `p-10-${randomUUID().slice(0, 8)}`;
    const d = `d-10-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const before = stats.contendedTransactions;
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        request(appFor(db, p))
          .post(`/v1/rides/${seeded.rideId}/ratings`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `c10-${i}-${randomUUID()}`)
          .send({ stars: 4 }),
      ),
    );
    const ok = results.filter((r) => r.status === 201).length;
    const conflict = results.filter(
      (r) => r.status === 409 && r.body.error?.code === 'ALREADY_RATED',
    ).length;
    assert(ok === 1 && conflict === 9, `ok=${ok} conflict=${conflict}`);
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    assert(await countOutbox(db, ratingId) === 1, 'one evt');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before}`,
    );
  });

  await test('both participants concurrently live', async () => {
    const p = `p-b-${randomUUID().slice(0, 8)}`;
    const d = `d-b-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const [pr, dr] = await Promise.all([
      request(appFor(db, p))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `bp-${randomUUID()}`)
        .send({ stars: 5 }),
      request(appFor(db, d))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `bd-${randomUUID()}`)
        .send({ stars: 3 }),
    ]);
    assert(pr.status === 201 && dr.status === 201, 'both ok');
    assert(
      (await db.collection('ratings').doc(`${seeded.rideId}_passenger_rates_driver`).get())
        .exists,
      'p doc',
    );
    assert(
      (await db.collection('ratings').doc(`${seeded.rideId}_driver_rates_passenger`).get())
        .exists,
      'd doc',
    );
  });

  await test('rating vs close live', async () => {
    const p = `p-rc-${randomUUID().slice(0, 8)}`;
    const d = `d-rc-${randomUUID().slice(0, 8)}`;
    const seeded = await seedToCompleted(db, p, d);
    const [rate, close] = await Promise.all([
      request(appFor(db, p))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `rvc-r-${randomUUID()}`)
        .send({ stars: 5 }),
      request(appFor(db, p))
        .post(`/v1/rides/${seeded.rideId}/close`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `rvc-c-${randomUUID()}`)
        .send({}),
    ]);
    assert(rate.status === 201, `rate ${rate.status}`);
    assert(close.status === 200, `close ${close.status}`);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'RIDE_CLOSED', 'closed');
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    assert((await db.collection('ratings').doc(ratingId).get()).exists, 'rated');
    assert(await countOutbox(db, ratingId) === 1, 'evt');
  });

  console.log('\n--- contention notes ---');
  for (const n of notes) console.log(n);
  console.log(
    `txnStarts=${stats.transactionStarts} fnInvocations=${stats.transactionFnInvocations} contendedTxns=${stats.contendedTransactions}`,
  );
  console.log(`\nPhase 2N live proof: ${passed} passed, ${failed} failed`);
  await deleteApp(app);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
