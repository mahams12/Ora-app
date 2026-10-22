import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { createFirestoreGeoClient } from '../redis/firestore_geo_client';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  geoDriversCityKey,
  type DriverOnlineMarker,
} from '../redis/types';
import { createEmptyN3NearbyDiagnostics } from '../drivers/nearby_service';

const WORKER = 'test-worker-token-fsgeo-xxxx';
const LAHORE = { lat: 31.52, lng: 74.35 };

function appFor(db: ReturnType<typeof memoryDb>) {
  return createApp({
    auth: {
      verifyIdToken: async () => ({ uid: 'unused', phone_number: '+100' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    redis: createFirestoreGeoClient(db as never),
  });
}

function seedApprovedOnlineDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    displayName: uid,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

function markerFor(
  driverId: string,
  overrides: Partial<DriverOnlineMarker> = {},
): string {
  const marker: DriverOnlineMarker = {
    driverId,
    lastLocationTs: Date.now(),
    accuracy: 8,
    city: null,
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date().toISOString(),
    ...overrides,
  };
  return JSON.stringify(marker);
}

async function seedOnlineGeo(
  db: ReturnType<typeof memoryDb>,
  driverId: string,
  lat: number,
  lng: number,
  marker?: Partial<DriverOnlineMarker>,
) {
  const geo = createFirestoreGeoClient(db as never);
  await geo.geoadd(GEO_DRIVERS_KEY, lng, lat, driverId);
  await geo.set(
    driverOnlineKey(driverId),
    markerFor(driverId, marker),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

describe('FirestoreGeoClient — client semantics', () => {
  it('geoadd/geopos/zrem round-trip on geo:drivers', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    expect(await geo.geoadd(GEO_DRIVERS_KEY, 74.35, 31.52, 'd1')).toBe(1);
    // geoadd is the hot path (every GPS update) — no pre-read, so the
    // added/updated count is not distinguished. Callers never consume it.
    expect(await geo.geoadd(GEO_DRIVERS_KEY, 74.36, 31.53, 'd1')).toBe(1);
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).toEqual([
      '74.36',
      '31.53',
    ]);
    expect(await geo.zrem(GEO_DRIVERS_KEY, 'd1')).toBe(1);
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).toBeNull();
    expect(await geo.zrem(GEO_DRIVERS_KEY, 'd1')).toBe(0);
  });

  it('georadius returns in-radius hits sorted by distance', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.geoadd(GEO_DRIVERS_KEY, 74.351, 31.521, 'near'); // ~0.1 km
    await geo.geoadd(GEO_DRIVERS_KEY, 74.45, 31.60, 'mid'); // ~13 km
    await geo.geoadd(GEO_DRIVERS_KEY, 75.50, 32.50, 'far'); // >100 km
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 15,
      count: 100,
    });
    expect(hits.map((h) => h.member)).toEqual(['near', 'mid']);
    expect(hits[0].distanceKm).toBeLessThan(hits[1].distanceKm);
  });

  it('georadius honors count cap', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    for (let i = 0; i < 5; i++) {
      await geo.geoadd(
        GEO_DRIVERS_KEY,
        LAHORE.lng + i * 0.001,
        LAHORE.lat,
        `d${i}`,
      );
    }
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 10,
      count: 2,
    });
    expect(hits).toHaveLength(2);
  });

  it('set/get/mget/del with TTL expiry', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.set(driverOnlineKey('d1'), 'v1', 60);
    await geo.set(driverOnlineKey('d2'), 'v2', -1); // already expired
    await geo.set(driverOnlineKey('d3'), 'v3'); // no TTL
    expect(await geo.get(driverOnlineKey('d1'))).toBe('v1');
    expect(await geo.get(driverOnlineKey('d2'))).toBeNull();
    expect(await geo.get(driverOnlineKey('d3'))).toBe('v3');
    expect(
      await geo.mget([
        driverOnlineKey('d1'),
        driverOnlineKey('d2'),
        driverOnlineKey('d3'),
        driverOnlineKey('missing'),
      ]),
    ).toEqual(['v1', null, 'v3', null]);
    expect(await geo.del(driverOnlineKey('d1'))).toBe(1);
    expect(await geo.get(driverOnlineKey('d1'))).toBeNull();
  });

  it('projectLocation writes geo + marker in one doc', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1'),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).toEqual([
      String(LAHORE.lng),
      String(LAHORE.lat),
    ]);
    expect(await geo.get(driverOnlineKey('d1'))).not.toBeNull();
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
    });
    expect(hits.map((h) => h.member)).toEqual(['d1']);
  });

  it('del removes marker but preserves geo membership (Redis parity)', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1'),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    expect(await geo.del(driverOnlineKey('d1'))).toBe(1);
    expect(await geo.get(driverOnlineKey('d1'))).toBeNull();
    // GEO membership survives DEL — driver only becomes ineligible via the
    // missing marker (same observable behavior as Redis).
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
  });

  it('standalone geoadd preserves existing marker (merge semantics)', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.set(driverOnlineKey('d1'), 'v1', 60);
    await geo.geoadd(GEO_DRIVERS_KEY, LAHORE.lng, LAHORE.lat, 'd1');
    expect(await geo.get(driverOnlineKey('d1'))).toBe('v1');
  });

  it('georadius returns markerValue on each hit (merged doc — no MGET needed)', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1'),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
    });
    expect(hits).toHaveLength(1);
    expect(hits[0].markerValue).not.toBeNull();
    expect(JSON.parse(hits[0].markerValue as string).driverId).toBe('d1');
  });

  it('georadius reports expired marker as null markerValue (no refetch)', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.geoadd(GEO_DRIVERS_KEY, LAHORE.lng, LAHORE.lat, 'd-exp');
    await geo.set(driverOnlineKey('d-exp'), markerFor('d-exp'), -1);
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
    });
    expect(hits).toHaveLength(1);
    expect(hits[0].markerValue).toBeNull();
  });

  it('minLastLocationTs excludes stale docs before read-cost at query level', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd-fresh',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d-fresh'),
      markerValue: markerFor('d-fresh', { lastLocationTs: Date.now() }),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd-stale',
      longitude: LAHORE.lng + 0.001,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d-stale'),
      markerValue: markerFor('d-stale', {
        lastLocationTs: Date.now() - 60_000,
      }),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    const floor = Date.now() - 15_000;
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
      minLastLocationTs: floor,
    });
    expect(hits.map((h) => h.member)).toEqual(['d-fresh']);
    // Without the floor both docs are geo hits (freshness left to caller).
    const all = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
    });
    expect(all).toHaveLength(2);
  });

  it('del clears freshness twins so doc no longer matches freshness filter', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1'),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
    });
    await geo.del(driverOnlineKey('d1'));
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
      minLastLocationTs: Date.now() - 15_000,
    });
    expect(hits).toEqual([]);
    // Membership still intact (Redis parity) — doc exists, just no marker.
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
  });

  it('legacy city-shard keys are no-ops (not read by matching)', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    expect(
      await geo.geoadd(geoDriversCityKey('lahore'), 74.3, 31.5, 'd1'),
    ).toBe(1);
    expect(await geo.zrem(geoDriversCityKey('lahore'), 'd1')).toBe(0);
    expect(await geo.geopos(geoDriversCityKey('lahore'), 'd1')).toBeNull();
    expect(
      await geo.georadius({
        key: geoDriversCityKey('lahore'),
        longitude: 74.3,
        latitude: 31.5,
        radiusKm: 10,
        count: 10,
      }),
    ).toEqual([]);
  });
});

