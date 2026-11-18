import { describe, it, expect, vi } from 'vitest';
import {
  NearbyDriversService,
  createEmptyN3NearbyDiagnostics,
  type N3NearbyDiagnostics,
} from '../drivers/nearby_service';
import { memoryDb } from './helpers/memory_db';
import { createMemoryGeoStore } from '../geo/memory_geo_store';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
  type GeoStoreClient,
} from '../geo/types';

const pickup = { lat: 31.52, lng: 74.35 };
const now = Date.now();

function seedApprovedOnline(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    availabilityState: 'online',
  });
}

async function seedGeo(
  geoStore: ReturnType<typeof createMemoryGeoStore>,
  driverId: string,
  marker: Partial<DriverOnlineMarker> & { lastLocationTs: number },
  lngOffset = 0.01,
) {
  await geoStore.geoadd(
    GEO_DRIVERS_KEY,
    pickup.lng + lngOffset,
    pickup.lat,
    driverId,
  );
  const full: DriverOnlineMarker = {
    driverId,
    accuracy: 8,
    city: null,
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date().toISOString(),
    ...marker,
  };
  await geoStore.set(
    driverOnlineKey(driverId),
    JSON.stringify(full),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

function wrapGeoStoreForFindNearby(
  base: ReturnType<typeof createMemoryGeoStore>,
): {
  geoStore: GeoStoreClient;
  mgetSpy: ReturnType<typeof vi.fn>;
  getSpy: ReturnType<typeof vi.fn>;
} {
  const mgetSpy = vi.fn(base.mget.bind(base));
  const getSpy = vi.fn(base.get.bind(base));
  const geoStore: GeoStoreClient = {
    ...base,
    mget: mgetSpy,
    get: getSpy,
  };
  return { geoStore, mgetSpy, getSpy };
}

describe('N3 findNearby geo-store MGET batching', () => {
  it('mget receives driver:online keys in GEO hit order', async () => {
    const db = memoryDb();
    const base = createMemoryGeoStore();
    const { geoStore, mgetSpy } = wrapGeoStoreForFindNearby(base);
    for (let i = 0; i < 3; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(base, id, { lastLocationTs: now - 1000, driverId: id }, 0.001 * (i + 1));
    }
    const svc = new NearbyDriversService(db as never, geoStore);
    await svc.findNearby({ query: { ...pickup }, nowMs: now });
    expect(mgetSpy).toHaveBeenCalledTimes(1);
    expect(mgetSpy.mock.calls[0][0]).toEqual([
      driverOnlineKey('d0'),
      driverOnlineKey('d1'),
      driverOnlineKey('d2'),
    ]);
  });

  it('findNearby does not call geoStore.get (N4 path still uses get separately)', async () => {
    const db = memoryDb();
    const base = createMemoryGeoStore();
    const { geoStore, getSpy } = wrapGeoStoreForFindNearby(base);
    seedApprovedOnline(db, 'd1');
    await seedGeo(base, 'd1', { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, geoStore);
    await svc.findNearby({ query: { ...pickup }, nowMs: now });
    expect(getSpy).not.toHaveBeenCalled();
  });

  it('eligibility and candidate ordering match GEO ASC distance order', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    seedApprovedOnline(db, 'near');
    seedApprovedOnline(db, 'far');
    await seedGeo(geoStore, 'far', { lastLocationTs: now - 1000, driverId: 'far' }, 0.05);
    await seedGeo(geoStore, 'near', { lastLocationTs: now - 1000, driverId: 'near' }, 0.001);
    const svc = new NearbyDriversService(db as never, geoStore);
    const result = await svc.findNearby({ query: { ...pickup, limit: 10 }, nowMs: now });
    expect(result.candidates.map((c) => c.driverId)).toEqual(['near', 'far']);
  });

  it('missing marker still increments marker_missing; prefetch loads docs before loop', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    seedApprovedOnline(db, 'd1');
    await geoStore.geoadd(GEO_DRIVERS_KEY, pickup.lng + 0.01, pickup.lat, 'd1');
    const svc = new NearbyDriversService(db as never, geoStore);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.marker_missing).toBe(1);
    expect(captured.firestoreUsersReads).toBe(1);
    expect(captured.firestoreDriversReads).toBe(1);
    expect(captured.geoGetCount).toBe(1);
  });

  it('stale and bad-accuracy markers reject; prefetch loads all geo docs', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    seedApprovedOnline(db, 'stale');
    seedApprovedOnline(db, 'badAcc');
    await seedGeo(geoStore, 'stale', { lastLocationTs: now - 60_000, driverId: 'stale' }, 0.01);
    await seedGeo(geoStore, 'badAcc', {
      lastLocationTs: now - 1000,
      driverId: 'badAcc',
      accuracy: 999,
    }, 0.02);
    const svc = new NearbyDriversService(db as never, geoStore);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.marker_not_fresh).toBe(1);
    expect(captured.rejected.marker_accuracy).toBe(1);
    expect(captured.firestoreUsersReads).toBe(2);
    expect(captured.firestoreDriversReads).toBe(2);
    expect(captured.geoGetCount).toBe(1);
  });

  it('mget failure → DEPENDENCY_ERROR 503', async () => {
    const db = memoryDb();
    const base = createMemoryGeoStore();
    seedApprovedOnline(db, 'd1');
    await seedGeo(base, 'd1', { lastLocationTs: now - 1000 });
    const geoStore: GeoStoreClient = {
      ...base,
      async mget() {
        throw new Error('geoStore down');
      },
    };
    const svc = new NearbyDriversService(db as never, geoStore);
    await expect(
      svc.findNearby({ query: { ...pickup }, nowMs: now }),
    ).rejects.toMatchObject({
      code: 'DEPENDENCY_ERROR',
      httpStatus: 503,
    });
  });

  it('mixed geo hits: same rejection buckets as sequential semantics', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    seedApprovedOnline(db, 'ok');
    await seedGeo(geoStore, 'ok', { lastLocationTs: now - 1000, driverId: 'ok' }, 0.001);
    await geoStore.geoadd(GEO_DRIVERS_KEY, pickup.lng + 0.02, pickup.lat, 'ghost');
    const svc = new NearbyDriversService(db as never, geoStore);
    let captured: N3NearbyDiagnostics = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0].driverId).toBe('ok');
    expect(captured.rejected.marker_missing).toBe(1);
    expect(captured.eligibleCount).toBe(1);
  });
});
