import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

type Db = ReturnType<typeof memoryDb>;

function authFor(uid: string) {
  return {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid,
      phone_number: '+923001111111',
    }),
  } as never;
}

function appFor(db: Db, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    // These tests exercise the auto-approve path explicitly; the production
    // default is approval-required (DRIVER_AUTO_APPROVE unset).
    driverAutoApprove: true,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

function seedUser(
  db: Db,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: 'User',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedApprovedDriver(db: Db, uid: string, online = false) {
  seedUser(db, uid, {
    role: 'driver',
    driverStatus: 'approved',
    activeMode: 'driver',
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: online ? 'online' : 'offline',
  });
}

function seedRide(
  db: Db,
  rideId: string,
  fields: Record<string, unknown>,
) {
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: null,
    state: 'SEARCHING',
    serviceType: 'ride',
    createdAt: new Date().toISOString(),
    ...fields,
  });
}

const IDEM = 'switch-idem-001';

describe('POST /v1/auth/mode — switch to driver', () => {
  function switchReq(db: Db, uid: string, mode: string, key = IDEM) {
    return request(appFor(db, uid))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ mode });
  }

  it('never-onboarded passenger → DRIVER_ONBOARDING_REQUIRED', async () => {
    const db = memoryDb();
    seedUser(db, 'u1');
    const res = await switchReq(db, 'u1', 'driver');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DRIVER_ONBOARDING_REQUIRED');
  });

  it('pending application → DRIVER_APPROVAL_PENDING', async () => {
    const db = memoryDb();
    seedUser(db, 'u1', { driverStatus: 'pending' });
    const res = await switchReq(db, 'u1', 'driver');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DRIVER_APPROVAL_PENDING');
  });

  it('suspended driver → 403 DRIVER_SUSPENDED', async () => {
    const db = memoryDb();
    seedUser(db, 'u1', { driverStatus: 'suspended' });
    const res = await switchReq(db, 'u1', 'driver');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_SUSPENDED');
  });

  it('approved driver switches to driver mode', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await switchReq(db, 'd1', 'driver');
    expect(res.status).toBe(200);
    expect(res.body.activeMode).toBe('driver');
    expect(res.body.role).toBe('driver');
    expect(db.getDoc('users', 'd1')!.activeMode).toBe('driver');
  });

  it('repairs a legacy approved doc with role=passenger', async () => {
    const db = memoryDb();
    seedUser(db, 'u1', {
      role: 'passenger',
      driverStatus: 'approved',
    });
    const res = await switchReq(db, 'u1', 'driver');
    expect(res.status).toBe(200);
    expect(res.body.role).toBe('driver');
    expect(res.body.activeMode).toBe('driver');
  });

  it('blocks while passenger has a live booking', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'r1', { passengerId: 'd1', state: 'SEARCHING' });
    const res = await switchReq(db, 'd1', 'driver');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ACTIVE_JOB');
    expect(res.body.activeRideId).toBe('r1');
  });

  it('allows switch when passenger rides are all terminal', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'r1', { passengerId: 'd1', state: 'RIDE_CLOSED' });
    seedRide(db, 'r2', { passengerId: 'd1', state: 'CANCELLED' });
    const res = await switchReq(db, 'd1', 'driver');
    expect(res.status).toBe(200);
  });

  it('rejects bad mode + unknown fields + missing key', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const bad = await switchReq(db, 'd1', 'admin');
    expect(bad.status).toBe(400);
    const extra = await request(appFor(db, 'd1'))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', IDEM)
      .send({ mode: 'driver', role: 'driver' });
    expect(extra.status).toBe(400);
    const noKey = await request(appFor(db, 'd1'))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .send({ mode: 'driver' });
    expect(noKey.status).toBe(400);
  });
});

describe('POST /v1/auth/mode — switch to passenger', () => {
  function switchReq(db: Db, uid: string, key = IDEM) {
    return request(appFor(db, uid))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', key)
      .send({ mode: 'passenger' });
  }

  it('takes an online approved driver offline durably', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1', true);
    const res = await switchReq(db, 'd1');
    expect(res.status).toBe(200);
    expect(res.body.activeMode).toBe('passenger');
    expect(res.body.role).toBe('driver'); // capability preserved
    expect(db.getDoc('drivers', 'd1')!.availabilityState).toBe('offline');
  });

  it('blocks while driver has an in-flight assigned ride', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'r1', {
      assignedDriverId: 'd1',
      state: 'DRIVER_EN_ROUTE',
    });
    const res = await switchReq(db, 'd1');
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('ACTIVE_JOB');
    expect(res.body.activeRideId).toBe('r1');
  });

  it('blocks while a courier parcel is in driver custody', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    for (const [i, state] of [
      'RIDE_STARTED',
      'DELIVERY_FAILED',
      'RETURNING',
    ].entries()) {
      seedRide(db, `r${i}`, { assignedDriverId: 'd1', state });
      const res = await switchReq(db, 'd1', `switch-key-${i}`);
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe('ACTIVE_JOB');
      db.store.delete(`rides/r${i}`);
    }
    const ok = await switchReq(db, 'd1', 'switch-key-final');
    expect(ok.status).toBe(200);
  });

  it('allows switch when driver jobs are terminal', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'r1', { assignedDriverId: 'd1', state: 'RIDE_COMPLETED' });
    seedRide(db, 'r2', { assignedDriverId: 'd1', state: 'RETURNED' });
    const res = await switchReq(db, 'd1');
    expect(res.status).toBe(200);
  });

  it('is a no-op for a plain passenger', async () => {
    const db = memoryDb();
    seedUser(db, 'u1');
    const res = await switchReq(db, 'u1');
    expect(res.status).toBe(200);
    expect(res.body.activeMode).toBe('passenger');
    expect(res.body.role).toBe('passenger');
  });
});

