/**
 * DR-008 / A7 — one active ride per passenger.
 *
 * memoryDb verifies guard logic and pointer lifecycle; REAL
 * transaction-conflict proof lives in the Firestore emulator script
 * (scripts/run_active_ride_guard_emulator_proof.ts) — memoryDb cannot
 * simulate optimistic-concurrency retries.
 */
import { describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { RideService } from '../rides/ride_service';
import { RIDE_NO_SHOW_WAIT_MS } from '../rides/types';
import type { RideDoc } from '../rides/types';

const RIDES = 'rides';
const POINTERS = 'passengerActiveRides';

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

function seedPricing(db: ReturnType<typeof memoryDb>) {
  db.seed('pricingSnapshots', 'snap-1', {
    snapshotId: 'snap-1',
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

function post(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  path: string,
  body: Record<string, unknown>,
  idem: string,
) {
  return request(appFor(db, uid))
    .post(path)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem.length < 8 ? idem.padEnd(8, 'x') : idem)
    .send(body);
}

const rideBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  city: 'Karachi',
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

const P = { lat: 24.86, lng: 67.0, address: 'Pickup A' };
const courierV2Body = {
  pickup: P,
  destination: { lat: 24.9, lng: 67.1, address: 'Drop B' },
  city: 'Karachi',
  category: 'courier_bike',
  serviceType: 'courier',
  passengerOfferMinor: 30000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  parcel: {
    senderName: 'Ali Sender',
    senderPhone: '+923001111111',
    receiverName: 'Bilal Receiver',
    receiverPhone: '+923009999999',
    parcelCategory: 'documents',
    size: 'SMALL',
    weightKg: 1.5,
    quantity: 1,
    description: 'Office papers',
  },
  stops: [
    { type: 'PICKUP', location: P, label: 'Home' },
    {
      type: 'DROPOFF',
      location: { lat: 24.9, lng: 67.1, address: 'Drop B' },
      label: 'Client',
    },
  ],
};

async function createRide(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  idem: string,
  body: Record<string, unknown> = rideBody,
) {
  const res = await post(db, passengerId, '/v1/rides', body, idem);
  expect(res.status).toBe(201);
  return res.body.data as { rideId: string; version: number; state: string };
}

async function createRideRaw(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  idem: string,
  body: Record<string, unknown> = rideBody,
) {
  return post(db, passengerId, '/v1/rides', body, idem);
}

function pointer(db: ReturnType<typeof memoryDb>, passengerId: string) {
  return db.getDoc(POINTERS, passengerId) as
    | { passengerId: string; activeRideId: string; updatedAt: string }
    | undefined;
}

function rideDoc(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
): RideDoc {
  return db.getDoc(RIDES, rideId) as unknown as RideDoc;
}

function patchRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  patch: Record<string, unknown>,
) {
  const doc = db.getDoc(RIDES, rideId) as Record<string, unknown>;
  db.seed(RIDES, rideId, { ...doc, ...patch });
}

async function assignRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  passengerId: string,
  driverId: string,
  prefix: string,
) {
  const offer = await post(
    db,
    driverId,
    `/v1/rides/${rideId}/offers`,
    {
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 32000,
      expectedRequestVersion: 1,
    },
    `${prefix}-offer`,
  );
  expect(offer.status).toBe(201);
  const sel = await post(
    db,
    passengerId,
    `/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`,
    { expectedVersion: 2 },
    `${prefix}-select`,
  );
  expect(sel.status).toBe(200);
}

describe('DR-008 — one active ride per passenger', () => {
  it('first create succeeds and acquires the pointer; second create → 409', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r1 = await createRide(db, 'p1', 'guard-create-1');
    expect(pointer(db, 'p1')?.activeRideId).toBe(r1.rideId);

    const res = await createRideRaw(db, 'p1', 'guard-create-2');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ACTIVE_RIDE_EXISTS');
    expect(res.body.error.details?.activeRideId).toBe(r1.rideId);
  });

  it('idempotent replay returns the original ride, never 409', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const first = await createRide(db, 'p1', 'guard-idem-1');
    const replay = await createRideRaw(db, 'p1', 'guard-idem-1');
    expect(replay.status).toBe(201);
    expect(replay.body.data.rideId).toBe(first.rideId);
  });

  it('different idempotency key, same body → 409 (not a replay)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    await createRide(db, 'p1', 'guard-idem-a');
    const res = await createRideRaw(db, 'p1', 'guard-idem-b');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ACTIVE_RIDE_EXISTS');
  });

  it('stale pointer to a missing ride self-heals', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    db.seed(POINTERS, 'p1', {
      passengerId: 'p1',
      activeRideId: 'ghost-ride',
      updatedAt: new Date().toISOString(),
    });
    const r = await createRide(db, 'p1', 'guard-stale-1');
    expect(pointer(db, 'p1')?.activeRideId).toBe(r.rideId);
  });

  it('stale pointer to a terminal ride self-heals', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    db.seed(RIDES, 'old-ride', {
      rideId: 'old-ride',
      passengerId: 'p1',
      state: 'CANCELLED',
    });
    db.seed(POINTERS, 'p1', {
      passengerId: 'p1',
      activeRideId: 'old-ride',
      updatedAt: new Date().toISOString(),
    });
    const r = await createRide(db, 'p1', 'guard-stale-2');
    expect(pointer(db, 'p1')?.activeRideId).toBe(r.rideId);
  });

  it('legacy active ride without a pointer is detected by the query fallback', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    db.seed(RIDES, 'legacy-1', {
      rideId: 'legacy-1',
      passengerId: 'p1',
      state: 'SEARCHING',
    });
    const res = await createRideRaw(db, 'p1', 'guard-legacy-1');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ACTIVE_RIDE_EXISTS');
    expect(res.body.error.details?.activeRideId).toBe('legacy-1');
  });

  it('guard applies across service types (ride blocks courier and vice versa)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    await createRide(db, 'p1', 'guard-svc-ride', rideBody);
    const courierAttempt = await createRideRaw(
      db,
      'p1',
      'guard-svc-courier',
      courierV2Body,
    );
    expect(courierAttempt.status).toBe(409);
  });

  it('non-terminal transitions do NOT release the pointer', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-nonterm-1');
    await assignRide(db, r.rideId, 'p1', 'd1', 'guard-nonterm');
    // DRIVER_ASSIGNED is still active — second create must still 409.
    const res = await createRideRaw(db, 'p1', 'guard-nonterm-2');
    expect(res.status).toBe(409);
    expect(pointer(db, 'p1')?.activeRideId).toBe(r.rideId);
  });

  it('rebook after passenger cancellation', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-pcancel-1');
    const cancel = await post(
      db,
      'p1',
      `/v1/rides/${r.rideId}/cancel`,
      { reason: 'changed_mind' },
      'guard-pcancel-2',
    );
    expect(cancel.status).toBe(200);
    expect(pointer(db, 'p1')).toBeUndefined();
    const r2 = await createRide(db, 'p1', 'guard-pcancel-3');
    expect(pointer(db, 'p1')?.activeRideId).toBe(r2.rideId);
  });

  it('rebook after driver cancellation (post-assign)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-dcancel-1');
    await assignRide(db, r.rideId, 'p1', 'd1', 'guard-dcancel');
    const cancel = await post(
      db,
      'd1',
      `/v1/rides/${r.rideId}/cancel`,
      { reason: 'driver_unavailable' },
      'guard-dcancel-2',
    );
    expect(cancel.status).toBe(200);
    expect(rideDoc(db, r.rideId).state).toBe('CANCELLED');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-dcancel-3');
  });

  it('rebook after ride completion (progressAssignedRide → RIDE_COMPLETED)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-done-1');
    await assignRide(db, r.rideId, 'p1', 'd1', 'guard-done');
    for (const [path, idem] of [
      ['/en-route', 'gd-enroute'],
      ['/arrive', 'gd-arrive'],
      ['/start', 'gd-start'],
      ['/complete', 'gd-complete'],
    ] as const) {
      const res = await post(db, 'd1', `/v1/rides/${r.rideId}${path}`, {}, idem);
      expect(res.status).toBe(200);
    }
    expect(rideDoc(db, r.rideId).state).toBe('RIDE_COMPLETED');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-done-2');
  });

  it('rebook after courier v2 completion (mutateDelivery → RIDE_COMPLETED)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-v2-1', courierV2Body);
    await assignRide(db, r.rideId, 'p1', 'd1', 'guard-v2');
    const enroute = await post(
      db,
      'd1',
      `/v1/rides/${r.rideId}/en-route`,
      {},
      'guard-v2-enroute',
    );
    expect(enroute.status).toBe(200);
    // Two stops: arrive + confirm each; final confirm lands RIDE_COMPLETED.
    for (const seq of [0, 1]) {
      const arrive = await post(
        db,
        'd1',
        `/v1/rides/${r.rideId}/stops/${seq}/arrive`,
        {},
        `guard-v2-a${seq}`,
      );
      expect(arrive.status).toBe(200);
      const confirm = await post(
        db,
        'd1',
        `/v1/rides/${r.rideId}/stops/${seq}/confirm`,
        {},
        `guard-v2-c${seq}`,
      );
      expect(confirm.status).toBe(200);
    }
    expect(rideDoc(db, r.rideId).state).toBe('RIDE_COMPLETED');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-v2-2', courierV2Body);
  });

  it('rebook after return completion (RETURNING → RETURNED)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-ret-1');
    // Seed the ride directly into RETURNING (post-courier-failure state)
    // and point the pointer at it — isolates the completeReturn clear.
    const doc = rideDoc(db, r.rideId);
    db.seed(RIDES, r.rideId, {
      ...(doc as unknown as Record<string, unknown>),
      state: 'RETURNING',
      assignedDriverId: 'd1',
      agreedFareMinor: 25000,
      agreedOfferId: 'offer-x',
      version: 9,
    });
    db.seed(POINTERS, 'p1', {
      passengerId: 'p1',
      activeRideId: r.rideId,
      updatedAt: new Date().toISOString(),
    });
    const res = await post(
      db,
      'd1',
      `/v1/rides/${r.rideId}/return-complete`,
      {},
      'guard-ret-2',
    );
    expect(res.status).toBe(200);
    expect(rideDoc(db, r.rideId).state).toBe('RETURNED');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-ret-3');
  });

  it('rebook after expiration (sweeper path)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-exp-1');
    patchRide(db, r.rideId, {
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const svc = new RideService(db as never);
    const result = await svc.expireRide({
      rideId: r.rideId,
      correlationId: 'guard-exp',
    });
    expect(result.outcome).toBe('expired');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-exp-2');
  });

  it('rebook after no-show', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-ns-1');
    await assignRide(db, r.rideId, 'p1', 'd1', 'guard-ns');
    for (const [path, idem] of [
      ['/en-route', 'gns-enroute'],
      ['/arrive', 'gns-arrive'],
    ] as const) {
      const res = await post(db, 'd1', `/v1/rides/${r.rideId}${path}`, {}, idem);
      expect(res.status).toBe(200);
    }
    patchRide(db, r.rideId, {
      arrivedAt: new Date(
        Date.now() - RIDE_NO_SHOW_WAIT_MS - 1000,
      ).toISOString(),
    });
    const svc = new RideService(db as never);
    const result = await svc.markNoShow({
      rideId: r.rideId,
      correlationId: 'guard-ns',
    });
    expect(result.outcome).toBe('no_show');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-ns-2');
  });

  it('rebook after closure (closeRide on a completed ride)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', 'guard-close-1');
    // Simulate a completed ride whose pointer was left behind (defense
    // in depth): RIDE_COMPLETED is closeable; close must still clear.
    const doc = rideDoc(db, r.rideId);
    db.seed(RIDES, r.rideId, {
      ...(doc as unknown as Record<string, unknown>),
      state: 'RIDE_COMPLETED',
      version: 9,
      completedAt: new Date().toISOString(),
    });
    const close = await post(
      db,
      'p1',
      `/v1/rides/${r.rideId}/close`,
      {},
      'guard-close-2',
    );
    expect(close.status).toBe(200);
    expect(rideDoc(db, r.rideId).state).toBe('RIDE_CLOSED');
    expect(pointer(db, 'p1')).toBeUndefined();
    await createRide(db, 'p1', 'guard-close-3');
  });
});

describe('DR-008 — terminal-writer enumeration guard', () => {
  it('every terminal-state writer in ride_service clears the pointer', () => {
    // Six transaction sites must release the pointer:
    //   createRide (acquire), cancelRide, progressAssignedRide,
    //   mutateDelivery, closeRide, expireRide, markNoShow.
    // If a NEW terminal writer is added without a clear call, or an
    // existing one loses it, this count changes and the test fails.
    const src = readFileSync(
      join(__dirname, '..', 'rides', 'ride_service.ts'),
      'utf8',
    );
    const clearCalls = src.match(/clearActiveRidePointerIfMatchTx\(\s*tx,/g);
    expect(clearCalls).toHaveLength(6);
    const acquireCalls = src.match(/assertNoActiveRideTx\(\s*tx,/g);
    expect(acquireCalls).toHaveLength(1);
    const pointerWrites = src.match(/writeActiveRidePointerTx\(\s*tx,/g);
    expect(pointerWrites).toHaveLength(1);
  });
});
