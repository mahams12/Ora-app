/**
 * Standalone Slice M0 unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-m0-unit-proof
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

function seedPassenger(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: 'Passenger',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923002222222',
    displayName: 'Driver',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedPricing(db: ReturnType<typeof memoryDb>, id = 'snap-1') {
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
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

const PROHIBITED = [
  'passengerId',
  'assignedDriverId',
  'version',
  'pricingSnapshotId',
  'routePolyline',
  'feePolicySnapshot',
  'paymentIntentId',
  'agreedFareMinor',
  'agreedOfferId',
  'agreedFareCurrency',
  'assignedAt',
  'arrivedAt',
  'startedAt',
  'completedAt',
  'closedAt',
  'cancelledBy',
  'cancellationReason',
  'cancellationFeeMinor',
  'updatedAt',
] as const;

function seedOpenRide(
  db: ReturnType<typeof memoryDb>,
  overrides: Record<string, unknown> = {},
) {
  const rideId = (overrides.rideId as string) ?? `open-${Math.random()}`;
  const createdAt =
    (overrides.createdAt as string) ?? new Date().toISOString();
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p-open',
    assignedDriverId: null,
    state: 'SEARCHING',
    version: 1,
    requestVersion: 1,
    category: 'economy',
    serviceType: 'ride',
    pickup: { lat: 24.86, lng: 67.0, address: 'Pickup A' },
    destination: { lat: 24.9, lng: 67.1, address: 'Dest B' },
    routePolyline: 'SECRET_POLY',
    distanceKm: 5,
    estimatedDurationMin: 12,
    pricingSnapshotId: 'snap-secret',
    recommendedFareMinor: 25000,
    passengerOfferMinor: 25000,
    agreedFareMinor: null,
    agreedOfferId: null,
    agreedFareCurrency: null,
    feePolicySnapshot: { secret: true },
    paymentMethod: 'CASH',
    paymentIntentId: 'pi_secret',
    passengerCount: 1,
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
    assignedAt: null,
    startedAt: null,
    completedAt: null,
    closedAt: null,
    cancelledBy: null,
    cancellationReason: null,
    cancellationFeeMinor: 99,
    createdAt,
    updatedAt: createdAt,
    ...overrides,
  });
  return rideId;
}

async function listOpen(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  query: Record<string, string> = {},
) {
  return request(appFor(db, uid))
    .get('/v1/rides/open')
    .query(query)
    .set('Authorization', 'Bearer t');
}

async function main(): Promise<void> {
  await test('approved driver can access endpoint', async () => {
    const db = memoryDb();
    seedDriver(db, 'd1');
    seedOpenRide(db, { rideId: 'r1' });
    const res = await listOpen(db, 'd1');
    assert(res.status === 200, `status ${res.status}`);
    assert(
      res.body.data.rides.some((r: { rideId: string }) => r.rideId === 'r1'),
      'missing ride',
    );
  });

  await test('unauthenticated rejected', async () => {
    const db = memoryDb();
    seedOpenRide(db, { rideId: 'r-unauth' });
    const app = createApp({
      auth: { verifyIdToken: async () => { throw new Error('no auth'); } } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
    const res = await request(app).get('/v1/rides/open');
    assert(res.status === 401, `status ${res.status}`);
  });

  await test('passenger rejected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    const res = await listOpen(db, 'p1');
    assert(res.status === 403, `status ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_ELIGIBLE', 'code');
  });

  await test('pending/unapproved driver rejected', async () => {
    const db = memoryDb();
    seedDriver(db, 'dp', { driverStatus: 'pending' });
    seedDriver(db, 'dn', { driverStatus: 'none' });
    const p = await listOpen(db, 'dp');
    assert(p.status === 403 && p.body.error.code === 'DRIVER_NOT_ELIGIBLE', 'pending');
    const n = await listOpen(db, 'dn');
    assert(n.status === 403 && n.body.error.code === 'DRIVER_NOT_ELIGIBLE', 'none');
  });

  await test('SEARCHING unassigned returned', async () => {
    const db = memoryDb();
    seedDriver(db, 'd2');
    seedOpenRide(db, { rideId: 'rs', state: 'SEARCHING' });
    const res = await listOpen(db, 'd2');
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'rs',
    );
    assert(ride?.state === 'SEARCHING', 'state');
  });

  await test('OFFERS_AVAILABLE unassigned returned', async () => {
    const db = memoryDb();
    seedDriver(db, 'd3');
    seedOpenRide(db, { rideId: 'ro', state: 'OFFERS_AVAILABLE' });
    const res = await listOpen(db, 'd3');
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'ro',
    );
    assert(ride?.state === 'OFFERS_AVAILABLE', 'state');
  });

  await test('assigned ride excluded', async () => {
    const db = memoryDb();
    seedDriver(db, 'd4');
    seedOpenRide(db, {
      rideId: 'ra',
      assignedDriverId: 'd-other',
      state: 'DRIVER_ASSIGNED',
    });
    const res = await listOpen(db, 'd4');
    assert(
      !res.body.data.rides.some((r: { rideId: string }) => r.rideId === 'ra'),
      'assigned leaked',
    );
  });

  await test('terminal rides excluded', async () => {
    const db = memoryDb();
    seedDriver(db, 'd5');
    for (const state of ['CANCELLED', 'EXPIRED', 'RIDE_CLOSED', 'NO_SHOW']) {
      seedOpenRide(db, { rideId: `rt-${state}`, state });
    }
    const res = await listOpen(db, 'd5');
    assert(res.body.data.rides.length === 0, 'terminal leaked');
  });

  await test('expired ride excluded without mutation', async () => {
    const db = memoryDb();
    seedDriver(db, 'd6');
    seedOpenRide(db, {
      rideId: 're',
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });
    const res = await listOpen(db, 'd6');
    assert(
      !res.body.data.rides.some((r: { rideId: string }) => r.rideId === 're'),
      'expired leaked',
    );
    assert(db.getDoc('rides', 're')?.state === 'SEARCHING', 'state mutated');
  });

  await test('unrelated in-progress states excluded', async () => {
    const db = memoryDb();
    seedDriver(db, 'd7');
    for (const state of [
      'DRIVER_ASSIGNED',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'RIDE_STARTED',
      'RIDE_COMPLETED',
    ]) {
      seedOpenRide(db, {
        rideId: `rp-${state}`,
        state,
        assignedDriverId: state === 'DRIVER_ASSIGNED' ? 'dx' : null,
      });
    }
    const res = await listOpen(db, 'd7');
    assert(res.body.data.rides.length === 0, 'progress leaked');
  });

  await test('pagination stable and non-duplicated', async () => {
    const db = memoryDb();
    seedDriver(db, 'd8');
    const ts = '2026-05-01T12:00:00.000Z';
    seedOpenRide(db, { rideId: 'open-a', createdAt: ts });
    seedOpenRide(db, { rideId: 'open-m', createdAt: ts });
    seedOpenRide(db, { rideId: 'open-z', createdAt: ts });
    const p1 = await listOpen(db, 'd8', { limit: '2' });
    assert(p1.body.data.rides.length === 2, 'page1 count');
    assert(p1.body.data.nextCursor, 'cursor');
    const p2 = await listOpen(db, 'd8', {
      limit: '2',
      cursor: p1.body.data.nextCursor,
    });
    const ids = [
      ...p1.body.data.rides.map((r: { rideId: string }) => r.rideId),
      ...p2.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ];
    assert(new Set(ids).size === 3, 'duplicates');
    assert(ids.sort().join(',') === 'open-a,open-m,open-z', 'order');
  });

  await test('page size bounded', async () => {
    const db = memoryDb();
    seedDriver(db, 'd9');
    const res = await listOpen(db, 'd9', { limit: '51' });
    assert(res.status === 400, `status ${res.status}`);
    assert(res.body.error.code === 'VALIDATION_ERROR', 'code');
  });

  await test('privacy DTO and requestVersion present', async () => {
    const db = memoryDb();
    seedDriver(db, 'd10');
    seedOpenRide(db, { rideId: 'rdto', requestVersion: 3 });
    const res = await listOpen(db, 'd10');
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'rdto',
    );
    assert(ride.requestVersion === 3, 'requestVersion');
    for (const field of PROHIBITED) {
      assert(!(field in ride), `${field} leaked`);
    }
  });

  await test('offer works against discovered ride', async () => {
    const db = memoryDb();
    seedPassenger(db, 'pp');
    seedDriver(db, 'dd');
    seedPricing(db);
    const create = await request(appFor(db, 'pp'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-create')
      .send(createBody);
    assert(create.status === 201, 'create');
    const rideId = create.body.data.rideId as string;
    const discovery = await listOpen(db, 'dd');
    assert(
      discovery.body.data.rides.some(
        (r: { rideId: string }) => r.rideId === rideId,
      ),
      'not discovered',
    );
    const offer = await request(appFor(db, 'dd'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-offer')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    assert(offer.status === 201, `offer ${offer.status}`);
  });

  await test('assignment race protected after discovery', async () => {
    const db = memoryDb();
    seedPassenger(db, 'pr');
    seedDriver(db, 'da');
    seedDriver(db, 'db');
    seedPricing(db);
    const create = await request(appFor(db, 'pr'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-race-create')
      .send(createBody);
    const rideId = create.body.data.rideId as string;
    const offerA = await request(appFor(db, 'da'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-race-a')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    assert(offerA.status === 201, 'offerA');
    const select = await request(appFor(db, 'pr'))
      .post(`/v1/rides/${rideId}/offers/${offerA.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-race-select')
      .send({});
    assert(select.status === 200, 'select');
    const offerB = await request(appFor(db, 'db'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-race-b')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 27000,
        expectedRequestVersion: 1,
      });
    assert(offerB.status === 409, `offerB ${offerB.status}`);
    assert(
      offerB.body.error.code === 'ALREADY_ASSIGNED' ||
        offerB.body.error.code === 'STATE_CONFLICT',
      `code ${offerB.body.error.code}`,
    );
  });

  await test('GET /v1/rides driver listing unchanged', async () => {
    const db = memoryDb();
    seedDriver(db, 'dr');
    seedPassenger(db, 'pr2');
    seedOpenRide(db, {
      rideId: 'ru',
      passengerId: 'pr2',
      state: 'SEARCHING',
      assignedDriverId: null,
    });
    seedOpenRide(db, {
      rideId: 'ra2',
      passengerId: 'pr2',
      assignedDriverId: 'dr',
      state: 'DRIVER_ASSIGNED',
    });
    const res = await request(appFor(db, 'dr'))
      .get('/v1/rides')
      .set('Authorization', 'Bearer t');
    assert(
      res.body.data.rides.map((r: { rideId: string }) => r.rideId).join(',') ===
        'ra2',
      'driver list changed',
    );
  });

  await test('GET /v1/rides passenger listing unchanged', async () => {
    const db = memoryDb();
    seedPassenger(db, 'pp2');
    seedOpenRide(db, { rideId: 'own', passengerId: 'pp2' });
    seedOpenRide(db, { rideId: 'other', passengerId: 'px' });
    const res = await request(appFor(db, 'pp2'))
      .get('/v1/rides')
      .set('Authorization', 'Bearer t');
    assert(
      res.body.data.rides.map((r: { rideId: string }) => r.rideId).join(',') ===
        'own',
      'passenger list changed',
    );
  });

  console.log(`\nSlice M0 unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
