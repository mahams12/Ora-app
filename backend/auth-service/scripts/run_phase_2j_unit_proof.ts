/**
 * Standalone Phase 2J unit proof (no Vitest workers).
 * Usage: npm run test:phase-2j-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { RideService } from '../src/rides/ride_service';

const WORKER_TOKEN = 'test-worker-token-16chars';

let passed = 0;
let failed = 0;

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

function seedPassenger(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: 'Passenger',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
  });
}

function seedDriver(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923002222222',
    displayName: 'Driver',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
}

function seedPricing(db: ReturnType<typeof memoryDb>) {
  db.seed('pricingSnapshots', 'snap-1', {
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

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
  } as never;
}

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

function workerApp(db: ReturnType<typeof memoryDb>) {
  return createApp({
    auth: authFor('worker'),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
    internalWorkerToken: WORKER_TOKEN,
  });
}

const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

async function createRide(db: ReturnType<typeof memoryDb>, passengerId: string) {
  const res = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `create-${Math.random()}`)
    .send(createBody);
  assert(res.status === 201, `create ${res.status}`);
  return res.body.data as { rideId: string; version: number };
}

function backdate(db: ReturnType<typeof memoryDb>, rideId: string) {
  const doc = db.getDoc('rides', rideId)!;
  db.seed('rides', rideId, {
    ...doc,
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
}

function countEvents(db: ReturnType<typeof memoryDb>, rideId: string): number {
  return [...db.store.entries()].filter(
    ([k, v]) =>
      k.startsWith('outboxEvents/') &&
      (v as { eventType?: string; aggregateId?: string }).eventType ===
        'ride.expired' &&
      (v as { aggregateId?: string }).aggregateId === rideId,
  ).length;
}

async function main(): Promise<void> {
  await test('worker auth gate', async () => {
    const db = memoryDb();
    assert(
      (
        await request(workerApp(db))
          .post('/v1/internal/rides/expire-sweep')
          .set('X-Ora-Worker-Token', 'bad')
      ).status === 403,
      '403',
    );
  });

  await test('SEARCHING expiry + outbox', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    backdate(db, ride.rideId);
    const v0 = db.getDoc('rides', ride.rideId)!.version as number;
    const sweep = await request(workerApp(db))
      .post('/v1/internal/rides/expire-sweep')
      .set('X-Ora-Worker-Token', WORKER_TOKEN);
    assert(sweep.status === 200, 'sweep');
    assert(sweep.body.data.expired === 1, 'expired');
    const doc = db.getDoc('rides', ride.rideId)!;
    assert(doc.state === 'EXPIRED', 'state');
    assert(doc.version === v0 + 1, 'version');
    assert(countEvents(db, ride.rideId) === 1, 'evt');
  });

  await test('idempotent retry', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p2');
    seedPricing(db);
    const ride = await createRide(db, 'p2');
    backdate(db, ride.rideId);
    const svc = new RideService(db as never);
    const a = await svc.expireRide({ rideId: ride.rideId, correlationId: 'a' });
    const b = await svc.expireRide({ rideId: ride.rideId, correlationId: 'b' });
    assert(a.outcome === 'expired', 'first');
    assert(b.outcome === 'already_expired', 'second');
    assert(countEvents(db, ride.rideId) === 1, 'one evt');
  });

  await test('assigned skipped', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p3');
    seedDriver(db, 'd3');
    seedPricing(db);
    const ride = await createRide(db, 'p3');
    const offer = await request(appFor(db, 'd3'))
      .post(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'offer-key-03')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    assert(offer.status === 201, 'offer');
    await request(appFor(db, 'p3'))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-03')
      .send({});
    backdate(db, ride.rideId);
    const v = db.getDoc('rides', ride.rideId)!.version as number;
    await request(workerApp(db))
      .post('/v1/internal/rides/expire-sweep')
      .set('X-Ora-Worker-Token', WORKER_TOKEN);
    assert(db.getDoc('rides', ride.rideId)?.state === 'DRIVER_ASSIGNED', 'assigned');
    assert(db.getDoc('rides', ride.rideId)?.version === v, 'version');
    assert(countEvents(db, ride.rideId) === 0, 'no evt');
  });

  console.log(`\npassed=${passed} failed=${failed}`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
