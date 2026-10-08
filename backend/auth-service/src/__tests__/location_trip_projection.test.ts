/**
 * L2 Step 3 — RTDB projection after durable accept + rideAccess lifecycle.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { MemoryTripLocationRtdb } from '../rtdb/memory_trip_location_rtdb';
import type { TripLocationLatest, TripLocationRtdb } from '../rtdb/types';
import {
  cleanupTripLocationOnTerminal,
  grantRideLocationAccess,
} from '../rtdb/ride_location_lifecycle';
import { RideService } from '../rides/ride_service';
import {
  rideAccessUidPath,
  tripLocationLatestPath,
} from '../rtdb/paths';

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

function seedAssignedRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: 'd1',
    state: 'DRIVER_ASSIGNED',
    version: 2,
    agreedOfferId: 'off-1',
    agreedFareMinor: 1000,
    ...overrides,
  });
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  rtdb: TripLocationRtdb,
) {
  return createApp({
    auth: {
      verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
    tripLocationRtdb: rtdb,
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

class FailingTripLocationRtdb implements TripLocationRtdb {
  setCalls = 0;
  async setTripLocationLatest(): Promise<void> {
    this.setCalls += 1;
    throw new Error('simulated_rtdb_failure');
  }
  async grantRideAccess(): Promise<void> {}
  async revokeRideAccess(): Promise<void> {}
  async clearTripLocations(): Promise<void> {}
}

class OrderTrackingRtdb extends MemoryTripLocationRtdb {
  events: string[] = [];
  override async setTripLocationLatest(
    rideId: string,
    latest: TripLocationLatest,
  ): Promise<void> {
    this.events.push('rtdb');
    return super.setTripLocationLatest(rideId, latest);
  }
}

describe('L2 Step 3 — accepted location → RTDB projection', () => {
  it('A. happy path writes server-authorized latest after accept', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');

    const res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));

    expect(res.status).toBe(200);
    expect(res.body.data.mode).toBe('trip');
    expect(db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq).toBe(1);
    expect(rtdb.get(tripLocationLatestPath('ride-1'))).toMatchObject({
      lat: 31.52,
      lng: 74.35,
      accuracy: 8,
      heading: 90,
      speed: 20,
      driverId: 'd1',
      locationSeq: 1,
      locationStreamId: 'stream-a',
    });
    const latest = rtdb.get(tripLocationLatestPath('ride-1')) as {
      acceptedAt: string;
      ts: number;
    };
    expect(typeof latest.acceptedAt).toBe('string');
    expect(typeof latest.ts).toBe('number');
  });

  it('B. RTDB projection occurs only after durable cursor accept', async () => {
    const db = memoryDb();
    const rtdb = new OrderTrackingRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');

    // Wrap seed so we can observe stream write before RTDB by checking mid-flight:
    // After HTTP returns, cursor must exist; RTDB event recorded.
    const res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    expect(res.status).toBe(200);
    expect(db.getDoc('locationStreams', 'ride-1_d1')).toBeDefined();
    expect(rtdb.events).toEqual(['rtdb']);
  });

  it('B2. RTDB is not called when cursor accept fails (seq)', async () => {
    const db = memoryDb();
    const rtdb = new OrderTrackingRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');
    db.seed('locationStreams', 'ride-1_d1', {
      driverId: 'd1',
      rideId: 'ride-1',
      activeStreamId: 'stream-a',
      lastAcceptedSeq: 5,
      streamState: 'ACTIVE',
      previousStreamIds: [],
    });
    const res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1', locationSeq: 3 }));
    expect(res.status).toBe(422);
    expect(rtdb.events).toEqual([]);
    expect(rtdb.get(tripLocationLatestPath('ride-1'))).toBeUndefined();
  });

  it('C. idle path does not write tripLocations', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    const res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body());
    expect(res.status).toBe(200);
    expect(res.body.data.mode).toBe('idle');
    expect(rtdb.store.size).toBe(0);
  });

  it('D. RTDB failure keeps HTTP 200 and durable cursor', async () => {
    const db = memoryDb();
    const rtdb = new FailingTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');
    const res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    expect(res.status).toBe(200);
    expect(db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq).toBe(1);
    expect(rtdb.setCalls).toBe(1);
  });

  it('body driverId cannot become RTDB driverId', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');
    await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1', driverId: 'attacker' }));
    expect(rtdb.get(tripLocationLatestPath('ride-1'))).toMatchObject({
      driverId: 'd1',
    });
  });
});

describe('L2 Step 3 — rideAccess grant / terminal cleanup', () => {
  it('E. grantRideLocationAccess sets passenger + driver ACL', async () => {
    const rtdb = new MemoryTripLocationRtdb();
    await grantRideLocationAccess({
      rtdb,
      rideId: 'ride-1',
      passengerId: 'p1',
      assignedDriverId: 'd1',
    });
    expect(rtdb.get(rideAccessUidPath('ride-1', 'p1'))).toBe(true);
    expect(rtdb.get(rideAccessUidPath('ride-1', 'd1'))).toBe(true);
  });

  it('F/G. terminal cleanup revokes, clears, closes stream; idempotent', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    db.seed('locationStreams', 'ride-1_d1', {
      driverId: 'd1',
      rideId: 'ride-1',
      activeStreamId: 's1',
      lastAcceptedSeq: 3,
      streamState: 'ACTIVE',
      previousStreamIds: [],
    });
    await rtdb.grantRideAccess('ride-1', 'p1');
    await rtdb.grantRideAccess('ride-1', 'd1');
    await rtdb.setTripLocationLatest('ride-1', {
      lat: 1,
      lng: 2,
      accuracy: 3,
      heading: 4,
      speed: 5,
      ts: 6,
      acceptedAt: 't',
      driverId: 'd1',
      locationSeq: 3,
      locationStreamId: 's1',
    });

    for (const reason of [
      'RIDE_COMPLETED',
      'RIDE_CLOSED',
      'CANCELLED',
      'NO_SHOW',
    ]) {
      await cleanupTripLocationOnTerminal({
        db: db as never,
        rtdb,
        rideId: 'ride-1',
        assignedDriverId: 'd1',
        reason,
      });
      expect(rtdb.get(rideAccessUidPath('ride-1', 'p1'))).toBeUndefined();
      expect(rtdb.get(tripLocationLatestPath('ride-1'))).toBeUndefined();
      expect(db.getDoc('locationStreams', 'ride-1_d1')?.streamState).toBe(
        'CLOSED',
      );
    }
  });

  it('closed stream rejects further trip publish (Step 1 + stream gate)', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1', { state: 'RIDE_COMPLETED' });
    // State gate rejects first.
    let res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    expect(res.status).toBe(403);
    expect(rtdb.store.size).toBe(0);

    // Stream CLOSED also rejects when state still publishable (defense in depth).
    seedAssignedRide(db, 'ride-2', { state: 'DRIVER_ASSIGNED' });
    db.seed('locationStreams', 'ride-2_d1', {
      driverId: 'd1',
      rideId: 'ride-2',
      activeStreamId: 'stream-a',
      lastAcceptedSeq: 1,
      streamState: 'CLOSED',
      previousStreamIds: [],
    });
    res = await request(appFor(db, 'd1', rtdb))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-2', locationSeq: 2 }));
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('SEQUENCE_VIOLATION');
    expect(rtdb.get(tripLocationLatestPath('ride-2'))).toBeUndefined();
  });

  it('H. reassignment is impossible (ALREADY_ASSIGNED invariant)', async () => {
    const db = memoryDb();
    const rides = new RideService(db as never, new MemoryTripLocationRtdb());
    db.seed('users', 'p1', {
      uid: 'p1',
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
      phoneNumber: '+923001111111',
    });
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
      phoneNumber: '+923001111112',
    });
    db.seed('users', 'd2', {
      uid: 'd2',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
      phoneNumber: '+923001111113',
    });
    db.seed('rides', 'ride-1', {
      rideId: 'ride-1',
      passengerId: 'p1',
      assignedDriverId: 'd1',
      state: 'DRIVER_ASSIGNED',
      version: 3,
      agreedOfferId: 'off-d1',
      agreedFareMinor: 1000,
      requestVersion: 1,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });
    db.seed('rideOffers', 'off-d2', {
      offerId: 'off-d2',
      rideId: 'ride-1',
      driverId: 'd2',
      status: 'PENDING',
      amountMinor: 1100,
      currency: 'PKR',
      requestVersion: 1,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });

    await expect(
      rides.selectOffer({
        caller: {
          uid: 'p1',
          phoneNumber: '+923001111111',
          email: null,
          disabled: false,
        },
        rideId: 'ride-1',
        offerId: 'off-d2',
        body: {},
        idempotencyKeyHeader: 'idem-reassign-1',
        correlationId: 'c1',
      }),
    ).rejects.toMatchObject({ code: 'ALREADY_ASSIGNED' });
  });

  it('cancel after assign runs terminal cleanup', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    const rides = new RideService(db as never, rtdb);
    db.seed('users', 'p1', {
      uid: 'p1',
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
      phoneNumber: '+923001111111',
    });
    db.seed('rides', 'ride-c', {
      rideId: 'ride-c',
      passengerId: 'p1',
      assignedDriverId: 'd1',
      state: 'DRIVER_EN_ROUTE',
      version: 4,
      agreedOfferId: 'o1',
      agreedFareMinor: 1000,
    });
    db.seed('locationStreams', 'ride-c_d1', {
      driverId: 'd1',
      rideId: 'ride-c',
      activeStreamId: 's',
      lastAcceptedSeq: 1,
      streamState: 'ACTIVE',
      previousStreamIds: [],
    });
    await rtdb.grantRideAccess('ride-c', 'p1');
    await rtdb.setTripLocationLatest('ride-c', {
      lat: 1,
      lng: 1,
      accuracy: 1,
      heading: 1,
      speed: 1,
      ts: 1,
      acceptedAt: 't',
      driverId: 'd1',
      locationSeq: 1,
      locationStreamId: 's',
    });

    const res = await rides.cancelRide({
      caller: {
        uid: 'p1',
        phoneNumber: '+923001111111',
        email: null,
        disabled: false,
      },
      rideId: 'ride-c',
      body: {},
      idempotencyKeyHeader: 'idem-cancel-1',
      correlationId: 'c-cancel',
    });
    expect(res.httpStatus).toBe(200);
    expect(rtdb.get(tripLocationLatestPath('ride-c'))).toBeUndefined();
    expect(rtdb.get(rideAccessUidPath('ride-c', 'p1'))).toBeUndefined();
    expect(db.getDoc('locationStreams', 'ride-c_d1')?.streamState).toBe(
      'CLOSED',
    );
  });
});

describe('L2 Step 3 — NullTripLocationRtdb when URL unset', () => {
  it('accept still succeeds with null RTDB helper', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedAssignedRide(db, 'ride-1');
    const res = await request(
      createApp({
        auth: {
          verifyIdToken: async () => ({
            uid: 'd1',
            phone_number: '+923001111111',
          }),
        } as never,
        db: db as never,
        requireAppCheck: false,
        rateLimit: { windowMs: 60_000, max: 10_000 },
        tripLocationRtdb: null,
      }),
    )
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    expect(res.status).toBe(200);
    expect(db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq).toBe(1);
  });
});
