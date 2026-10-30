/**
 * Eligibility cache — bounded TTL on the per-packet users+drivers reads.
 * Verifies read reduction, invalidation on availability transitions, expiry,
 * and that failures are never cached (fail-closed).
 */
import { describe, expect, it } from 'vitest';
import { memoryDb } from './helpers/memory_db';
import {
  DriverEligibilityCache,
  LocationUpdateService,
} from '../location/location_update_service';
import { DriverAvailabilityService } from '../drivers/driver_availability_service';
import type { AuthenticatedCaller } from '../types';

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

function caller(uid: string): AuthenticatedCaller {
  return {
    uid,
    phoneNumber: '+923001111111',
    email: null,
    disabled: false,
  };
}

function body(seq: number) {
  return {
    locationSeq: seq,
    locationStreamId: 'stream-a',
    lat: 31.52,
    lng: 74.35,
    accuracy: 8,
    heading: 90,
    speed: 20,
    timestamp: new Date().toISOString(),
    provider: 'gps',
  };
}

describe('DriverEligibilityCache — per-packet read reduction', () => {
  it('second accepted packet within TTL reuses the eligibility snapshot', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const cache = new DriverEligibilityCache(15_000);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });

    await service.update({ caller: caller('d1'), body: body(1) });
    await service.update({ caller: caller('d1'), body: body(2) });
    await service.update({ caller: caller('d1'), body: body(3) });

    // First packet misses (users+drivers reads); next two hit the cache.
    expect(cache.stats()).toEqual({ hits: 2, misses: 1, size: 1 });
  });

  it('invalidate forces a re-read on the next packet', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const cache = new DriverEligibilityCache(15_000);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });

    await service.update({ caller: caller('d1'), body: body(1) });
    cache.invalidate('d1');
    await service.update({ caller: caller('d1'), body: body(2) });

    expect(cache.stats().misses).toBe(2);
    expect(cache.stats().hits).toBe(0);
  });

  it('expired entry is re-fetched (injectable clock)', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    let now = 1_000_000;
    const cache = new DriverEligibilityCache(15_000, () => now);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });

    await service.update({ caller: caller('d1'), body: body(1) });
    now += 20_000; // past TTL
    await service.update({ caller: caller('d1'), body: body(2) });

    expect(cache.stats().misses).toBe(2);
  });

  it('ttl=0 disables caching entirely', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const cache = new DriverEligibilityCache(0);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });

    await service.update({ caller: caller('d1'), body: body(1) });
    await service.update({ caller: caller('d1'), body: body(2) });

    expect(cache.stats().hits).toBe(0);
    expect(cache.stats().misses).toBe(2);
  });

  it('failed eligibility is never cached — rejected offline driver re-checks each packet', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      userId: 'd1',
      availabilityState: 'offline',
    });
    const cache = new DriverEligibilityCache(15_000);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });

    await expect(
      service.update({ caller: caller('d1'), body: body(1) }),
    ).rejects.toMatchObject({ code: 'FORBIDDEN' });
    // Flip to online — uncached failure means immediate recovery.
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      userId: 'd1',
      availabilityState: 'online',
    });
    const res = await service.update({ caller: caller('d1'), body: body(1) });
    expect(res.httpStatus).toBe(200);
    expect(cache.stats().hits).toBe(0);
  });

  it('availability service transition hook invalidates the cache entry', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const cache = new DriverEligibilityCache(15_000);
    const service = new LocationUpdateService(db as never, null, null, {
      eligibilityCache: cache,
    });
    const availability = new DriverAvailabilityService(
      db as never,
      null,
      (driverId) => cache.invalidate(driverId),
    );

    await service.update({ caller: caller('d1'), body: body(1) });
    expect(cache.stats().size).toBe(1);

    await availability.goOffline({ caller: caller('d1') });
    expect(cache.stats().size).toBe(0);

    // Driver is now durably offline — next publish is rejected (re-read).
    await expect(
      service.update({ caller: caller('d1'), body: body(2) }),
    ).rejects.toMatchObject({ code: 'FORBIDDEN' });

    // Back online → transition hook clears the (absent) entry; publish works.
    await availability.goOnline({ caller: caller('d1') });
    const res = await service.update({ caller: caller('d1'), body: body(2) });
    expect(res.httpStatus).toBe(200);
  });
});
