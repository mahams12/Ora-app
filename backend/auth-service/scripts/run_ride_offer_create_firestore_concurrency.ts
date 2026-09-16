/**
 * LIVE Firestore emulator concurrency proof for Phase 2F offer-create.
 *
 * Requires FIRESTORE_EMULATOR_HOST. Uses real Admin SDK runTransaction —
 * not memoryDb.
 *
 * Usage:
 *   npm run test:ride-offer-create-firestore-concurrency
 *
 * Prefer a no-space checkout/copy if firebase-admin hangs under spaced paths.
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
  pricingSnapshotId: 'snap-offer-live-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

const offerBody = {
  type: 'DRIVER_COUNTEROFFER' as const,
  amountMinor: 26000,
  expectedRequestVersion: 1,
};

function expectedOfferId(
  rideId: string,
  driverId: string,
  requestVersion = 1,
): string {
  return `${rideId}_${driverId}_v${requestVersion}`;
}

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
  await db.collection('pricingSnapshots').doc('snap-offer-live-1').set({
    snapshotId: 'snap-offer-live-1',
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

async function createRide(
  db: Firestore,
  passengerId: string,
  idem: string,
): Promise<{ rideId: string; version: number; requestVersion: number }> {
  const res = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(createBody);
  assert(res.status === 201, `createRide ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data as {
    rideId: string;
    version: number;
    requestVersion: number;
  };
}

async function createOffer(
  db: Firestore,
  rideId: string,
  driverId: string,
  idem: string,
  body: typeof offerBody = offerBody,
) {
  return request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(body);
}

async function seedRideReadyForOffers(
  db: Firestore,
  tag: string,
): Promise<{
  passengerId: string;
  driverId: string;
  rideId: string;
  versionBefore: number;
}> {
  const passengerId = `p-${tag}-${randomUUID().slice(0, 8)}`;
  const driverId = `d-${tag}-${randomUUID().slice(0, 8)}`;
  await seedPassenger(db, passengerId);
  await seedDriver(db, driverId);
  await seedPricing(db);
  const ride = await createRide(db, passengerId, `create-${tag}-${randomUUID()}`);
  const rideSnap = await db.collection('rides').doc(ride.rideId).get();
  assert(rideSnap.exists, 'ride exists');
  assert(rideSnap.data()?.state === 'SEARCHING', 'ride SEARCHING');
  return {
    passengerId,
    driverId,
    rideId: ride.rideId,
    versionBefore: rideSnap.data()!.version as number,
  };
}

async function listOffersForRide(
  db: Firestore,
  rideId: string,
): Promise<
  Array<{
    id: string;
    driverId: string;
    rideId: string;
    requestVersion: number;
    status: string;
    amountMinor: number;
    currency: string;
    createdAt: string;
    expiresAt: string;
  }>
> {
  // Emulator may lack composite indexes; scan collection and filter.
  const snap = await db.collection('rideOffers').get();
  return snap.docs
    .map((d) => ({ id: d.id, ...(d.data() as Record<string, unknown>) }))
    .filter((o) => o.rideId === rideId)
    .map((o) => ({
      id: String(o.id),
      driverId: String(o.driverId),
      rideId: String(o.rideId),
      requestVersion: Number(o.requestVersion),
      status: String(o.status),
      amountMinor: Number(o.amountMinor),
      currency: String(o.currency),
      createdAt: String(o.createdAt),
      expiresAt: String(o.expiresAt),
    }));
}

function assertNoUndefinedFields(data: Record<string, unknown>, path: string): void {
  for (const [k, v] of Object.entries(data)) {
    assert(v !== undefined, `${path}.${k} is undefined`);
    if (v != null && typeof v === 'object' && !Array.isArray(v)) {
      assertNoUndefinedFields(v as Record<string, unknown>, `${path}.${k}`);
    }
  }
}

async function assertSinglePendingOffer(
  db: Firestore,
  rideId: string,
  driverId: string,
  amountMinor = 26000,
): Promise<string> {
  const offerId = expectedOfferId(rideId, driverId, 1);
  const offers = await listOffersForRide(db, rideId);
  assert(offers.length === 1, `offer count=${offers.length}`);
  const offer = offers[0]!;
  assert(offer.id === offerId, `offerId=${offer.id} expected=${offerId}`);
  assert(offer.driverId === driverId, 'driverId');
  assert(offer.rideId === rideId, 'rideId');
  assert(offer.requestVersion === 1, 'requestVersion');
  assert(offer.status === 'PENDING', `status=${offer.status}`);
  assert(offer.amountMinor === amountMinor, 'amountMinor');
  assert(offer.currency === 'PKR', 'currency');
  assert(typeof offer.createdAt === 'string' && offer.createdAt.length > 0, 'createdAt');
  assert(typeof offer.expiresAt === 'string' && offer.expiresAt.length > 0, 'expiresAt');

  const raw = (await db.collection('rideOffers').doc(offerId).get()).data()!;
  assertNoUndefinedFields(raw as Record<string, unknown>, `rideOffers/${offerId}`);
  return offerId;
}

async function concurrentSameDriverCreates(
  db: Firestore,
  rideId: string,
  driverId: string,
  n: number,
  keyMode: 'unique' | 'same',
) {
  const sharedKey = `same-key-${randomUUID()}`;
  return Promise.all(
    Array.from({ length: n }, (_, i) =>
      createOffer(
        db,
        rideId,
        driverId,
        keyMode === 'same' ? sharedKey : `uniq-${i}-${randomUUID()}`,
      ),
    ),
  );
}

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore offer-create concurrency — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);

  await test('offer-create concurrency 2-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideReadyForOffers(db, 'oc2');
    const results = await concurrentSameDriverCreates(
      db,
      seeded.rideId,
      seeded.driverId,
      2,
      'unique',
    );
    const wins = results.filter((r) => r.status === 201);
    const conflicts = results.filter(
      (r) => r.status === 409 && r.body?.error?.code === 'OFFER_ALREADY_EXISTS',
    );
    assert(wins.length === 1, `wins=${wins.length}`);
    assert(conflicts.length === 1, `conflicts=${conflicts.length}`);
    const offerId = await assertSinglePendingOffer(
      db,
      seeded.rideId,
      seeded.driverId,
    );
    assert(wins[0]!.body.data.offerId === offerId, 'response offerId');
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'OFFERS_AVAILABLE', `state=${ride.state}`);
    assert(
      ride.version === seeded.versionBefore + 1,
      `version ${ride.version} != ${seeded.versionBefore + 1}`,
    );
    notes.push(
      `2-way: 1 win / 1 OFFER_ALREADY_EXISTS; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }; starts+=${stats.transactionStarts - before.transactionStarts}`,
    );
  });

  await test('offer-create concurrency 10-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideReadyForOffers(db, 'oc10');
    const results = await concurrentSameDriverCreates(
      db,
      seeded.rideId,
      seeded.driverId,
      10,
      'unique',
    );
    assert(results.filter((r) => r.status === 201).length === 1, '1 win');
    assert(
      results.filter(
        (r) =>
          r.status === 409 && r.body?.error?.code === 'OFFER_ALREADY_EXISTS',
      ).length === 9,
      '9 conflicts',
    );
    await assertSinglePendingOffer(db, seeded.rideId, seeded.driverId);
    notes.push(
      `10-way: 1 win / 9 conflicts; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }`,
    );
  });

  await test('offer-create concurrency 50-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideReadyForOffers(db, 'oc50');
    const results = await concurrentSameDriverCreates(
      db,
      seeded.rideId,
      seeded.driverId,
      50,
      'unique',
    );
    assert(results.filter((r) => r.status === 201).length === 1, '1 win');
    assert(
      results.filter(
        (r) =>
          r.status === 409 && r.body?.error?.code === 'OFFER_ALREADY_EXISTS',
      ).length === 49,
      '49 conflicts',
    );
    const offerId = await assertSinglePendingOffer(
      db,
      seeded.rideId,
      seeded.driverId,
    );
    // Losers must not create a second document on retry.
    const again = await createOffer(
      db,
      seeded.rideId,
      seeded.driverId,
      `post50-${randomUUID()}`,
    );
    assert(again.status === 409, `post-create ${again.status}`);
    assert(again.body.error.code === 'OFFER_ALREADY_EXISTS', 'post code');
    const offers = await listOffersForRide(db, seeded.rideId);
    assert(offers.length === 1 && offers[0]!.id === offerId, 'still one offer');
    notes.push(
      `50-way: 1 win / 49 conflicts; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }`,
    );
  });

  await test('same idempotency key concurrent create live', async () => {
    const before = { ...stats };
    const seeded = await seedRideReadyForOffers(db, 'oc-same');
    const results = await concurrentSameDriverCreates(
      db,
      seeded.rideId,
      seeded.driverId,
      2,
      'same',
    );
    assert(
      results.every((r) => r.status === 201),
      `statuses=${results.map((r) => r.status).join(',')}`,
    );
    assert(
      results[0]!.body.data.offerId === results[1]!.body.data.offerId,
      'same offerId',
    );
    assert(
      results[0]!.body.data.rideVersion === results[1]!.body.data.rideVersion,
      'same rideVersion',
    );
    await assertSinglePendingOffer(db, seeded.rideId, seeded.driverId);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(
      ride.version === seeded.versionBefore + 1,
      'version bumped once',
    );
    notes.push(
      `same-key: both 201 replay; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }`,
    );
  });

  await test('different idempotency keys uniqueness live', async () => {
    const seeded = await seedRideReadyForOffers(db, 'oc-diffkey');
    const results = await concurrentSameDriverCreates(
      db,
      seeded.rideId,
      seeded.driverId,
      2,
      'unique',
    );
    const wins = results.filter((r) => r.status === 201);
    const conflicts = results.filter(
      (r) => r.status === 409 && r.body?.error?.code === 'OFFER_ALREADY_EXISTS',
    );
    assert(wins.length === 1, `wins=${wins.length}`);
    assert(conflicts.length === 1, `conflicts=${conflicts.length}`);
    await assertSinglePendingOffer(db, seeded.rideId, seeded.driverId);
  });

  await test('different drivers concurrent create live', async () => {
    const passengerId = `p-md-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const ride = await createRide(db, passengerId, `md-ride-${randomUUID()}`);
    const driverIds = await Promise.all(
      Array.from({ length: 5 }, async (_, i) => {
        const id = `md-${i}-${randomUUID().slice(0, 6)}`;
        await seedDriver(db, id);
        return id;
      }),
    );
    const results = await Promise.all(
      driverIds.map((driverId, i) =>
        createOffer(db, ride.rideId, driverId, `md-offer-${i}-${randomUUID()}`, {
          ...offerBody,
          amountMinor: 26000 + i,
        }),
      ),
    );
    assert(
      results.every((r) => r.status === 201),
      `statuses=${results.map((r) => `${r.status}:${r.body?.error?.code}`).join(',')}`,
    );
    const offers = await listOffersForRide(db, ride.rideId);
    assert(offers.length === 5, `offer count=${offers.length}`);
    for (const driverId of driverIds) {
      const expected = expectedOfferId(ride.rideId, driverId, 1);
      const offer = offers.find((o) => o.id === expected);
      assert(offer, `missing ${expected}`);
      assert(offer!.driverId === driverId, 'ownership');
      assert(offer!.status === 'PENDING', 'PENDING');
      assert(offer!.requestVersion === 1, 'requestVersion');
    }
    const rideDoc = (await db.collection('rides').doc(ride.rideId).get()).data()!;
    assert(rideDoc.state === 'OFFERS_AVAILABLE', 'OFFERS_AVAILABLE');
  });

  await test('offer create vs cancel live', async () => {
    const seeded = await seedRideReadyForOffers(db, 'oc-cvc');
    const [offerRes, cancelRes] = await Promise.all([
      createOffer(db, seeded.rideId, seeded.driverId, `cvc-o-${randomUUID()}`),
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `cvc-c-${randomUUID()}`)
        .send({ reason: 'race' }),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    const offers = await listOffersForRide(db, seeded.rideId);
    assert(
      ride.state === 'CANCELLED' ||
        ride.state === 'OFFERS_AVAILABLE' ||
        ride.state === 'SEARCHING',
      `state=${ride.state}`,
    );
    if (ride.state === 'CANCELLED') {
      assert(cancelRes.status === 200, `cancel ${cancelRes.status}`);
      assert(ride.assignedDriverId == null, 'no driver');
      for (const o of offers) {
        assert(
          o.status === 'EXPIRED' || o.status === 'PENDING',
          `offer status=${o.status}`,
        );
        assert(o.status !== 'SELECTED', 'not SELECTED');
      }
      if (offerRes.status === 201) {
        // Offer may have landed before cancel expired it.
        assert(offers.length <= 1, 'at most one offer');
      } else {
        assert(offerRes.status === 409, `offer ${offerRes.status}`);
        assert(
          offerRes.body.error.code === 'STATE_CONFLICT' ||
            offerRes.body.error.code === 'OFFER_ALREADY_EXISTS',
          `code=${offerRes.body.error.code}`,
        );
      }
    } else {
      assert(offerRes.status === 201, `offer ${offerRes.status}`);
      assert(cancelRes.status !== 200, `cancel ${cancelRes.status}`);
      assert(offers.length === 1, 'one offer');
      assert(offers[0]!.status === 'PENDING', 'PENDING');
    }
  });

  await test('offer create against expired ride live', async () => {
    const seeded = await seedRideReadyForOffers(db, 'oc-exp');
    await db.collection('rides').doc(seeded.rideId).update({
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });
    const res = await createOffer(
      db,
      seeded.rideId,
      seeded.driverId,
      `exp-${randomUUID()}`,
    );
    assert(res.status === 409, `status=${res.status}`);
    assert(res.body.error.code === 'STATE_CONFLICT', `code=${res.body.error.code}`);
    const offers = await listOffersForRide(db, seeded.rideId);
    assert(offers.length === 0, `offers=${offers.length}`);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.state === 'SEARCHING', `state=${ride.state}`);
    assert(ride.assignedDriverId == null, 'unassigned');
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
