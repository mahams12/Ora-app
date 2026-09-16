/**
 * Standalone Phase 2N unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-2n-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';

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
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    rating: 4.5,
    ratingCount: 10,
    noShowCount: 2,
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

async function seedToCompleted(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  driverId: string,
): Promise<{ rideId: string; version: number; updatedAt: string; state: string }> {
  seedPassenger(db, passengerId);
  seedDriver(db, driverId);
  seedPricing(db);
  const create = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `c-${Math.random()}`)
    .send(createBody);
  assert(create.status === 201, `create ${create.status}`);
  const rideId = create.body.data.rideId as string;
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `o-${Math.random()}`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  assert(offer.status === 201, `offer ${offer.status}`);
  const select = await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `s-${Math.random()}`)
    .send({});
  assert(select.status === 200, `select ${select.status}`);
  for (const step of ['en-route', 'arrive', 'start', 'complete'] as const) {
    const res = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${step}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${step}-${Math.random()}`)
      .send({});
    assert(res.status === 200, `${step} ${res.status}`);
  }
  const ride = db.getDoc('rides', rideId)!;
  assert(ride.state === 'RIDE_COMPLETED', 'COMPLETED');
  return {
    rideId,
    version: ride.version as number,
    updatedAt: ride.updatedAt as string,
    state: ride.state as string,
  };
}

function countRatingEvents(
  db: ReturnType<typeof memoryDb>,
  ratingId: string,
): number {
  return [...db.store.entries()].filter(
    ([k, v]) =>
      k.startsWith('outboxEvents/') &&
      (v as { eventType?: string; aggregateId?: string }).eventType ===
        'ride.rating.submitted' &&
      (v as { aggregateId?: string }).aggregateId === ratingId,
  ).length;
}

function ratingEventPayload(
  db: ReturnType<typeof memoryDb>,
  ratingId: string,
): Record<string, unknown> | null {
  for (const [k, v] of db.store.entries()) {
    if (!k.startsWith('outboxEvents/')) continue;
    const e = v as {
      eventType?: string;
      aggregateId?: string;
      payload?: Record<string, unknown>;
    };
    if (e.eventType === 'ride.rating.submitted' && e.aggregateId === ratingId) {
      return e.payload ?? null;
    }
  }
  return null;
}

function setRideState(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  state: string,
) {
  const doc = db.getDoc('rides', rideId)!;
  db.seed('rides', rideId, { ...doc, state });
}

async function main(): Promise<void> {
  await test('passenger rates driver on RIDE_COMPLETED', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p1', 'd1');
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'rate-p1-aaaaaaaa')
      .send({ stars: 5 });
    assert(res.status === 201, `status ${res.status}`);
    assert(res.body.data.ratingType === 'passenger_rates_driver', 'type');
    assert(res.body.data.raterId === 'p1', 'rater');
    assert(res.body.data.ratedId === 'd1', 'rated');
    assert(res.body.data.stars === 5, 'stars');
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    const doc = db.getDoc('ratings', ratingId);
    assert(doc != null, 'persisted');
    assert(doc!.stars === 5, 'doc stars');
    assert(countRatingEvents(db, ratingId) === 1, 'one evt');
    const payload = ratingEventPayload(db, ratingId)!;
    assert(payload.rideId === seeded.rideId, 'p.rideId');
    assert(payload.ratingId === ratingId, 'p.ratingId');
    assert(payload.ratingType === 'passenger_rates_driver', 'p.type');
    assert(payload.raterId === 'p1', 'p.rater');
    assert(payload.ratedId === 'd1', 'p.rated');
    assert(payload.stars === 5, 'p.stars');
    assert(Object.keys(payload).length === 6, 'exact keys');
  });

  await test('driver rates passenger on RIDE_COMPLETED', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p2', 'd2');
    const res = await request(appFor(db, 'd2'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'rate-d2-aaaaaaaa')
      .send({ stars: 4 });
    assert(res.status === 201, `status ${res.status}`);
    assert(res.body.data.ratingType === 'driver_rates_passenger', 'type');
    assert(res.body.data.ratedId === 'p2', 'rated');
    const ratingId = `${seeded.rideId}_driver_rates_passenger`;
    assert(db.getDoc('ratings', ratingId) != null, 'doc');
    assert(countRatingEvents(db, ratingId) === 1, 'evt');
  });

  await test('both directions on RIDE_CLOSED + ride unchanged', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p3', 'd3');
    const close = await request(appFor(db, 'p3'))
      .post(`/v1/rides/${seeded.rideId}/close`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'close-p3-aaaaaaa')
      .send({});
    assert(close.status === 200, 'close');
    const before = db.getDoc('rides', seeded.rideId)!;
    const p = await request(appFor(db, 'p3'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'rate-p3-aaaaaaaa')
      .send({ stars: 3 });
    const d = await request(appFor(db, 'd3'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'rate-d3-aaaaaaaa')
      .send({ stars: 2 });
    assert(p.status === 201 && d.status === 201, 'both');
    const after = db.getDoc('rides', seeded.rideId)!;
    assert(after.state === before.state, 'state');
    assert(after.version === before.version, 'version');
    assert(after.updatedAt === before.updatedAt, 'updatedAt');
    assert(after.passengerRating == null, 'no denorm p');
    assert(after.driverRating == null, 'no denorm d');
    const driver = db.getDoc('drivers', 'd3')!;
    assert(driver.rating === 4.5, 'drv rating');
    assert(driver.ratingCount === 10, 'drv count');
    assert(driver.noShowCount === 2, 'noShow');
  });

  await test('pre-completion / STARTED / ARRIVED / NO_SHOW / CANCELLED / EXPIRED rejected', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p4', 'd4');
    for (const state of [
      'RIDE_STARTED',
      'DRIVER_ARRIVED',
      'NO_SHOW',
      'CANCELLED',
      'EXPIRED',
      'SEARCHING',
    ]) {
      setRideState(db, seeded.rideId, state);
      const res = await request(appFor(db, 'p4'))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `rej-${state}-${Math.random()}`)
        .send({ stars: 5 });
      assert(res.status === 409, `${state} → ${res.status}`);
      assert(
        db.getDoc('ratings', `${seeded.rideId}_passenger_rates_driver`) == null,
        `no doc ${state}`,
      );
    }
  });

  await test('non-participant + missing assignedDriver rejected', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p5', 'd5');
    seedPassenger(db, 'stranger');
    const stranger = await request(appFor(db, 'stranger'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'stranger-aaaaaaaa')
      .send({ stars: 5 });
    assert(stranger.status === 403, 'stranger');

    const ride = db.getDoc('rides', seeded.rideId)!;
    db.seed('rides', seeded.rideId, { ...ride, assignedDriverId: null });
    const missing = await request(appFor(db, 'p5'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'missing-drv-aaaaaa')
      .send({ stars: 5 });
    assert(missing.status === 409, 'missing driver');
  });

  await test('invalid stars rejected', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p6', 'd6');
    const bad = [
      0,
      -1,
      6,
      3.5,
      '5',
      null,
      undefined,
      [],
      {},
      Number.NaN,
    ];
    for (const stars of bad) {
      const body =
        stars === undefined ? {} : ({ stars } as Record<string, unknown>);
      const res = await request(appFor(db, 'p6'))
        .post(`/v1/rides/${seeded.rideId}/ratings`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `bad-${Math.random()}`)
        .send(body);
      assert(res.status === 400, `stars=${String(stars)} → ${res.status}`);
    }
    const forged = await request(appFor(db, 'p6'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'forge-fields-aaaaaa')
      .send({
        stars: 5,
        raterId: 'evil',
        ratedId: 'evil',
        ratingType: 'driver_rates_passenger',
      });
    assert(forged.status === 400, 'forged fields');
  });

  await test('idempotency replay / reuse / already rated', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p7', 'd7');
    const key = 'idem-rate-p7-aaaaaa';
    const first = await request(appFor(db, 'p7'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 5 });
    assert(first.status === 201, 'first');
    const replay = await request(appFor(db, 'p7'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 5 });
    assert(replay.status === 201, 'replay');
    assert(replay.body.data.stars === 5, 'replay body');
    const ratingId = `${seeded.rideId}_passenger_rates_driver`;
    assert(countRatingEvents(db, ratingId) === 1, 'still one evt');

    const reused = await request(appFor(db, 'p7'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ stars: 1 });
    assert(reused.status === 409, 'reuse');
    assert(reused.body.error?.code === 'IDEMPOTENCY_KEY_REUSED', 'reuse code');

    const dup = await request(appFor(db, 'p7'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'idem-rate-p7-bbbbbb')
      .send({ stars: 5 });
    assert(dup.status === 409, 'already');
    assert(dup.body.error?.code === 'ALREADY_RATED', 'already code');
  });

  await test('GET own rating; counterpart not exposed', async () => {
    const db = memoryDb();
    const seeded = await seedToCompleted(db, 'p8', 'd8');
    await request(appFor(db, 'p8'))
      .post(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'get-p8-aaaaaaaa')
      .send({ stars: 5 });
    const mine = await request(appFor(db, 'p8'))
      .get(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t');
    assert(mine.status === 200, 'get mine');
    assert(mine.body.data.stars === 5, 'stars');
    assert(mine.body.data.ratingType === 'passenger_rates_driver', 'type');

    const other = await request(appFor(db, 'd8'))
      .get(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t');
    assert(other.status === 404, 'driver has no own rating yet');
    assert(other.body.error?.code === 'RATING_NOT_FOUND', 'not found');

    seedPassenger(db, 'x8');
    const stranger = await request(appFor(db, 'x8'))
      .get(`/v1/rides/${seeded.rideId}/ratings`)
      .set('Authorization', 'Bearer t');
    assert(stranger.status === 403, 'stranger get');
  });

  console.log(`\nPhase 2N unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
