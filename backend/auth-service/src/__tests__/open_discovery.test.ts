import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

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

function seedPricing(
  db: ReturnType<typeof memoryDb>,
  id = 'snap-1',
  overrides: Record<string, unknown> = {},
) {
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt,
    inputs: { distanceKm: 5.2, durationMin: 18 },
    ...overrides,
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid,
      phone_number: '+923001111111',
    }),
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

async function createRide(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  idem = 'create-ride-key-001',
) {
  const app = appFor(db, passengerId);
  const res = await request(app)
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(createBody);
  expect(res.status).toBe(201);
  return res.body.data as { rideId: string; version: number; state: string };
}

async function createOffer(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  driverId: string,
  amountMinor: number,
  idem: string,
) {
  const app = appFor(db, driverId);
  return request(app)
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor,
      expectedRequestVersion: 1,
    });
}

describe('Slice M0 open ride discovery', () => {
  const PROHIBITED_OPEN_FIELDS = [
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

  it('approved driver can access open discovery', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-open-1');
    seedOpenRide(db, { rideId: 'r-open-1' });
    const res = await listOpen(db, 'd-open-1');
    expect(res.status).toBe(200);
    expect(res.body.data.rides.map((r: { rideId: string }) => r.rideId)).toContain(
      'r-open-1',
    );
  });

  it('unauthenticated caller rejected', async () => {
    const db = memoryDb();
    seedOpenRide(db, { rideId: 'r-unauth' });
    const app = createApp({
      auth: { verifyIdToken: vi.fn() } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
    const res = await request(app).get('/v1/rides/open');
    expect(res.status).toBe(401);
  });

  it('passenger rejected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-open');
    seedOpenRide(db, { rideId: 'r-pass-deny' });
    const res = await listOpen(db, 'p-open');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');
  });

  it('pending and unapproved drivers rejected', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-pending', { driverStatus: 'pending' });
    seedDriver(db, 'd-none', { driverStatus: 'none' });
    seedOpenRide(db, { rideId: 'r-driver-deny' });
    const pending = await listOpen(db, 'd-pending');
    expect(pending.status).toBe(403);
    expect(pending.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');
    const none = await listOpen(db, 'd-none');
    expect(none.status).toBe(403);
    expect(none.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');
  });

  it('returns SEARCHING unassigned ride', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-search');
    seedOpenRide(db, {
      rideId: 'r-searching',
      state: 'SEARCHING',
      assignedDriverId: null,
    });
    const res = await listOpen(db, 'd-search');
    expect(res.status).toBe(200);
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'r-searching',
    );
    expect(ride?.state).toBe('SEARCHING');
  });

  it('returns OFFERS_AVAILABLE unassigned ride', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-offers');
    seedOpenRide(db, {
      rideId: 'r-offers',
      state: 'OFFERS_AVAILABLE',
      assignedDriverId: null,
    });
    const res = await listOpen(db, 'd-offers');
    expect(res.status).toBe(200);
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'r-offers',
    );
    expect(ride?.state).toBe('OFFERS_AVAILABLE');
  });

  it('excludes assigned rides', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-assigned');
    seedOpenRide(db, {
      rideId: 'r-assigned',
      assignedDriverId: 'd-other',
      state: 'DRIVER_ASSIGNED',
    });
    const res = await listOpen(db, 'd-assigned');
    expect(res.status).toBe(200);
    expect(
      res.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ).not.toContain('r-assigned');
  });

  it('excludes terminal rides', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-term');
    for (const state of ['CANCELLED', 'EXPIRED', 'RIDE_CLOSED', 'NO_SHOW']) {
      seedOpenRide(db, {
        rideId: `r-${state}`,
        state,
        assignedDriverId: null,
      });
    }
    const res = await listOpen(db, 'd-term');
    expect(res.status).toBe(200);
    expect(res.body.data.rides).toEqual([]);
  });

  it('excludes expired rides by server time', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-exp');
    seedOpenRide(db, {
      rideId: 'r-expired',
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
    });
    const res = await listOpen(db, 'd-exp');
    expect(res.status).toBe(200);
    expect(
      res.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ).not.toContain('r-expired');
    expect(db.getDoc('rides', 'r-expired')?.state).toBe('SEARCHING');
  });

  it('excludes unrelated in-progress ride states', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-progress');
    for (const state of [
      'DRIVER_ASSIGNED',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'RIDE_STARTED',
      'RIDE_COMPLETED',
    ]) {
      seedOpenRide(db, {
        rideId: `r-${state}`,
        state,
        assignedDriverId: state === 'DRIVER_ASSIGNED' ? 'd-x' : null,
      });
    }
    const res = await listOpen(db, 'd-progress');
    expect(res.status).toBe(200);
    expect(res.body.data.rides).toEqual([]);
  });

  it('paginates with stable non-duplicated cursors', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-page');
    const ts = '2026-05-01T12:00:00.000Z';
    seedOpenRide(db, { rideId: 'open-a', createdAt: ts });
    seedOpenRide(db, { rideId: 'open-m', createdAt: ts });
    seedOpenRide(db, { rideId: 'open-z', createdAt: ts });

    const page1 = await listOpen(db, 'd-page', { limit: '2' });
    expect(page1.status).toBe(200);
    expect(page1.body.data.rides).toHaveLength(2);
    expect(page1.body.data.nextCursor).toBeTruthy();

    const page2 = await listOpen(db, 'd-page', {
      limit: '2',
      cursor: page1.body.data.nextCursor,
    });
    expect(page2.status).toBe(200);
    expect(page2.body.data.rides).toHaveLength(1);

    const allIds = [
      ...page1.body.data.rides.map((r: { rideId: string }) => r.rideId),
      ...page2.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ];
    expect(new Set(allIds).size).toBe(3);
    expect(allIds.sort()).toEqual(['open-a', 'open-m', 'open-z']);
  });

  it('rejects page size above bounded maximum', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-limit');
    const res = await listOpen(db, 'd-limit', { limit: '51' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('discovery response omits prohibited fields and includes requestVersion', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-dto');
    seedOpenRide(db, { rideId: 'r-dto', requestVersion: 3 });
    const res = await listOpen(db, 'd-dto');
    expect(res.status).toBe(200);
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === 'r-dto',
    );
    expect(ride.requestVersion).toBe(3);
    for (const field of PROHIBITED_OPEN_FIELDS) {
      expect(ride).not.toHaveProperty(field);
    }
    expect(ride.pickup).toEqual({
      lat: 24.86,
      lng: 67.0,
      address: 'Pickup A',
    });
    expect(ride.recommendedFareMinor).toBe(25000);
  });

  it('offer submission works against a discovered ride', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-offer-open');
    seedDriver(db, 'd-offer-open');
    seedPricing(db);
    const created = await createRide(db, 'p-offer-open', 'm0-create-offer');
    const discovery = await listOpen(db, 'd-offer-open');
    expect(discovery.status).toBe(200);
    const found = discovery.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === created.rideId,
    );
    expect(found).toBeTruthy();
    const offer = await createOffer(
      db,
      created.rideId,
      'd-offer-open',
      26000,
      'm0-offer-key',
    );
    expect(offer.status).toBe(201);
    expect(offer.body.data.rideId).toBe(created.rideId);
  });

  it('assignment race remains protected after discovery', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-race-open');
    seedDriver(db, 'd-race-a');
    seedDriver(db, 'd-race-b');
    seedPricing(db);
    const created = await createRide(db, 'p-race-open', 'm0-race-create');
    const discovery = await listOpen(db, 'd-race-a');
    expect(
      discovery.body.data.rides.some(
        (r: { rideId: string }) => r.rideId === created.rideId,
      ),
    ).toBe(true);

    const offerA = await createOffer(
      db,
      created.rideId,
      'd-race-a',
      26000,
      'm0-race-off-a',
    );
    expect(offerA.status).toBe(201);
    const select = await request(appFor(db, 'p-race-open'))
      .post(
        `/v1/rides/${created.rideId}/offers/${offerA.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'm0-race-select')
      .send({});
    expect(select.status).toBe(200);

    const offerB = await createOffer(
      db,
      created.rideId,
      'd-race-b',
      27000,
      'm0-race-off-b',
    );
    expect(offerB.status).toBe(409);
    expect(['ALREADY_ASSIGNED', 'STATE_CONFLICT']).toContain(
      offerB.body.error.code,
    );
  });

  it('GET /v1/rides driver listing unchanged — no unassigned open rides', async () => {
    const db = memoryDb();
    seedDriver(db, 'd-reg');
    seedPassenger(db, 'p-reg');
    seedOpenRide(db, {
      rideId: 'r-unassigned-reg',
      passengerId: 'p-reg',
      state: 'SEARCHING',
      assignedDriverId: null,
    });
    seedOpenRide(db, {
      rideId: 'r-assigned-reg',
      passengerId: 'p-reg',
      assignedDriverId: 'd-reg',
      state: 'DRIVER_ASSIGNED',
    });
    const res = await request(appFor(db, 'd-reg'))
      .get('/v1/rides')
      .set('Authorization', 'Bearer t');
    expect(res.status).toBe(200);
    expect(res.body.data.rides.map((r: { rideId: string }) => r.rideId)).toEqual([
      'r-assigned-reg',
    ]);
  });

  it('GET /v1/rides passenger listing unchanged', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-reg2');
    seedOpenRide(db, {
      rideId: 'r-own-reg',
      passengerId: 'p-reg2',
      state: 'SEARCHING',
    });
    seedOpenRide(db, {
      rideId: 'r-other-reg',
      passengerId: 'p-other',
      state: 'SEARCHING',
    });
    const res = await request(appFor(db, 'p-reg2'))
      .get('/v1/rides')
      .set('Authorization', 'Bearer t');
    expect(res.status).toBe(200);
    expect(res.body.data.rides.map((r: { rideId: string }) => r.rideId)).toEqual([
      'r-own-reg',
    ]);
  });
});
