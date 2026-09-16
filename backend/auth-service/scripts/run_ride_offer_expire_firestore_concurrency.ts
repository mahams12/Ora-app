/**
 * LIVE Firestore emulator concurrency proof for Phase 2K offer expiry sweeper.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction.
 *
 * Usage:
 *   npm run test:ride-offer-expire-firestore-concurrency
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
  pricingSnapshotId: 'snap-offer-expire-live-1',
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
  await db.collection('pricingSnapshots').doc('snap-offer-expire-live-1').set({
    snapshotId: 'snap-offer-expire-live-1',
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

async function createOfferLive(
  db: Firestore,
  rideId: string,
  driverId: string,
  tag: string,
): Promise<{ offerId: string }> {
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `offer-${tag}-${randomUUID()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(offer.status === 201, `offer ${offer.status} ${JSON.stringify(offer.body)}`);
  return { offerId: offer.body.data.offerId as string };
}

async function backdateOfferExpiry(
  db: Firestore,
  offerId: string,
): Promise<void> {
  await db.collection('rideOffers').doc(offerId).update({
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
}

async function backdateRideExpiry(db: Firestore, rideId: string): Promise<void> {
  await db.collection('rides').doc(rideId).update({
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
}

async function offerExpireSweep(db: Firestore, limit?: number) {
  const req = request(workerApp(db))
    .post('/v1/internal/rides/offer-expire-sweep')
    .set('X-Ora-Worker-Token', WORKER_TOKEN);
  if (limit != null) req.query({ limit: String(limit) });
  return req;
}

async function countOfferOutbox(
  db: Firestore,
  offerId: string,
): Promise<number> {
  const snap = await db.collection('outboxEvents').get();
  return snap.docs.filter((d) => {
    const data = d.data();
    return (
      data.eventType === 'ride.offer.expired' &&
      data.payload?.offerId === offerId
    );
  }).length;
}

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore offer-expire concurrency — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);
  const rides = new RideService(db);

  await test('sweeper query index PENDING due offer live', async () => {
    const passengerId = `p-q-${randomUUID().slice(0, 8)}`;
    const driverId = `d-q-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'q');
    const rideVerAfterCreate = (
      await db.collection('rides').doc(rideId).get()
    ).data()!.version as number;
    const { offerId } = await createOfferLive(db, rideId, driverId, 'q');
    const rideVerAfterOffer = (
      await db.collection('rides').doc(rideId).get()
    ).data()!.version as number;
    assert(
      rideVerAfterOffer === rideVerAfterCreate + 1,
      'offer create bumps SEARCHING→OFFERS_AVAILABLE',
    );
    await backdateOfferExpiry(db, offerId);

    const due = await db
      .collection('rideOffers')
      .where('status', '==', 'PENDING')
      .where('expiresAt', '<=', new Date().toISOString())
      .limit(50)
      .get();
    assert(
      due.docs.some((d) => d.id === offerId),
      'indexed query returns due offer',
    );

    const sweep = await offerExpireSweep(db);
    assert(sweep.status === 200, `sweep ${sweep.status}`);
    assert(sweep.body.data.expired >= 1, 'expired>=1');

    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', `status=${offer.status}`);
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(
      ride.version === rideVerAfterOffer,
      'offer-only expiry must not bump ride.version',
    );
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    const evt = (await db.collection('outboxEvents').get()).docs.find(
      (d) =>
        d.data().eventType === 'ride.offer.expired' &&
        d.data().payload?.offerId === offerId,
    )!;
    assert(evt.data().payload.reason === 'offer_ttl_elapsed', 'reason');
    assert(evt.data().payload.rideId === rideId, 'rideId');
    assert(evt.data().payload.driverId === driverId, 'driverId');
  });

  await test('non-due PENDING unchanged live', async () => {
    const passengerId = `p-fut-${randomUUID().slice(0, 8)}`;
    const driverId = `d-fut-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'fut');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'fut');
    const rideVer = (await db.collection('rides').doc(rideId).get()).data()!
      .version;
    const sweep = await offerExpireSweep(db);
    assert(sweep.status === 200, 'sweep');
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'PENDING', 'still PENDING');
    assert((await countOfferOutbox(db, offerId)) === 0, 'no evt');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.version === rideVer, 'ride version unchanged');
  });

  await test('parent ride EXPIRED cleans PENDING offers live', async () => {
    const passengerId = `p-par-${randomUUID().slice(0, 8)}`;
    const driverId = `d-par-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'par');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'par');
    // Keep offer TTL in the future.
    await backdateRideExpiry(db, rideId);
    const outcome = await rides.expireRide({
      rideId,
      correlationId: `par-${randomUUID()}`,
    });
    assert(outcome.outcome === 'expired', 'ride expired');
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'offer expired');
    assert((await countOfferOutbox(db, offerId)) === 1, 'one offer evt');
    const evt = (await db.collection('outboxEvents').get()).docs.find(
      (d) =>
        d.data().eventType === 'ride.offer.expired' &&
        d.data().payload?.offerId === offerId,
    )!;
    assert(evt.data().payload.reason === 'parent_ride_expired', 'parent reason');
  });

  await test('offer expire concurrency 2-way live', async () => {
    const before = { ...stats };
    const passengerId = `p-c2-${randomUUID().slice(0, 8)}`;
    const driverId = `d-c2-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'c2');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'c2');
    await backdateOfferExpiry(db, offerId);
    const rideVer = (await db.collection('rides').doc(rideId).get()).data()!
      .version;
    await Promise.all([
      rides.expireOffer({
        offerId,
        correlationId: `c2-a-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
      rides.expireOffer({
        offerId,
        correlationId: `c2-b-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
    ]);
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'EXPIRED');
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(ride.version === rideVer, 'ride version unchanged');
    notes.push(
      `2-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('offer expire concurrency 10-way live', async () => {
    const before = { ...stats };
    const passengerId = `p-c10-${randomUUID().slice(0, 8)}`;
    const driverId = `d-c10-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'c10');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'c10');
    await backdateOfferExpiry(db, offerId);
    await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        rides.expireOffer({
          offerId,
          correlationId: `c10-${i}-${randomUUID()}`,
          reason: 'offer_ttl_elapsed',
        }),
      ),
    );
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    notes.push(
      `10-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('offer expire concurrency 50-way live', async () => {
    const before = { ...stats };
    const passengerId = `p-c50-${randomUUID().slice(0, 8)}`;
    const driverId = `d-c50-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'c50');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'c50');
    await backdateOfferExpiry(db, offerId);
    await Promise.all(
      Array.from({ length: 50 }, (_, i) =>
        rides.expireOffer({
          offerId,
          correlationId: `c50-${i}-${randomUUID()}`,
          reason: 'offer_ttl_elapsed',
        }),
      ),
    );
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'EXPIRED');
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    notes.push(
      `50-way: contendedTxns+=${stats.contendedTransactions - before.contendedTransactions}`,
    );
  });

  await test('expire vs select live', async () => {
    const passengerId = `p-race-s-${randomUUID().slice(0, 8)}`;
    const driverId = `d-race-s-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'rs');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'rs');
    await backdateOfferExpiry(db, offerId);

    const [expireOutcome, selectRes] = await Promise.all([
      rides.expireOffer({
        offerId,
        correlationId: `race-exp-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
      request(appFor(db, passengerId))
        .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `sel-${randomUUID()}`)
        .send({}),
    ]);

    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    const events = await countOfferOutbox(db, offerId);

    if (offer.status === 'SELECTED') {
      assert(ride.state === 'DRIVER_ASSIGNED', 'assigned');
      assert(expireOutcome.outcome === 'skipped', 'expire skipped');
      assert(events === 0, 'no expire evt');
      assert(selectRes.status === 200, 'select won');
      notes.push('expire-vs-select: SELECT won');
    } else if (offer.status === 'EXPIRED') {
      assert(ride.assignedDriverId == null, 'no assignment');
      assert(ride.state !== 'DRIVER_ASSIGNED', 'not assigned');
      assert(expireOutcome.outcome === 'expired', 'expire won');
      assert(events === 1, 'one expire evt');
      assert(
        selectRes.status === 422 || selectRes.status === 409,
        `select rejected ${selectRes.status}`,
      );
      notes.push('expire-vs-select: EXPIRE won');
    } else {
      throw new Error(`unexpected offer status ${offer.status}`);
    }
  });

  await test('expire vs withdraw live', async () => {
    const passengerId = `p-race-w-${randomUUID().slice(0, 8)}`;
    const driverId = `d-race-w-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'rw');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'rw');
    await backdateOfferExpiry(db, offerId);

    const [expireOutcome, withdrawRes] = await Promise.all([
      rides.expireOffer({
        offerId,
        correlationId: `race-w-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
      request(appFor(db, driverId))
        .post(`/v1/rides/${rideId}/offers/${offerId}/withdraw`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `wd-${randomUUID()}`)
        .send({}),
    ]);

    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    const events = await countOfferOutbox(db, offerId);

    if (offer.status === 'WITHDRAWN') {
      assert(expireOutcome.outcome === 'skipped', 'expire skipped');
      assert(events === 0, 'no expire evt');
      assert(withdrawRes.status === 200, 'withdraw won');
      notes.push('expire-vs-withdraw: WITHDRAW won');
    } else if (offer.status === 'EXPIRED') {
      assert(expireOutcome.outcome === 'expired', 'expire won');
      assert(events === 1, 'one evt');
      assert(
        withdrawRes.status === 422 || withdrawRes.status === 409,
        `withdraw rejected ${withdrawRes.status}`,
      );
      notes.push('expire-vs-withdraw: EXPIRE won');
    } else {
      throw new Error(`unexpected ${offer.status}`);
    }
  });

  await test('expire vs parent ride EXPIRED live', async () => {
    const passengerId = `p-race-p-${randomUUID().slice(0, 8)}`;
    const driverId = `d-race-p-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'rp');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'rp');
    await backdateOfferExpiry(db, offerId);
    await backdateRideExpiry(db, rideId);

    await Promise.all([
      rides.expireOffer({
        offerId,
        correlationId: `race-po-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
      rides.expireRide({
        rideId,
        correlationId: `race-pr-${randomUUID()}`,
      }),
    ]);

    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    const ride = (await db.collection('rides').doc(rideId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'offer EXPIRED');
    assert(ride.state === 'EXPIRED', 'ride EXPIRED');
    assert((await countOfferOutbox(db, offerId)) === 1, 'exactly one offer evt');
    notes.push('expire-vs-parent: single offer event');
  });

  await test('expire vs cancel live', async () => {
    const passengerId = `p-race-c-${randomUUID().slice(0, 8)}`;
    const driverId = `d-race-c-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'rc');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'rc');
    await backdateOfferExpiry(db, offerId);

    const [, cancelRes] = await Promise.all([
      rides.expireOffer({
        offerId,
        correlationId: `race-ce-${randomUUID()}`,
        reason: 'offer_ttl_elapsed',
      }),
      request(appFor(db, passengerId))
        .post(`/v1/rides/${rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `cancel-${randomUUID()}`)
        .send({}),
    ]);

    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'offer EXPIRED');
    // Cancel may succeed (CANCELLED) or lose to expire leaving ride OFFERS_AVAILABLE/EXPIRED via other path.
    // Offer must have exactly one ride.offer.expired.
    assert((await countOfferOutbox(db, offerId)) === 1, 'exactly one offer evt');
    void cancelRes;
    notes.push('expire-vs-cancel: single offer event');
  });

  await test('retry after success live', async () => {
    const passengerId = `p-ret-${randomUUID().slice(0, 8)}`;
    const driverId = `d-ret-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'ret');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'ret');
    await backdateOfferExpiry(db, offerId);
    const first = await rides.expireOffer({
      offerId,
      correlationId: 'ret-1',
      reason: 'offer_ttl_elapsed',
    });
    assert(first.outcome === 'expired', 'first');
    const second = await rides.expireOffer({
      offerId,
      correlationId: 'ret-2',
      reason: 'offer_ttl_elapsed',
    });
    assert(second.outcome === 'already_expired', 'second');
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    const sweep = await offerExpireSweep(db);
    assert(sweep.status === 200, 'resweep ok');
    assert((await countOfferOutbox(db, offerId)) === 1, 'still one');
  });

  await test('SELECTED untouched live', async () => {
    const passengerId = `p-sel-${randomUUID().slice(0, 8)}`;
    const driverId = `d-sel-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'sel');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'sel');
    const sel = await request(appFor(db, passengerId))
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `sel-${randomUUID()}`)
      .send({});
    assert(sel.status === 200, 'select');
    await backdateOfferExpiry(db, offerId);
    const outcome = await rides.expireOffer({
      offerId,
      correlationId: 'sel-exp',
      reason: 'offer_ttl_elapsed',
    });
    assert(outcome.outcome === 'skipped', 'skipped');
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'SELECTED', 'still SELECTED');
    assert((await countOfferOutbox(db, offerId)) === 0, 'no evt');
  });

  await test('worker unauthorized live', async () => {
    const bad = await request(workerApp(db))
      .post('/v1/internal/rides/offer-expire-sweep')
      .set('X-Ora-Worker-Token', 'wrong-token-xxxxx');
    assert(bad.status === 403, `403 got ${bad.status}`);
  });

  await test('cancel emits ride.offer.expired live', async () => {
    const passengerId = `p-can-${randomUUID().slice(0, 8)}`;
    const driverId = `d-can-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedDriver(db, driverId);
    await seedPricing(db);
    const { rideId } = await createRideLive(db, passengerId, 'can');
    const { offerId } = await createOfferLive(db, rideId, driverId, 'can');
    const cancel = await request(appFor(db, passengerId))
      .post(`/v1/rides/${rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `can-${randomUUID()}`)
      .send({});
    assert(
      cancel.status === 200,
      `cancel ${cancel.status} ${JSON.stringify(cancel.body)}`,
    );
    const offer = (await db.collection('rideOffers').doc(offerId).get()).data()!;
    assert(offer.status === 'EXPIRED', 'EXPIRED');
    assert((await countOfferOutbox(db, offerId)) === 1, 'one evt');
    const evt = (await db.collection('outboxEvents').get()).docs.find(
      (d) =>
        d.data().eventType === 'ride.offer.expired' &&
        d.data().payload?.offerId === offerId,
    )!;
    assert(
      evt.data().payload.reason === 'parent_ride_cancelled',
      'cancel reason',
    );
  });

  console.log('\n--- contention notes ---');
  for (const n of notes) console.log(n);
  console.log(
    `\nPhase 2K live proof: ${passed} passed, ${failed} failed`,
  );

  const apps = getApps();
  if (apps[0]) await deleteApp(apps[0]);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
