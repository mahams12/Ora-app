/**
 * N4 invite revalidation batching — loadInviteRevalidationContext +
 * isStillEligibleForInvite(revalidation) must produce IDENTICAL eligibility
 * decisions to the per-driver path while replacing serial reads with one
 * batched snapshot. Dispatch chunking keeps nearest-first order and early
 * exit.
 */
import { describe, it, expect } from 'vitest';
import { memoryDb } from './helpers/memory_db';
import { createMemoryGeoStore } from '../geo/memory_geo_store';
import { createFirestoreGeoClient } from '../geo/firestore_geo_client';
import { NearbyDriversService } from '../drivers/nearby_service';
import { DispatchWaveService } from '../rides/dispatch_wave_service';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../geo/types';
import { waveDocId } from '../rides/dispatch_types';

const PICKUP = { lat: 31.52, lng: 74.35 };

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    ...overrides,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
    ...overrides,
  });
}

async function seedGeoMarker(
  geoStore: ReturnType<typeof createMemoryGeoStore>,
  driverId: string,
  nowMs: number,
  marker: Partial<DriverOnlineMarker> = {},
  i = 0,
) {
  await geoStore.geoadd(
    GEO_DRIVERS_KEY,
    PICKUP.lng + i * 0.001,
    PICKUP.lat,
    driverId,
  );
  const full: DriverOnlineMarker = {
    driverId,
    lastLocationTs: nowMs,
    accuracy: 5,
    city: null,
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date(nowMs).toISOString(),
    ...marker,
  };
  await geoStore.set(
    driverOnlineKey(driverId),
    JSON.stringify(full),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

function seedRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  const now = Date.now();
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: null,
    state: 'SEARCHING',
    version: 1,
    requestVersion: 1,
    category: 'zip',
    serviceType: 'ride',
    pickup: { ...PICKUP, address: 'A' },
    destination: { lat: 31.53, lng: 74.36, address: 'B' },
    routePolyline: null,
    distanceKm: null,
    estimatedDurationMin: null,
    pricingSnapshotId: 'ps1',
    recommendedFareMinor: 50000,
    passengerOfferMinor: 45000,
    agreedFareMinor: null,
    agreedOfferId: null,
    agreedFareCurrency: null,
    feePolicySnapshot: null,
    paymentMethod: 'CASH',
    paymentIntentId: null,
    passengerCount: 1,
    expiresAt: new Date(now + 15 * 60_000).toISOString(),
    assignedAt: null,
    arrivedAt: null,
    startedAt: null,
    completedAt: null,
    closedAt: null,
    cancelledBy: null,
    cancellationReason: null,
    cancellationFeeMinor: null,
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    ...overrides,
  });
}