describe('N3 nearby via Firestore geo store (HTTP integration)', () => {
  it('skips the marker MGET entirely — markers arrive on geo hits', async () => {
    const db = memoryDb();
    seedApprovedOnlineDriver(db, 'd-near');
    await seedOnlineGeo(db, 'd-near', LAHORE.lat, LAHORE.lng, {
      lastLocationTs: Date.now() - 1000,
    });
    const { NearbyDriversService } = await import(
      '../drivers/nearby_service'
    );
    const svc = new NearbyDriversService(
      db as never,
      createFirestoreGeoClient(db as never),
    );
    let diag = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { lat: LAHORE.lat, lng: LAHORE.lng },
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(result.candidates).toHaveLength(1);
    // Zero marker fetches: markerValue rode in on the bounding-box scan.
    expect(diag.redisGetCount).toBe(0);
    expect(diag.geoHits).toBe(1);
  });

  it('returns eligible nearby driver end-to-end', async () => {
    const db = memoryDb();
    seedApprovedOnlineDriver(db, 'd-near');
    await seedOnlineGeo(db, 'd-near', LAHORE.lat, LAHORE.lng, {
      lastLocationTs: Date.now() - 1000,
    });
    const res = await request(appFor(db))
      .get('/v1/internal/drivers/nearby')
      .query({ lat: LAHORE.lat, lng: LAHORE.lng })
      .set('X-Ora-Worker-Token', WORKER);
    expect(res.status).toBe(200);
    expect(res.body.data.candidates.map((c: { driverId: string }) => c.driverId))
      .toEqual(['d-near']);
  });

  it('orders multiple drivers by distance; out-of-radius excluded', async () => {
    const db = memoryDb();
    seedApprovedOnlineDriver(db, 'd-a');
    seedApprovedOnlineDriver(db, 'd-b');
    seedApprovedOnlineDriver(db, 'd-far');
    await seedOnlineGeo(db, 'd-a', LAHORE.lat + 0.002, LAHORE.lng);
    await seedOnlineGeo(db, 'd-b', LAHORE.lat + 0.001, LAHORE.lng);
    await seedOnlineGeo(db, 'd-far', LAHORE.lat + 2.0, LAHORE.lng);
    const res = await request(appFor(db))
      .get('/v1/internal/drivers/nearby')
      .query({ lat: LAHORE.lat, lng: LAHORE.lng, radiusKm: 10 })
      .set('X-Ora-Worker-Token', WORKER);
    expect(res.status).toBe(200);
    expect(res.body.data.candidates.map((c: { driverId: string }) => c.driverId))
      .toEqual(['d-b', 'd-a']);
  });

  it('rejects stale marker and expired marker', async () => {
    const db = memoryDb();
    seedApprovedOnlineDriver(db, 'd-stale');
    seedApprovedOnlineDriver(db, 'd-expired');
    await seedOnlineGeo(db, 'd-stale', LAHORE.lat, LAHORE.lng, {
      lastLocationTs: Date.now() - 60_000, // > 15s freshness window
    });
    const geo = createFirestoreGeoClient(db as never);
    await geo.geoadd(GEO_DRIVERS_KEY, LAHORE.lng, LAHORE.lat, 'd-expired');
    await geo.set(
      driverOnlineKey('d-expired'),
      markerFor('d-expired'),
      -1, // already expired at write time
    );
    const res = await request(appFor(db))
      .get('/v1/internal/drivers/nearby')
      .query({ lat: LAHORE.lat, lng: LAHORE.lng })
      .set('X-Ora-Worker-Token', WORKER);
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toEqual([]);
  });

  it('rejects poor-accuracy and offline drivers', async () => {
    const db = memoryDb();
    seedApprovedOnlineDriver(db, 'd-badacc');
    db.seed('users', 'd-off', {
      uid: 'd-off',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd-off', {
      driverId: 'd-off',
      userId: 'd-off',
      availabilityState: 'offline',
    });
    await seedOnlineGeo(db, 'd-badacc', LAHORE.lat, LAHORE.lng, {
      accuracy: 80, // > N3_MAX_ACCURACY_M (50)
    });
    await seedOnlineGeo(db, 'd-off', LAHORE.lat, LAHORE.lng);
    const res = await request(appFor(db))
      .get('/v1/internal/drivers/nearby')
      .query({ lat: LAHORE.lat, lng: LAHORE.lng })
      .set('X-Ora-Worker-Token', WORKER);
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toEqual([]);
  });
});
