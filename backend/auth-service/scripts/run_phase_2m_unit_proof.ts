/**
 * Standalone Phase 2M unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-2m-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { RideService } from '../src/rides/ride_service';
import { RIDE_NO_SHOW_WAIT_MS } from '../src/rides/types';

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
    internalWorkerToken: WORKER_TOKEN,
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

async function seedToArrived(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  driverId: string,
): Promise<{ rideId: string; version: number; arrivedAt: string }> {
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
  for (const step of ['en-route', 'arrive'] as const) {
    const res = await request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${step}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${step}-${Math.random()}`)
      .send({});
    assert(res.status === 200, `${step} ${res.status}`);
  }
  const ride = db.getDoc('rides', rideId)!;
  assert(ride.state === 'DRIVER_ARRIVED', 'ARRIVED');
  assert(typeof ride.arrivedAt === 'string', 'arrivedAt');
  return {
    rideId,
    version: ride.version as number,
    arrivedAt: ride.arrivedAt as string,
  };
}

function setArrivedAt(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  arrivedAt: string | null,
) {
  const doc = db.getDoc('rides', rideId)!;
  db.seed('rides', rideId, { ...doc, arrivedAt });
}

function countNoShowEvents(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
): number {
  return [...db.store.entries()].filter(
    ([k, v]) =>
      k.startsWith('outboxEvents/') &&
      (v as { eventType?: string; aggregateId?: string }).eventType ===
        'ride.no_show' &&
      (v as { aggregateId?: string }).aggregateId === rideId,
  ).length;
}

function noShowEvent(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
): Record<string, unknown> | null {
  for (const [k, v] of db.store.entries()) {
    if (!k.startsWith('outboxEvents/')) continue;
    const ev = v as {
      eventType?: string;
      aggregateId?: string;
      payload?: Record<string, unknown>;
      causationId?: string;
    };
    if (ev.eventType === 'ride.no_show' && ev.aggregateId === rideId) {
      return ev as Record<string, unknown>;
    }
  }
  return null;
}

async function sweep(db: ReturnType<typeof memoryDb>) {
  return request(workerApp(db))
    .post('/v1/internal/rides/no-show-sweep')
    .set('X-Ora-Worker-Token', WORKER_TOKEN);
}

async function main(): Promise<void> {
  await test('not due (<5m) remains DRIVER_ARRIVED', async () => {
    const db = memoryDb();
    const { rideId } = await seedToArrived(db, 'p0', 'd0');
    setArrivedAt(
      db,
      rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS + 30_000).toISOString(),
    );
    const res = await sweep(db);
    assert(res.status === 200, 'sweep');
    assert(db.getDoc('rides', rideId)!.state === 'DRIVER_ARRIVED', 'state');
    assert(countNoShowEvents(db, rideId) === 0, 'no evt');
  });

  await test('exact 5m boundary becomes NO_SHOW', async () => {
    const db = memoryDb();
    const { rideId, version, arrivedAt: _a } = await seedToArrived(
      db,
      'p1',
      'd1',
    );
    const boundary = new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS).toISOString();
    setArrivedAt(db, rideId, boundary);
    const res = await sweep(db);
    assert(res.status === 200, 'sweep');
    assert(res.body.data.noShowed >= 1, 'noShowed');
    const ride = db.getDoc('rides', rideId)!;
    assert(ride.state === 'NO_SHOW', 'state');
    assert(ride.version === version + 1, 'version');
    assert(ride.arrivedAt === boundary, 'clock preserved');
  });

  await test('older than 5m becomes NO_SHOW + exact payload', async () => {
    const db = memoryDb();
    const { rideId, version } = await seedToArrived(db, 'p2', 'd2');
    const clock = new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 60_000).toISOString();
    setArrivedAt(db, rideId, clock);
    const feeBefore = db.getDoc('rides', rideId)!.cancellationFeeMinor;
    await sweep(db);
    const ride = db.getDoc('rides', rideId)!;
    assert(ride.state === 'NO_SHOW', 'state');
    assert(ride.version === version + 1, 'version');
    assert(ride.arrivedAt === clock, 'arrivedAt');
    assert(ride.cancellationFeeMinor === feeBefore, 'no fee mutation');
    assert(countNoShowEvents(db, rideId) === 1, 'one evt');
    const ev = noShowEvent(db, rideId)!;
    assert(ev.causationId === `no-show:${rideId}`, 'causation');
    const payload = ev.payload as Record<string, unknown>;
    assert(payload.rideId === rideId, 'p.rideId');
    assert(payload.fromState === 'DRIVER_ARRIVED', 'p.from');
    assert(payload.toState === 'NO_SHOW', 'p.to');
    assert(payload.reason === 'arrived_wait_ttl_elapsed', 'p.reason');
    assert(payload.arrivedAt === clock, 'p.arrivedAt');
    assert(payload.passengerId === undefined, 'no passengerId');
    assert(payload.assignedDriverId === undefined, 'no assignedDriverId');
    assert(payload.occurredAt === undefined, 'no occurredAt in payload');
  });

  await test('legacy ARRIVED + null arrivedAt skipped', async () => {
    const db = memoryDb();
    const { rideId, version } = await seedToArrived(db, 'p3', 'd3');
    setArrivedAt(db, rideId, null);
    await sweep(db);
    const ride = db.getDoc('rides', rideId)!;
    assert(ride.state === 'DRIVER_ARRIVED', 'state');
    assert(ride.version === version, 'version');
    assert(ride.arrivedAt == null, 'null clock');
    assert(countNoShowEvents(db, rideId) === 0, 'no evt');
  });

  await test('wrong state skipped (EN_ROUTE)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p4');
    seedDriver(db, 'd4');
    seedPricing(db);
    const create = await request(appFor(db, 'p4'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `c-${Math.random()}`)
      .send(createBody);
    const rideId = create.body.data.rideId as string;
    const offer = await request(appFor(db, 'd4'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `o-${Math.random()}`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    await request(appFor(db, 'p4'))
      .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `s-${Math.random()}`)
      .send({});
    await request(appFor(db, 'd4'))
      .post(`/v1/rides/${rideId}/en-route`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `er-${Math.random()}`)
      .send({});
    const svc = new RideService(db as never);
    const outcome = await svc.markNoShow({
      rideId,
      correlationId: 'x',
    });
    assert(outcome.outcome === 'skipped', 'skipped');
    assert(
      outcome.outcome === 'skipped' && outcome.reason === 'state_DRIVER_EN_ROUTE',
      'reason',
    );
  });

  await test('already NO_SHOW is no-op', async () => {
    const db = memoryDb();
    const { rideId } = await seedToArrived(db, 'p5', 'd5');
    setArrivedAt(
      db,
      rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    const svc = new RideService(db as never);
    const a = await svc.markNoShow({ rideId, correlationId: 'a' });
    const v = db.getDoc('rides', rideId)!.version as number;
    const b = await svc.markNoShow({ rideId, correlationId: 'b' });
    assert(a.outcome === 'no_show', 'first');
    assert(b.outcome === 'already_no_show', 'second');
    assert(db.getDoc('rides', rideId)!.version === v, 'no bump');
    assert(countNoShowEvents(db, rideId) === 1, 'one evt');
  });

  await test('NO_SHOW cannot start or cancel', async () => {
    const db = memoryDb();
    const { rideId } = await seedToArrived(db, 'p6', 'd6');
    setArrivedAt(
      db,
      rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    await sweep(db);
    const start = await request(appFor(db, 'd6'))
      .post(`/v1/rides/${rideId}/start`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `st-${Math.random()}`)
      .send({});
    assert(start.status === 409, `start ${start.status}`);
    const cancel = await request(appFor(db, 'p6'))
      .post(`/v1/rides/${rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `ca-${Math.random()}`)
      .send({});
    assert(cancel.status === 409, `cancel ${cancel.status}`);
    assert(db.getDoc('rides', rideId)!.state === 'NO_SHOW', 'still NO_SHOW');
  });

  await test('noShowCount / drivers unchanged', async () => {
    const db = memoryDb();
    seedDriver(db, 'd7');
    db.seed('drivers', 'd7', {
      driverId: 'd7',
      noShowCount: 3,
      totalRides: 10,
    });
    const { rideId } = await seedToArrived(db, 'p7', 'd7');
    setArrivedAt(
      db,
      rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    await sweep(db);
    assert(db.getDoc('drivers', 'd7')!.noShowCount === 3, 'unchanged');
  });

  await test('worker auth: missing/wrong/user rejected', async () => {
    const db = memoryDb();
    assert(
      (
        await request(workerApp(db)).post('/v1/internal/rides/no-show-sweep')
      ).status === 403,
      'missing token',
    );
    assert(
      (
        await request(workerApp(db))
          .post('/v1/internal/rides/no-show-sweep')
          .set('X-Ora-Worker-Token', 'wrong-token-xxxxx')
      ).status === 403,
      'wrong token',
    );
    assert(
      (
        await request(appFor(db, 'p8'))
          .post('/v1/internal/rides/no-show-sweep')
          .set('Authorization', 'Bearer t')
      ).status === 403,
      'user bearer is not worker token',
    );
  });

  await test('history: NO_SHOW under all only', async () => {
    const db = memoryDb();
    const { rideId } = await seedToArrived(db, 'p9', 'd9');
    setArrivedAt(
      db,
      rideId,
      new Date(Date.now() - RIDE_NO_SHOW_WAIT_MS - 1).toISOString(),
    );
    await sweep(db);
    const all = await request(appFor(db, 'p9'))
      .get('/v1/rides?status=all')
      .set('Authorization', 'Bearer t');
    assert(all.status === 200, 'all');
    assert(
      (all.body.data.rides as Array<{ rideId: string; state: string }>).some(
        (r) => r.rideId === rideId && r.state === 'NO_SHOW',
      ),
      'in all',
    );
    const completed = await request(appFor(db, 'p9'))
      .get('/v1/rides?status=completed')
      .set('Authorization', 'Bearer t');
    assert(
      !(
        completed.body.data.rides as Array<{ rideId: string }>
      ).some((r) => r.rideId === rideId),
      'not completed',
    );
    const cancelled = await request(appFor(db, 'p9'))
      .get('/v1/rides?status=cancelled')
      .set('Authorization', 'Bearer t');
    assert(
      !(
        cancelled.body.data.rides as Array<{ rideId: string }>
      ).some((r) => r.rideId === rideId),
      'not cancelled',
    );
  });

  console.log(`\nPhase 2M unit proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
