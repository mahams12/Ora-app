/**
 * LIVE Firestore emulator concurrency proof for Phase 2E assignment.
 *
 * Requires FIRESTORE_EMULATOR_HOST (set by `firebase emulators:exec` or a
 * running emulator). Uses real Admin SDK transactions — not memoryDb.
 *
 * Usage (from repo root):
 *   npm run test:ride-firestore-concurrency
 *
 * If the workspace path contains spaces, firebase-admin may hang while loading
 * from that path's node_modules. Prefer CI, or a no-space checkout/copy.
 *
 * Harness create payloads always include lat/lng address strings because the
 * live Firestore SDK rejects undefined nested fields (see Phase 2E live proof
 * report — production writer should omit undefined, not write it).
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
  pricingSnapshotId: 'snap-live-1',
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
  await db.collection('pricingSnapshots').doc('snap-live-1').set({
    snapshotId: 'snap-live-1',
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
): Promise<{ rideId: string; version: number }> {
  const res = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(createBody);
  assert(res.status === 201, `createRide ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data as { rideId: string; version: number };
}

async function createOffer(
  db: Firestore,
  rideId: string,
  driverId: string,
  amount: number,
  idem: string,
) {
  return request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: amount,
      expectedRequestVersion: 1,
    });
}

async function seedRideWithOffers(
  db: Firestore,
  n: number,
  tag: string,
): Promise<{
  passengerId: string;
  rideId: string;
  offerIds: string[];
  driverIds: string[];
  versionBeforeSelect: number;
}> {
  const passengerId = `p-${tag}-${randomUUID().slice(0, 8)}`;
  await seedPassenger(db, passengerId);
  await seedPricing(db);
  const ride = await createRide(
    db,
    passengerId,
    `create-${tag}-${randomUUID()}`,
  );
  const offerIds: string[] = [];
  const driverIds: string[] = [];
  for (let i = 0; i < n; i++) {
    const driverId = `d-${tag}-${i}-${randomUUID().slice(0, 6)}`;
    driverIds.push(driverId);
    await seedDriver(db, driverId);
    const res = await createOffer(
      db,
      ride.rideId,
      driverId,
      26000 + i,
      `offer-${tag}-${i}-${randomUUID()}`,
    );
    assert(
      res.status === 201,
      `offer ${i} ${res.status} ${JSON.stringify(res.body)}`,
    );
    offerIds.push(res.body.data.offerId as string);
  }
  const rideSnap = await db.collection('rides').doc(ride.rideId).get();
  const versionBeforeSelect = (rideSnap.data()?.version as number) ?? 0;
  return {
    passengerId,
    rideId: ride.rideId,
    offerIds,
    driverIds,
    versionBeforeSelect,
  };
}

async function concurrentSelect(
  db: Firestore,
  passengerId: string,
  rideId: string,
  offerIds: string[],
  keyPrefix: string,
) {
  return Promise.all(
    offerIds.map((offerId, i) =>
      request(appFor(db, passengerId))
        .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `${keyPrefix}-${i}-${randomUUID()}`)
        .send({}),
    ),
  );
}

async function assertPersistedAssignment(
  db: Firestore,
  rideId: string,
  offerIds: string[],
  versionBeforeSelect: number,
): Promise<{
  assignedDriverId: string;
  agreedOfferId: string;
  agreedFareMinor: number;
}> {
  const rideSnap = await db.collection('rides').doc(rideId).get();
  assert(rideSnap.exists, 'ride exists');
  const ride = rideSnap.data()!;
  assert(ride.state === 'DRIVER_ASSIGNED', `state=${ride.state}`);
  assert(typeof ride.assignedDriverId === 'string', 'assignedDriverId');
  assert(typeof ride.agreedOfferId === 'string', 'agreedOfferId');
  assert(typeof ride.agreedFareMinor === 'number', 'agreedFareMinor');
  assert(
    ride.version === versionBeforeSelect + 1,
    `version ${ride.version} != ${versionBeforeSelect + 1}`,
  );

  const winner = await db.collection('rideOffers').doc(ride.agreedOfferId).get();
  assert(winner.exists, 'winning offer exists');
  assert(winner.data()?.status === 'SELECTED', 'winner SELECTED');
  assert(
    winner.data()?.driverId === ride.assignedDriverId,
    'winner driver matches',
  );
  assert(
    winner.data()?.amountMinor === ride.agreedFareMinor,
    'fare from winning offer',
  );

  let selectedCount = 0;
  for (const id of offerIds) {
    const snap = await db.collection('rideOffers').doc(id).get();
    const status = snap.data()?.status;
    if (status === 'SELECTED') selectedCount += 1;
    if (id !== ride.agreedOfferId) {
      assert(status !== 'SELECTED', `loser ${id} must not be SELECTED`);
      assert(
        status === 'SUPERSEDED' || status === 'PENDING' || status === 'WITHDRAWN',
        `loser ${id} status=${status}`,
      );
    }
  }
  assert(selectedCount === 1, `selectedCount=${selectedCount}`);

  return {
    assignedDriverId: ride.assignedDriverId as string,
    agreedOfferId: ride.agreedOfferId as string,
    agreedFareMinor: ride.agreedFareMinor as number,
  };
}

async function listOutboxForRide(
  db: Firestore,
  rideId: string,
): Promise<Array<{ eventType: string; aggregateVersion: number }>> {
  // Emulator may lack composite indexes for arbitrary queries; scan collection.
  const snap = await db.collection('outboxEvents').get();
  return snap.docs
    .map((d) => d.data())
    .filter((e) => e.aggregateId === rideId)
    .map((e) => ({
      eventType: String(e.eventType),
      aggregateVersion: Number(e.aggregateVersion),
    }));
}

async function main(): Promise<void> {
  requireEmulator();
  console.log(
    `LIVE Firestore concurrency proof — emulator=${process.env.FIRESTORE_EMULATOR_HOST}`,
  );

  if (getApps().length === 0) {
    initializeApp({ projectId: 'ora-app-d8112' });
  }
  const db = getFirestore();
  const stats = instrumentRunTransaction(db);

  await test('concurrency 2-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideWithOffers(db, 2, 'c2');
    const results = await concurrentSelect(
      db,
      seeded.passengerId,
      seeded.rideId,
      seeded.offerIds,
      'live-2way',
    );
    const wins = results.filter((r) => r.status === 200);
    const conflicts = results.filter((r) => r.status === 409);
    assert(wins.length === 1, `wins=${wins.length}`);
    assert(conflicts.length === 1, `conflicts=${conflicts.length}`);
    await assertPersistedAssignment(
      db,
      seeded.rideId,
      seeded.offerIds,
      seeded.versionBeforeSelect,
    );
    const deltaRetries =
      stats.contendedTransactions - before.contendedTransactions;
    notes.push(
      `2-way: 1 win / 1 conflict; contendedTxns+=${deltaRetries}; fnInvocations+=${
        stats.transactionFnInvocations - before.transactionFnInvocations
      }`,
    );
  });

  await test('concurrency 10-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideWithOffers(db, 10, 'c10');
    const results = await concurrentSelect(
      db,
      seeded.passengerId,
      seeded.rideId,
      seeded.offerIds,
      'live-10way',
    );
    assert(results.filter((r) => r.status === 200).length === 1, '1 win');
    assert(results.filter((r) => r.status === 409).length === 9, '9 conflicts');
    await assertPersistedAssignment(
      db,
      seeded.rideId,
      seeded.offerIds,
      seeded.versionBeforeSelect,
    );
    notes.push(
      `10-way: 1 win / 9 conflicts; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }`,
    );
  });

  await test('concurrency 50-way live', async () => {
    const before = { ...stats };
    const seeded = await seedRideWithOffers(db, 50, 'c50');
    const results = await concurrentSelect(
      db,
      seeded.passengerId,
      seeded.rideId,
      seeded.offerIds,
      'live-50way',
    );
    assert(results.filter((r) => r.status === 200).length === 1, '1 win');
    assert(results.filter((r) => r.status === 409).length === 49, '49 conflicts');
    const final = await assertPersistedAssignment(
      db,
      seeded.rideId,
      seeded.offerIds,
      seeded.versionBeforeSelect,
    );
    // Losers must not become SELECTED later.
    for (const id of seeded.offerIds) {
      if (id === final.agreedOfferId) continue;
      const again = await request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/offers/${id}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `post50-${randomUUID()}`)
        .send({});
      assert(again.status === 409, `post-select loser ${again.status}`);
    }
    notes.push(
      `50-way: 1 win / 49 conflicts; contendedTxns+=${
        stats.contendedTransactions - before.contendedTransactions
      }`,
    );
  });

  await test('same offer same idempotency concurrent live', async () => {
    const seeded = await seedRideWithOffers(db, 1, 'idem-same');
    const offerId = seeded.offerIds[0]!;
    const key = `same-key-${randomUUID()}`;
    const results = await Promise.all(
      [0, 1].map(() =>
        request(appFor(db, seeded.passengerId))
          .post(`/v1/rides/${seeded.rideId}/offers/${offerId}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', key)
          .send({}),
      ),
    );
    assert(results.every((r) => r.status === 200), 'both 200');
    assert(
      results[0]!.body.data.version === results[1]!.body.data.version,
      'same version',
    );
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(ride.version === seeded.versionBeforeSelect + 1, 'version +1 once');
    assert(ride.assignedDriverId != null, 'assigned');
    const selected = (
      await db.collection('rideOffers').doc(offerId).get()
    ).data()?.status;
    assert(selected === 'SELECTED', 'selected once');
    const events = await listOutboxForRide(db, seeded.rideId);
    const assigned = events.filter((e) => e.eventType === 'ride.assigned');
    const offerSelected = events.filter(
      (e) => e.eventType === 'ride.offer.selected',
    );
    assert(assigned.length === 1, `assigned events=${assigned.length}`);
    assert(
      offerSelected.length === 1,
      `offer.selected events=${offerSelected.length}`,
    );
  });

  await test('idempotency different body live', async () => {
    const passengerId = `p-body-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, passengerId);
    await seedPricing(db);
    const key = `body-key-${randomUUID()}`;
    const a = await request(appFor(db, passengerId))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send(createBody);
    const b = await request(appFor(db, passengerId))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ ...createBody, passengerOfferMinor: 26000 });
    assert(a.status === 201, 'first create');
    assert(b.status === 409, `second ${b.status}`);
    assert(b.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'code');
  });

  await test('idempotency different actor live', async () => {
    const p1 = `p-a1-${randomUUID().slice(0, 8)}`;
    const p2 = `p-a2-${randomUUID().slice(0, 8)}`;
    await seedPassenger(db, p1);
    await seedPassenger(db, p2);
    await seedPricing(db);
    const key = `actor-key-${randomUUID()}`;
    const a = await request(appFor(db, p1))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send(createBody);
    const b = await request(appFor(db, p2))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send(createBody);
    assert(a.status === 201, 'first');
    assert(b.status === 409 && b.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'actor');
    const ride = (
      await db.collection('rides').doc(a.body.data.rideId).get()
    ).data();
    assert(ride?.passengerId === p1, 'first actor owns ride');
  });

  await test('select vs cancel live', async () => {
    const seeded = await seedRideWithOffers(db, 1, 'svc');
    const offerId = seeded.offerIds[0]!;
    const [sel, can] = await Promise.all([
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `svc-sel-${randomUUID()}`)
        .send({}),
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `svc-can-${randomUUID()}`)
        .send({ reason: 'race' }),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    assert(
      ride.state === 'DRIVER_ASSIGNED' || ride.state === 'CANCELLED',
      `state=${ride.state}`,
    );
    const events = await listOutboxForRide(db, seeded.rideId);
    if (ride.state === 'DRIVER_ASSIGNED') {
      // Winner must be select; cancel may be 409 business conflict or rare
      // INTERNAL after Firestore txn retry exhaustion — never a successful cancel.
      assert(sel.status === 200, `select status=${sel.status}`);
      assert(can.status !== 200, `cancel status=${can.status} body=${JSON.stringify(can.body)}`);
      assert(ride.assignedDriverId != null, 'driver set');
      assert(events.some((e) => e.eventType === 'ride.assigned'), 'assigned evt');
      assert(
        !events.some((e) => e.eventType === 'ride.cancelled'),
        'no cancel evt',
      );
    } else {
      // Phase 2G: cancel after assign is legal — select may 200 then cancel 200,
      // leaving CANCELLED with assignedDriverId retained; or cancel-only (select 409).
      assert(can.status === 200, `cancel status=${can.status}`);
      assert(
        sel.status === 200 || sel.status === 409,
        `select status=${sel.status} body=${JSON.stringify(sel.body)}`,
      );
      assert(events.some((e) => e.eventType === 'ride.cancelled'), 'cancel evt');
      if (sel.status === 200) {
        assert(ride.assignedDriverId != null, 'assignee retained after post-assign cancel');
        assert(events.some((e) => e.eventType === 'ride.assigned'), 'assigned then cancelled');
      } else {
        assert(ride.assignedDriverId == null, 'no driver');
        assert(
          !events.some((e) => e.eventType === 'ride.assigned'),
          'no assigned evt',
        );
      }
    }
  });

  await test('select vs withdraw live', async () => {
    const seeded = await seedRideWithOffers(db, 1, 'svw');
    const offerId = seeded.offerIds[0]!;
    const driverId = seeded.driverIds[0]!;
    await Promise.all([
      request(appFor(db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `svw-sel-${randomUUID()}`)
        .send({}),
      request(appFor(db, driverId))
        .post(`/v1/rides/${seeded.rideId}/offers/${offerId}/withdraw`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `svw-wd-${randomUUID()}`)
        .send({}),
    ]);
    const ride = (await db.collection('rides').doc(seeded.rideId).get()).data()!;
    const offer = (
      await db.collection('rideOffers').doc(offerId).get()
    ).data()!;
    assert(
      offer.status === 'SELECTED' || offer.status === 'WITHDRAWN',
      `offer=${offer.status}`,
    );
    if (offer.status === 'SELECTED') {
      assert(ride.state === 'DRIVER_ASSIGNED', 'assigned');
      assert(ride.assignedDriverId === driverId, 'driver');
    } else {
      assert(ride.assignedDriverId == null, 'unassigned');
      assert(ride.state !== 'DRIVER_ASSIGNED', 'not assigned');
    }
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