describe('loadInviteRevalidationContext — parity with per-driver path', () => {
  it('batched context returns identical eligibility for every rejection class', async () => {
    const db = memoryDb();
    const geoStore = createFirestoreGeoClient(db as never);
    const now = Date.now();

    // Eligible control.
    seedApprovedOnline(db, 'ok');
    // Stale marker (older than 15s freshness window).
    seedApprovedOnline(db, 'stale');
    // Banned user.
    seedApprovedOnline(db, 'banned', { banned: true });
    // Inactive user.
    seedApprovedOnline(db, 'inactive', { isActive: false });
    // Offline driver doc.
    seedApprovedOnline(db, 'offline', { availabilityState: 'offline' });
    // Busy driver (active ride assigned).
    seedApprovedOnline(db, 'busy');
    // Geo member with NO marker at all.
    seedApprovedOnline(db, 'nomarker');
    // Never seeded anywhere.
    // 'ghost' — no users/drivers docs, no geo, no marker.

    for (const [i, id] of [
      'ok',
      'stale',
      'banned',
      'inactive',
      'offline',
      'busy',
      'nomarker',
    ].entries()) {
      await geoStore.geoadd(GEO_DRIVERS_KEY, PICKUP.lng + i * 0.001, PICKUP.lat, id);
    }
    const markerFor = (id: string) =>
      JSON.stringify({
        driverId: id,
        lastLocationTs: id === 'stale' ? now - 60_000 : now,
        accuracy: 5,
        city: null,
        locationStreamId: 's1',
        locationSeq: 1,
        acceptedAt: new Date(now).toISOString(),
      } satisfies DriverOnlineMarker);
    for (const id of ['ok', 'stale', 'banned', 'inactive', 'offline', 'busy']) {
      await geoStore.set(driverOnlineKey(id), markerFor(id), 300);
    }
    db.seed('rides', 'ride-busy', {
      rideId: 'ride-busy',
      assignedDriverId: 'busy',
      state: 'DRIVER_EN_ROUTE',
    });

    const svc = new NearbyDriversService(db as never, geoStore);
    const ids = ['ok', 'stale', 'banned', 'inactive', 'offline', 'busy', 'nomarker', 'ghost'];
    const ctx = await svc.loadInviteRevalidationContext(ids, {
      requestId: 'test-ctx',
    });

    for (const id of ids) {
      const batched = await svc.isStillEligibleForInvite(id, {
        nowMs: now,
        revalidation: ctx,
      });
      const serial = await svc.isStillEligibleForInvite(id, { nowMs: now });
      expect(batched, `parity mismatch for ${id}`).toBe(serial);
    }
    // Spot-check the expected outcomes themselves.
    expect(await svc.isStillEligibleForInvite('ok', { nowMs: now, revalidation: ctx })).toBe(true);
    expect(await svc.isStillEligibleForInvite('stale', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('banned', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('inactive', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('offline', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('busy', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('nomarker', { nowMs: now, revalidation: ctx })).toBe(false);
    expect(await svc.isStillEligibleForInvite('ghost', { nowMs: now, revalidation: ctx })).toBe(false);
  });

  it('context covers only requested ids — unknown driver fails closed', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const now = Date.now();
    seedApprovedOnline(db, 'd1');
    await seedGeoMarker(geoStore, 'd1', now);
    const svc = new NearbyDriversService(db as never, geoStore);
    const ctx = await svc.loadInviteRevalidationContext(['d1']);
    // d2 was never part of the snapshot → not eligible (same as missing marker).
    expect(
      await svc.isStillEligibleForInvite('d2', { nowMs: now, revalidation: ctx }),
    ).toBe(false);
    expect(
      await svc.isStillEligibleForInvite('d1', { nowMs: now, revalidation: ctx }),
    ).toBe(true);
  });
});

describe('dispatch — chunked invite revalidation', () => {
  it('loads revalidation contexts lazily in nearest-first chunks', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const now = Date.now();

    const ids: string[] = [];
    for (let i = 0; i < 30; i += 1) {
      const id = `d${i}`;
      ids.push(id);
      seedApprovedOnline(db, id);
      await seedGeoMarker(geoStore, id, now, {}, i);
    }
    seedRide(db, 'r-chunk');

    const nearby = new NearbyDriversService(db as never, geoStore);
    const dispatch = new DispatchWaveService(db as never, nearby);

    // After findNearby returns, invalidate the markers of the nearest 25
    // candidates — they must fail revalidation, forcing the selection loop
    // past the first 25-candidate chunk into a second context load.
    const originalFind = nearby.findNearby.bind(nearby);
    nearby.findNearby = async (input) => {
      const result = await originalFind(input);
      for (const id of ids.slice(0, 25)) {
        await geoStore.del(driverOnlineKey(id));
      }
      return result;
    };

    const loadCalls: number[] = [];
    const originalLoad = nearby.loadInviteRevalidationContext.bind(nearby);
    nearby.loadInviteRevalidationContext = async (driverIds, opts) => {
      loadCalls.push(driverIds.length);
      return originalLoad(driverIds, opts);
    };

    const result = await dispatch.tickRide({
      rideId: 'r-chunk',
      correlationId: 'corr-chunk',
      nowMs: now,
    });

    expect(result.outcome).toBe('wave_completed');
    expect(result.waveNumber).toBe(1);
    expect(result.invitedCount).toBe(5);
    // Nearest 25 failed revalidation → wave filled from candidates 25-29.
    expect(result.driverIds).toEqual(ids.slice(25, 30));
    // Exactly two chunk loads: [0..24] then [25..29].
    expect(loadCalls).toEqual([25, 5]);

    const wave = db.getDoc('rideDispatchWaves', waveDocId('r-chunk', 1));
    expect(wave?.driverIds).toEqual(ids.slice(25, 30));
  });
});
