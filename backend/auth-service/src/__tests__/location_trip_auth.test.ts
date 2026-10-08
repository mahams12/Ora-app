/**
 * L2 Step 1 — trip-mode location authorization (vitest).
 * Exercises LocationUpdateService via HTTP; does not mock the auth gate.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

function seedRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: 'd1',
    state: 'DRIVER_ASSIGNED',
    ...overrides,
  });
}

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  return createApp({
    auth: {
      verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

function body(overrides: Record<string, unknown> = {}) {
  return {
    locationSeq: 1,
    locationStreamId: 'stream-a',
    lat: 31.52,
    lng: 74.35,
    accuracy: 8,
    heading: 90,
    speed: 20,
    timestamp: new Date().toISOString(),
    provider: 'gps',
    ...overrides,
  };
}

describe('L2 Step 1 — trip location authorization', () => {
  for (const state of [
    'DRIVER_ASSIGNED',
    'DRIVER_EN_ROUTE',
    'DRIVER_ARRIVED',
    'RIDE_STARTED',
  ] as const) {
    it(`accepts assigned driver in ${state}`, async () => {
      const db = memoryDb();
      seedApprovedOnline(db, 'd1');
      seedRide(db, 'ride-1', { state, assignedDriverId: 'd1' });
      const res = await request(appFor(db, 'd1'))
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(body({ rideId: 'ride-1' }));
      expect(res.status).toBe(200);
      expect(res.body.data.mode).toBe('trip');
      expect(res.body.data.driverId).toBe('d1');
      expect(db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq).toBe(1);
    });
  }

  it('rejects driver not assigned to the ride', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedApprovedOnline(db, 'd2');
    seedRide(db, 'ride-1', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd2',
    });
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('RIDE_LOCATION_FORBIDDEN');
    expect(db.getDoc('locationStreams', 'ride-1_d1')).toBeUndefined();
  });

  it('rejects cross-ride publish (assigned to A, body ride B)', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedApprovedOnline(db, 'd2');
    seedRide(db, 'ride-a', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd1',
    });
    seedRide(db, 'ride-b', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd2',
    });
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-b' }));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('RIDE_LOCATION_FORBIDDEN');
    expect(db.getDoc('locationStreams', 'ride-b_d1')).toBeUndefined();
    expect(db.getDoc('locationStreams', 'ride-a_d1')).toBeUndefined();
  });

  for (const state of [
    'SEARCHING',
    'OFFERS_AVAILABLE',
    'EXPIRED',
    'CANCELLED',
    'NO_SHOW',
    'RIDE_COMPLETED',
    'RIDE_CLOSED',
  ] as const) {
    it(`rejects ${state} even if assignedDriverId matches`, async () => {
      const db = memoryDb();
      seedApprovedOnline(db, 'd1');
      seedRide(db, 'ride-1', { state, assignedDriverId: 'd1' });
      const res = await request(appFor(db, 'd1'))
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(body({ rideId: 'ride-1' }));
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('RIDE_LOCATION_FORBIDDEN');
      expect(db.getDoc('locationStreams', 'ride-1_d1')).toBeUndefined();
    });
  }

  it('body driverId cannot override auth.uid', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedApprovedOnline(db, 'd2');
    seedRide(db, 'ride-d1', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd1',
    });
    seedRide(db, 'ride-d2', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd2',
    });

    const ok = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-d1', driverId: 'd2' }));
    expect(ok.status).toBe(200);
    expect(ok.body.data.driverId).toBe('d1');
    expect(db.getDoc('locationStreams', 'ride-d1_d1')).toBeDefined();
    expect(db.getDoc('locationStreams', 'ride-d1_d2')).toBeUndefined();

    const cross = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-d2', driverId: 'd2' }));
    expect(cross.status).toBe(403);
    expect(cross.body.error.code).toBe('RIDE_LOCATION_FORBIDDEN');
    expect(db.getDoc('locationStreams', 'ride-d2_d1')).toBeUndefined();
    expect(db.getDoc('locationStreams', 'ride-d2_d2')).toBeUndefined();
  });

  it('idle/no-ride path remains unchanged', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ locationSeq: 4 }));
    expect(res.status).toBe(200);
    expect(res.body.data.mode).toBe('idle');
    expect(res.body.data.rideId).toBeNull();
    expect(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq).toBe(4);
  });

  it('missing ride document is forbidden and does not create cursor', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'missing' }));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('RIDE_LOCATION_FORBIDDEN');
    expect(db.getDoc('locationStreams', 'missing_d1')).toBeUndefined();
  });
});
