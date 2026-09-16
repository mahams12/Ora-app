/**
 * Standalone Phase 2E ride proof runner (no Vitest workers).
 * Usage: node --import tsx scripts/run_ride_proof.ts
 * Or:    npx tsx scripts/run_ride_proof.ts
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import {
  assertIntegerMinor,
  assertPositiveIntegerMinor,
} from '../src/rides/money';
import { assertAssignable, assertOfferable } from '../src/rides/state_machine';
import { RideDomainError } from '../src/rides/types';
import { hashRequest } from '../src/rides/hash';

type Db = ReturnType<typeof memoryDb>;

let passed = 0;
let failed = 0;
const notes: string[] = [];

async function test(name: string, fn: () => Promise<void> | void) {
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

function seedPassenger(db: Db, uid: string, o: Record<string, unknown> = {}) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: 'P',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...o,
  });
}

function seedDriver(db: Db, uid: string, o: Record<string, unknown> = {}) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923002222222',
    displayName: 'D',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    ...o,
  });
}

function seedPricing(db: Db, id = 'snap-1') {
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    inputs: { distanceKm: 5.2, durationMin: 18 },
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
  } as never;
}

function appFor(db: Db, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
  });
}

const createBody = {
  pickup: { lat: 24.86, lng: 67.0 },
  destination: { lat: 24.9, lng: 67.1 },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

async function createRide(db: Db, passengerId: string, idem: string) {
  const res = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(createBody);
  assert(res.status === 201, `createRide status ${res.status}`);
  return res.body.data as { rideId: string; version: number };
}

async function createOffer(
  db: Db,
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

async function seedRideWithOffers(n: number) {
  const db = memoryDb();
  seedPassenger(db, 'p1');
  seedPricing(db);
  const ride = await createRide(db, 'p1', `create-${n}-${Date.now()}`);
  const offerIds: string[] = [];
  for (let i = 0; i < n; i++) {
    const driverId = `d${i}`;
    seedDriver(db, driverId);
    const res = await createOffer(
      db,
      ride.rideId,
      driverId,
      26000 + i,
      `offer-${n}-${i}-${Date.now()}`,
    );
    assert(res.status === 201, `offer ${i} status ${res.status} ${JSON.stringify(res.body)}`);
    offerIds.push(res.body.data.offerId as string);
  }
  return { db, rideId: ride.rideId, offerIds };
}

async function main() {
  await test('money validation', () => {
    try {
      assertIntegerMinor(12.5, 'x');
      throw new Error('expected throw');
    } catch (e) {
      assert(e instanceof RideDomainError, 'domain error');
    }
    assert(assertPositiveIntegerMinor(100, 'x') === 100, 'ok');
  });

  await test('state machine', () => {
    assertOfferable('SEARCHING');
    assertAssignable('OFFERS_AVAILABLE');
    try {
      assertOfferable('DRIVER_ASSIGNED');
      throw new Error('expected throw');
    } catch (e) {
      assert(e instanceof RideDomainError, 'domain error');
    }
  });

  await test('hash stable', () => {
    assert(hashRequest({ a: 1, b: 2 }) === hashRequest({ b: 2, a: 1 }), 'stable');
  });

  await test('create + assign + get', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'proof-create-1');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'proof-offer-1');
    assert(offer.status === 201, 'offer created');
    const select = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'proof-select-1')
      .send({});
    assert(select.status === 200, `select ${select.status}`);
    assert(select.body.data.agreedFareMinor === 27000, 'fare from offer');
    assert(select.body.data.assignedDriverId === 'd1', 'driver');
    const get = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    assert(get.status === 200, 'get ok');
    assert(get.body.data.state === 'DRIVER_ASSIGNED', 'assigned');
  });

  await test('IDOR get forbidden', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'idor-create');
    const denied = await request(appFor(db, 'p2'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    assert(denied.status === 403, 'idor');
  });

  await test('idempotency replay + reuse', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const app = appFor(db, 'p1');
    const a = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'idem-same')
      .send(createBody);
    const b = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'idem-same')
      .send(createBody);
    assert(a.status === 201 && b.status === 201, 'replay');
    assert(a.body.data.rideId === b.body.data.rideId, 'same ride');
    const c = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'idem-same')
      .send({ ...createBody, passengerOfferMinor: 26000 });
    assert(c.status === 409, 'reuse');
    assert(c.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'code');
  });

  await test('concurrency 2-way', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(2);
    const results = await Promise.all(
      offerIds.map((id, i) =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${id}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `concurrent-2-way-select-${i}`)
          .send({}),
      ),
    );
    const wins = results.filter((r) => r.status === 200);
    const conflicts = results.filter((r) => r.status === 409);
    assert(wins.length === 1, `wins=${wins.length}`);
    assert(conflicts.length === 1, `conflicts=${conflicts.length}`);
    notes.push('2-way: 1 win / 1 conflict');
  });

  await test('concurrency 10-way', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(10);
    const results = await Promise.all(
      offerIds.map((id, i) =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${id}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `concurrent-10-way-select-${i}`)
          .send({}),
      ),
    );
    assert(results.filter((r) => r.status === 200).length === 1, '1 win');
    assert(results.filter((r) => r.status === 409).length === 9, '9 conflicts');
    notes.push('10-way: 1 win / 9 conflicts');
  });

  await test('concurrency 50-way', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(50);
    const results = await Promise.all(
      offerIds.map((id, i) =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${id}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `concurrent-50-way-select-${i}`)
          .send({}),
      ),
    );
    assert(results.filter((r) => r.status === 200).length === 1, '1 win');
    assert(results.filter((r) => r.status === 409).length === 49, '49 conflicts');
    notes.push('50-way: 1 win / 49 conflicts');
  });

  await test('same offer same idempotency concurrent', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const id = offerIds[0]!;
    const results = await Promise.all(
      [0, 1].map(() =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${id}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', 'same-key-select')
          .send({}),
      ),
    );
    assert(results.every((r) => r.status === 200), 'both 200');
    assert(
      results[0]!.body.data.version === results[1]!.body.data.version,
      'same version',
    );
  });

  await test('select vs withdraw', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const id = offerIds[0]!;
    await Promise.all([
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/offers/${id}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-withdraw-select')
        .send({}),
      request(appFor(db, 'd0'))
        .post(`/v1/rides/${rideId}/offers/${id}/withdraw`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-withdraw-withdraw')
        .send({}),
    ]);
    const status = db.getDoc('rideOffers', id)?.status;
    assert(status === 'SELECTED' || status === 'WITHDRAWN', `status=${status}`);
  });

  await test('select vs cancel', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const id = offerIds[0]!;
    const [sel, can] = await Promise.all([
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/offers/${id}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-cancel-select')
        .send({}),
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-cancel-cancel')
        .send({ reason: 'race' }),
    ]);
    const state = db.getDoc('rides', rideId)?.state;
    assert(state === 'DRIVER_ASSIGNED' || state === 'CANCELLED', `state=${state}`);
    if (state === 'DRIVER_ASSIGNED') {
      assert(sel.status === 200 && can.status === 409, 'select won');
    } else {
      // Phase 2G: cancel may succeed after select (both 200) or alone (select 409).
      assert(can.status === 200, `cancel status=${can.status}`);
      assert(sel.status === 200 || sel.status === 409, `select status=${sel.status}`);
    }
  });

  await test('expired offer', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const id = offerIds[0]!;
    const existing = db.getDoc('rideOffers', id)!;
    db.seed('rideOffers', id, {
      ...existing,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${id}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'expired-sel')
      .send({});
    assert(res.status === 422 && res.body.error.code === 'OFFER_EXPIRED', 'expired');
    assert(db.getDoc('rides', rideId)?.assignedDriverId == null, 'unassigned');
  });

  await test('expired ride select rejected', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const id = offerIds[0]!;
    const before = db.getDoc('rides', rideId)!;
    const versionBefore = before.version as number;
    db.seed('rides', rideId, {
      ...before,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${id}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'expired-ride-sel')
      .send({});
    assert(res.status === 409 && res.body.error.code === 'STATE_CONFLICT', 'state');
    assert(db.getDoc('rides', rideId)?.assignedDriverId == null, 'unassigned');
    assert(db.getDoc('rides', rideId)?.version === versionBefore, 'version');
    assert(db.getDoc('rideOffers', id)?.status === 'PENDING', 'pending');
    const assignedEvents = [...db.store.values()].filter(
      (v) =>
        (v as { eventType?: string }).eventType === 'ride.assigned' ||
        (v as { eventType?: string }).eventType === 'ride.offer.selected',
    );
    assert(assignedEvents.length === 0, 'no assignment events');
  });

  await test('select emits offer.selected and assigned', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'outbox-create');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'outbox-offer');
    const select = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'outbox-select')
      .send({});
    assert(select.status === 200, 'select ok');
    const types = [...db.store.values()]
      .map((v) => (v as { eventType?: string }).eventType)
      .filter(Boolean);
    assert(types.includes('ride.offer.selected'), 'selected event');
    assert(types.includes('ride.assigned'), 'assigned event');
  });

  await test('idempotency different actor rejected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedPricing(db);
    const a = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'shared-key-actors')
      .send(createBody);
    const b = await request(appFor(db, 'p2'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'shared-key-actors')
      .send(createBody);
    assert(a.status === 201, 'first ok');
    assert(b.status === 409 && b.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'actor');
    assert(
      [...db.store.keys()].filter((k) => k.startsWith('rides/')).length === 1,
      'one ride',
    );
  });

  await test('stale version', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'ver-create');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'ver-offer');
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'stale-version-select-key')
      .send({ expectedVersion: 1 });
    assert(res.status === 409 && res.body.error.code === 'VERSION_CONFLICT', 'version');
  });

  console.log('\n---');
  console.log(`passed=${passed} failed=${failed}`);
  for (const n of notes) console.log(n);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
