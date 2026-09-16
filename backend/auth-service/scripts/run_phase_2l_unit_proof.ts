/**
 * Standalone Phase 2L unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-2l-unit-proof
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

function isIso(s: unknown): boolean {
  return typeof s === 'string' && Number.isFinite(Date.parse(s));
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

async function seedAssigned(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  driverId: string,
): Promise<{ rideId: string; version: number }> {
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
  return { rideId, version: select.body.data.version as number };
}

async function enRoute(
  db: ReturnType<typeof memoryDb>,
  driverId: string,
  rideId: string,
) {
  const res = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/en-route`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `er-${Math.random()}`)
    .send({});
  assert(res.status === 200, `en-route ${res.status}`);
  return res.body.data.version as number;
}

async function main(): Promise<void> {
  await test('EN_ROUTE has null arrivedAt before arrive', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p0', 'd0');
    await enRoute(db, 'd0', rideId);
    const ride = db.getDoc('rides', rideId)!;
    assert(ride.state === 'DRIVER_EN_ROUTE', 'EN_ROUTE');
    assert(ride.arrivedAt == null, 'arrivedAt null');
  });

  await test('EN_ROUTE → ARRIVED sets arrivedAt + version +1', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p1', 'd1');
    const vEn = await enRoute(db, 'd1', rideId);
    const arrive = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `arr-${Math.random()}`)
      .send({});
    assert(arrive.status === 200, `arrive ${arrive.status}`);
    assert(arrive.body.data.state === 'DRIVER_ARRIVED', 'state');
    assert(arrive.body.data.version === vEn + 1, 'version');
    assert(isIso(arrive.body.data.arrivedAt), 'iso');
    const ride = db.getDoc('rides', rideId)!;
    assert(ride.state === 'DRIVER_ARRIVED', 'persisted state');
    assert(ride.arrivedAt === arrive.body.data.arrivedAt, 'persisted clock');
    assert(ride.version === vEn + 1, 'persisted version');
  });

  await test('idempotent replay same key preserves arrivedAt', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p2', 'd2');
    await enRoute(db, 'd2', rideId);
    const key = `arr-replay-${Math.random()}`;
    const first = await request(appFor(db, 'd2'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(first.status === 200, 'first');
    const t1 = first.body.data.arrivedAt as string;
    const v1 = first.body.data.version as number;
    const second = await request(appFor(db, 'd2'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(second.status === 200, 'second');
    assert(second.body.data.arrivedAt === t1, 'same arrivedAt');
    assert(second.body.data.version === v1, 'same version');
    assert(db.getDoc('rides', rideId)!.arrivedAt === t1, 'store');
  });

  await test('already-arrived retry does not overwrite arrivedAt', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p3', 'd3');
    await enRoute(db, 'd3', rideId);
    const first = await request(appFor(db, 'd3'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `a1-${Math.random()}`)
      .send({});
    const t1 = first.body.data.arrivedAt as string;
    const v1 = first.body.data.version as number;
    // Force different key — already at DRIVER_ARRIVED path.
    const second = await request(appFor(db, 'd3'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `a2-${Math.random()}`)
      .send({});
    assert(second.status === 200, 'already arrived');
    assert(second.body.data.arrivedAt === t1, 'unchanged');
    assert(second.body.data.version === v1, 'no bump');
  });

  await test('cancel from EN_ROUTE leaves arrivedAt null', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p4', 'd4');
    await enRoute(db, 'd4', rideId);
    const cancel = await request(appFor(db, 'p4'))
      .post(`/v1/rides/${rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `cancel-${Math.random()}`)
      .send({});
    assert(cancel.status === 200, 'cancel');
    assert(db.getDoc('rides', rideId)!.arrivedAt == null, 'null');
  });

  await test('cancel after ARRIVED preserves arrivedAt', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p4b', 'd4b');
    await enRoute(db, 'd4b', rideId);
    const arrive = await request(appFor(db, 'd4b'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `arr-${Math.random()}`)
      .send({});
    const t1 = arrive.body.data.arrivedAt as string;
    const cancel = await request(appFor(db, 'p4b'))
      .post(`/v1/rides/${rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `cancel-arr-${Math.random()}`)
      .send({});
    assert(cancel.status === 200, 'cancel');
    assert(db.getDoc('rides', rideId)!.state === 'CANCELLED', 'CANCELLED');
    assert(db.getDoc('rides', rideId)!.arrivedAt === t1, 'preserved');
  });

  await test('start/complete/close preserve arrivedAt', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p5', 'd5');
    await enRoute(db, 'd5', rideId);
    const arrive = await request(appFor(db, 'd5'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `arr-${Math.random()}`)
      .send({});
    const t1 = arrive.body.data.arrivedAt as string;
    for (const step of ['start', 'complete']) {
      const res = await request(appFor(db, 'd5'))
        .post(`/v1/rides/${rideId}/${step}`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `${step}-${Math.random()}`)
        .send({});
      assert(res.status === 200, step);
      assert(res.body.data.arrivedAt === t1, `${step} dto`);
      assert(db.getDoc('rides', rideId)!.arrivedAt === t1, `${step} store`);
    }
    const close = await request(appFor(db, 'p5'))
      .post(`/v1/rides/${rideId}/close`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `close-${Math.random()}`)
      .send({});
    assert(close.status === 200, 'close');
    assert(close.body.data.arrivedAt === t1, 'close dto');
    assert(db.getDoc('rides', rideId)!.arrivedAt === t1, 'close store');
  });

  await test('passenger arrive forbidden', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p6', 'd6');
    await enRoute(db, 'd6', rideId);
    const res = await request(appFor(db, 'p6'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `bad-${Math.random()}`)
      .send({});
    assert(res.status === 403, `403 got ${res.status}`);
    assert(db.getDoc('rides', rideId)!.arrivedAt == null, 'no clock');
  });

  await test('unrelated driver arrive forbidden', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p7', 'd7');
    seedDriver(db, 'd7x');
    await enRoute(db, 'd7', rideId);
    const res = await request(appFor(db, 'd7x'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `bad-${Math.random()}`)
      .send({});
    assert(res.status === 403, `403 got ${res.status}`);
  });

  await test('stale expectedVersion rejected', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p8', 'd8');
    const v = await enRoute(db, 'd8', rideId);
    const res = await request(appFor(db, 'd8'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `stale-${Math.random()}`)
      .send({ expectedVersion: v - 1 });
    assert(res.status === 409, `409 got ${res.status}`);
    assert(res.body.error.code === 'VERSION_CONFLICT', 'code');
  });

  await test('same key different body rejected', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p9', 'd9');
    await enRoute(db, 'd9', rideId);
    const key = `reuse-${Math.random()}`;
    const first = await request(appFor(db, 'd9'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(first.status === 200, 'first');
    // Different body: expectedVersion present vs absent changes hash.
    const second = await request(appFor(db, 'd9'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ expectedVersion: first.body.data.version });
    assert(second.status === 409, `409 got ${second.status}`);
    assert(second.body.error.code === 'IDEMPOTENCY_KEY_REUSED', 'code');
  });

  await test('same key different actor rejected', async () => {
    const db = memoryDb();
    const { rideId } = await seedAssigned(db, 'p10', 'd10');
    seedDriver(db, 'd10b');
    await enRoute(db, 'd10', rideId);
    const key = `actor-${Math.random()}`;
    const first = await request(appFor(db, 'd10'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(first.status === 200, 'first');
    const second = await request(appFor(db, 'd10b'))
      .post(`/v1/rides/${rideId}/arrive`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({});
    assert(second.status === 409 || second.status === 403, `got ${second.status}`);
  });

  console.log(`\nPhase 2L unit proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
