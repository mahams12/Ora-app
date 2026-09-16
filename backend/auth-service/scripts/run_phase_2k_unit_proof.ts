/**
 * Standalone Phase 2K unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-2k-unit-proof
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

async function createOffer(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  driverId: string,
) {
  const res = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `offer-${Math.random()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(res.status === 201, `offer ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data as { offerId: string };
}

function countOfferExpired(
  db: ReturnType<typeof memoryDb>,
  offerId: string,
): number {
  return [...db.store.entries()].filter(([k, v]) => {
    if (!k.startsWith('outboxEvents/')) return false;
    const e = v as {
      eventType?: string;
      payload?: { offerId?: string };
    };
    return (
      e.eventType === 'ride.offer.expired' && e.payload?.offerId === offerId
    );
  }).length;
}

async function main(): Promise<void> {
  await test('worker auth gate offer-expire-sweep', async () => {
    const db = memoryDb();
    assert(
      (
        await request(workerApp(db))
          .post('/v1/internal/rides/offer-expire-sweep')
          .set('X-Ora-Worker-Token', 'bad')
      ).status === 403,
      '403',
    );
    assert(
      (
        await request(
          createApp({
            auth: authFor('worker'),
            db: db as never,
            requireAppCheck: false,
            rateLimit: { windowMs: 60_000, max: 10_000 },
            // token unset
          }),
        )
          .post('/v1/internal/rides/offer-expire-sweep')
          .set('X-Ora-Worker-Token', WORKER_TOKEN)
      ).status === 503,
      '503 when unconfigured',
    );
  });

  await test('TTL expire PENDING + outbox; ride version unchanged', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const offer = await createOffer(db, ride.rideId, 'd1');
    const rideBefore = db.getDoc('rides', ride.rideId)!;
    db.seed('rideOffers', offer.offerId, {
      ...db.getDoc('rideOffers', offer.offerId)!,
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });

    const sweep = await request(workerApp(db))
      .post('/v1/internal/rides/offer-expire-sweep')
      .set('X-Ora-Worker-Token', WORKER_TOKEN);
    assert(sweep.status === 200, `sweep ${sweep.status}`);
    assert(sweep.body.data.expired === 1, 'expired=1');

    const offerDoc = db.getDoc('rideOffers', offer.offerId)!;
    assert(offerDoc.status === 'EXPIRED', 'status EXPIRED');
    const rideAfter = db.getDoc('rides', ride.rideId)!;
    assert(rideAfter.version === rideBefore.version, 'ride version unchanged');
    assert(countOfferExpired(db, offer.offerId) === 1, 'one outbox');
  });

  await test('future TTL not expired', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p2');
    seedDriver(db, 'd2');
    seedPricing(db);
    const ride = await createRide(db, 'p2');
    const offer = await createOffer(db, ride.rideId, 'd2');
    const sweep = await request(workerApp(db))
      .post('/v1/internal/rides/offer-expire-sweep')
      .set('X-Ora-Worker-Token', WORKER_TOKEN);
    assert(sweep.status === 200, 'sweep');
    assert(sweep.body.data.expired === 0, 'none');
    assert(db.getDoc('rideOffers', offer.offerId)!.status === 'PENDING', 'PENDING');
  });

  await test('parent ride expire cleans PENDING offers + events', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p3');
    seedDriver(db, 'd3');
    seedPricing(db);
    const ride = await createRide(db, 'p3');
    const offer = await createOffer(db, ride.rideId, 'd3');
    // Keep offer TTL in the future; parent expire must still clean up.
    db.seed('rides', ride.rideId, {
      ...db.getDoc('rides', ride.rideId)!,
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });

    const svc = new RideService(db as never);
    const outcome = await svc.expireRide({
      rideId: ride.rideId,
      correlationId: 'unit-parent',
    });
    assert(outcome.outcome === 'expired', 'ride expired');
    assert(db.getDoc('rideOffers', offer.offerId)!.status === 'EXPIRED', 'offer');
    assert(countOfferExpired(db, offer.offerId) === 1, 'offer evt');
  });

  await test('retry already EXPIRED is no-op', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p4');
    seedDriver(db, 'd4');
    seedPricing(db);
    const ride = await createRide(db, 'p4');
    const offer = await createOffer(db, ride.rideId, 'd4');
    db.seed('rideOffers', offer.offerId, {
      ...db.getDoc('rideOffers', offer.offerId)!,
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });
    const svc = new RideService(db as never);
    const first = await svc.expireOffer({
      offerId: offer.offerId,
      correlationId: 'r1',
      reason: 'offer_ttl_elapsed',
    });
    assert(first.outcome === 'expired', 'first');
    const second = await svc.expireOffer({
      offerId: offer.offerId,
      correlationId: 'r2',
      reason: 'offer_ttl_elapsed',
    });
    assert(second.outcome === 'already_expired', 'second');
    assert(countOfferExpired(db, offer.offerId) === 1, 'still one evt');
  });

  await test('cancel pre-assign emits ride.offer.expired', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p5');
    seedDriver(db, 'd5');
    seedPricing(db);
    const ride = await createRide(db, 'p5');
    const offer = await createOffer(db, ride.rideId, 'd5');
    const cancel = await request(appFor(db, 'p5'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `cancel-${Math.random()}`)
      .send({});
    assert(cancel.status === 200, `cancel ${cancel.status}`);
    assert(db.getDoc('rideOffers', offer.offerId)!.status === 'EXPIRED', 'offer');
    assert(countOfferExpired(db, offer.offerId) === 1, 'cancel outbox');
  });

  await test('SELECTED / WITHDRAWN / SUPERSEDED untouched by TTL expire', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p6');
    seedDriver(db, 'd6a');
    seedDriver(db, 'd6b');
    seedPricing(db);
    const ride = await createRide(db, 'p6');
    const offerA = await createOffer(db, ride.rideId, 'd6a');
    const offerB = await createOffer(db, ride.rideId, 'd6b');
    const select = await request(appFor(db, 'p6'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerA.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `sel-${Math.random()}`)
      .send({});
    assert(select.status === 200, `select ${select.status}`);
    assert(db.getDoc('rideOffers', offerA.offerId)!.status === 'SELECTED', 'SELECTED');
    assert(
      db.getDoc('rideOffers', offerB.offerId)!.status === 'SUPERSEDED',
      'SUPERSEDED',
    );

    for (const id of [offerA.offerId, offerB.offerId]) {
      db.seed('rideOffers', id, {
        ...db.getDoc('rideOffers', id)!,
        expiresAt: new Date(Date.now() - 60_000).toISOString(),
      });
    }

    const svc = new RideService(db as never);
    const rA = await svc.expireOffer({
      offerId: offerA.offerId,
      correlationId: 'x',
      reason: 'offer_ttl_elapsed',
    });
    const rB = await svc.expireOffer({
      offerId: offerB.offerId,
      correlationId: 'y',
      reason: 'offer_ttl_elapsed',
    });
    assert(rA.outcome === 'skipped', 'skip SELECTED');
    assert(rB.outcome === 'skipped', 'skip SUPERSEDED');
    assert(db.getDoc('rideOffers', offerA.offerId)!.status === 'SELECTED', 'still S');
    assert(
      db.getDoc('rideOffers', offerB.offerId)!.status === 'SUPERSEDED',
      'still SUP',
    );
  });

  console.log(`\nPhase 2K unit proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