describe('GET /v1/rides?as= — dual-role history', () => {
  it('approved driver can list passenger bookings with as=passenger', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'pride', {
      passengerId: 'd1',
      state: 'RIDE_COMPLETED',
      serviceType: 'courier',
    });
    seedRide(db, 'djob', {
      assignedDriverId: 'd1',
      passengerId: 'other',
      state: 'RIDE_COMPLETED',
    });
    const res = await request(appFor(db, 'd1'))
      .get('/v1/rides?as=passenger')
      .set('Authorization', 'Bearer t');
    expect(res.status).toBe(200);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    expect(ids).toEqual(['pride']);
  });

  it('as=driver lists driver jobs', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedRide(db, 'pride', { passengerId: 'd1', state: 'RIDE_COMPLETED' });
    seedRide(db, 'djob', {
      assignedDriverId: 'd1',
      passengerId: 'other',
      state: 'RIDE_COMPLETED',
    });
    const res = await request(appFor(db, 'd1'))
      .get('/v1/rides?as=driver')
      .set('Authorization', 'Bearer t');
    expect(res.status).toBe(200);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    expect(ids).toEqual(['djob']);
  });

  it('non-driver as=driver → 403; bad as → 400', async () => {
    const db = memoryDb();
    seedUser(db, 'u1');
    const forbidden = await request(appFor(db, 'u1'))
      .get('/v1/rides?as=driver')
      .set('Authorization', 'Bearer t');
    expect(forbidden.status).toBe(403);
    const bad = await request(appFor(db, 'u1'))
      .get('/v1/rides?as=admin')
      .set('Authorization', 'Bearer t');
    expect(bad.status).toBe(400);
  });
});

describe('single canonical profile — no duplicates', () => {
  it('re-registering an approved driver does not create or downgrade a doc', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'register_d1')
      .send({});
    expect(res.status).toBe(200);
    const doc = db.getDoc('users', 'd1')!;
    expect(doc.role).toBe('driver');
    expect(doc.driverStatus).toBe('approved');
    expect(doc.activeMode).toBe('driver');
    // One doc keyed by uid — no second profile can exist by construction.
    expect(
      [...(db as unknown as { store: Map<string, unknown> }).store.keys()].filter(
        (k) => k.startsWith('users/'),
      ),
    ).toEqual(['users/d1']);
  });

  it('full journey: register → onboard (auto-approve) → switch → passenger switch', async () => {
    const db = memoryDb();
    seedUser(db, 'u1');

    // 1. Self-registration auto-approves until admin review exists.
    const on = await request(appFor(db, 'u1'))
      .post('/v1/drivers/onboarding')
      .set('Authorization', 'Bearer t')
      .send({
        fullName: 'Journey Driver',
        cnicNumber: '35202-1234567-8',
        homeCity: 'Lahore',
        licenseNumber: 'LHR-123456',
        licenseExpiry: '2099-12-31',
        vehicleCategory: 'zip',
        vehicleMake: 'Toyota',
        vehicleModel: 'Corolla',
        vehicleYear: 2024,
        vehicleColor: 'White',
        plateNumber: 'LEA-1234',
      });
    expect(on.status).toBe(200);
    expect(on.body.data.driverStatus).toBe('approved');

    // 2. Switch to driver.
    const toDriver = await request(appFor(db, 'u1'))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'journey-mode-2')
      .send({ mode: 'driver' });
    expect(toDriver.status).toBe(200);
    expect(toDriver.body.activeMode).toBe('driver');

    // 5. Go online, then switch back — durable offline.
    await request(appFor(db, 'u1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t');
    expect(db.getDoc('drivers', 'u1')!.availabilityState).toBe('online');

    const toPassenger = await request(appFor(db, 'u1'))
      .post('/v1/auth/mode')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'journey-mode-3')
      .send({ mode: 'passenger' });
    expect(toPassenger.status).toBe(200);
    expect(toPassenger.body.activeMode).toBe('passenger');
    expect(db.getDoc('drivers', 'u1')!.availabilityState).toBe('offline');
    // Capability preserved — same uid, same doc.
    expect(db.getDoc('users', 'u1')!.role).toBe('driver');
  });
});
