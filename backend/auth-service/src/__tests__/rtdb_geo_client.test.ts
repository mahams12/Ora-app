import { describe, expect, it } from 'vitest';
import { createRtdbGeoClient } from '../rtdb/rtdb_geo_client';
import { memoryRtdb } from './helpers/memory_rtdb';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  geoDriversCityKey,
  type DriverOnlineMarker,
} from '../redis/types';
import { RedisGeoProjectionService } from '../redis/geo_projection';

const LAHORE = { lat: 31.52, lng: 74.35 };

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

function seedDriver(
  geo: ReturnType<typeof createRtdbGeoClient>,
  driverId: string,
  lat: number,
  lng: number,
  marker?: Partial<DriverOnlineMarker>,
) {
  return geo.projectLocation!({
    key: GEO_DRIVERS_KEY,
    member: driverId,
    longitude: lng,
    latitude: lat,
    markerKey: driverOnlineKey(driverId),
    markerValue: markerFor(driverId, marker),
    markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
  });
}

describe('RtdbGeoClient — Redis-parity semantics', () => {
  it('projectLocation writes geo + marker in one node', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    const res = await seedDriver(geo, 'd1', LAHORE.lat, LAHORE.lng);
    expect(res).toBe('written');
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

  it('markerGuard skip aborts the write inside the transaction', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await seedDriver(geo, 'd1', LAHORE.lat, LAHORE.lng, {
      lastLocationTs: 1000,
      locationSeq: 5,
    });
    let saw: string | null | undefined;
    const result = await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng + 1,
      latitude: LAHORE.lat + 1,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1', { lastLocationTs: 500, locationSeq: 4 }),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
      markerGuard: (existing) => {
        saw = existing.markerValue;
        return 'skip';
      },
    });
    expect(result).toBe('skipped');
    expect(JSON.parse(saw!).locationSeq).toBe(5);
    // Original doc untouched.
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).toEqual([
      String(LAHORE.lng),
      String(LAHORE.lat),
    ]);
    expect(
      JSON.parse((await geo.get(driverOnlineKey('d1')))!).locationSeq,
    ).toBe(5);
  });

  it('markerGuard write applies atomically', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await seedDriver(geo, 'd1', LAHORE.lat, LAHORE.lng, {
      lastLocationTs: 1000,
      locationSeq: 5,
    });
    const result = await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: 'd1',
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      markerKey: driverOnlineKey('d1'),
      markerValue: markerFor('d1', { lastLocationTs: 2000, locationSeq: 6 }),
      markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
      markerGuard: (existing) => {
        const prev = JSON.parse(existing.markerValue!) as DriverOnlineMarker;
        return prev.lastLocationTs > 2000 ? 'skip' : 'write';
      },
    });
    expect(result).toBe('written');
    expect(
      JSON.parse((await geo.get(driverOnlineKey('d1')))!).locationSeq,
    ).toBe(6);
  });

  it('georadius orders nearest-first and respects radius + count', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await seedDriver(geo, 'far', LAHORE.lat + 0.1, LAHORE.lng); // ~11km
    await seedDriver(geo, 'near', LAHORE.lat + 0.01, LAHORE.lng); // ~1.1km
    await seedDriver(geo, 'mid', LAHORE.lat + 0.04, LAHORE.lng); // ~4.4km
    await seedDriver(geo, 'outside', LAHORE.lat + 0.5, LAHORE.lng); // ~55km
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 10,
      count: 10,
    });
    expect(hits.map((h) => h.member)).toEqual(['near', 'mid']);
    expect(hits[0].distanceKm).toBeLessThan(hits[1].distanceKm);
    const capped = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 10,
      count: 1,
    });
    expect(capped.map((h) => h.member)).toEqual(['near']);
  });

  it('georadius finds drivers across geohash cell boundaries', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    // Place a ring of drivers just inside the radius in every direction —
    // correctness must not depend on which cell a driver hashes into.
    for (let i = 0; i < 12; i += 1) {
      const angle = (i / 12) * 2 * Math.PI;
      await seedDriver(
        geo,
        `ring-${i}`,
        LAHORE.lat + 0.08 * Math.sin(angle),
        LAHORE.lng + 0.08 * Math.cos(angle),
      );
    }
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 10,
      count: 20,
    });
    expect(hits).toHaveLength(12);
  });

  it('expired marker returns null but geo membership remains', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await geo.set(driverOnlineKey('d-exp'), markerFor('d-exp'), -1);
    expect(await geo.get(driverOnlineKey('d-exp'))).toBeNull();
  });

  it('zrem removes the node entirely', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await seedDriver(geo, 'd1', LAHORE.lat, LAHORE.lng);
    expect(await geo.zrem(GEO_DRIVERS_KEY, 'd1')).toBe(1);
    expect(await geo.zrem(GEO_DRIVERS_KEY, 'd1')).toBe(0);
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).toBeNull();
    expect(await geo.get(driverOnlineKey('d1'))).toBeNull();
  });

  it('del clears marker fields but preserves geo membership (Redis parity)', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    await seedDriver(geo, 'd1', LAHORE.lat, LAHORE.lng);
    expect(await geo.del(driverOnlineKey('d1'))).toBe(1);
    expect(await geo.get(driverOnlineKey('d1'))).toBeNull();
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
  });

  it('legacy city-shard keys are no-ops (same as Firestore client)', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    expect(await geo.geoadd(geoDriversCityKey('lahore'), 74, 31, 'd1')).toBe(1);
    expect(await geo.zrem(geoDriversCityKey('lahore'), 'd1')).toBe(0);
    expect(rtdb._root.geoPresence).toBeUndefined();
  });

  it('minLastLocationTs filters stale docs post-fetch', async () => {
    const rtdb = memoryRtdb();
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    const now = Date.now();
    await seedDriver(geo, 'fresh', LAHORE.lat + 0.01, LAHORE.lng, {
      lastLocationTs: now,
    });
    await seedDriver(geo, 'stale', LAHORE.lat + 0.01, LAHORE.lng, {
      lastLocationTs: now - 60_000,
    });
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 10,
      count: 10,
      minLastLocationTs: now - 15_000,
    });
    expect(hits.map((h) => h.member)).toEqual(['fresh']);
  });

  it('sweepExpired removes expired nodes only', async () => {
    const rtdb = memoryRtdb();
    const now = { t: Date.now() };
    const geo = createRtdbGeoClient(rtdb.ref('/'), { nowMs: () => now.t });
    await seedDriver(geo, 'alive', LAHORE.lat, LAHORE.lng);
    await geo.set(driverOnlineKey('dead'), markerFor('dead'), -1);
    now.t += 20_000; // 'dead' was already expired; 'alive' has ~10s TTL left
    expect(await geo.sweepExpired!()).toBe(1);
    expect(await geo.geopos(GEO_DRIVERS_KEY, 'alive')).not.toBeNull();
    expect(await geo.get(driverOnlineKey('dead'))).toBeNull();
  });
});

describe('RtdbGeoClient — projection service integration', () => {
  function projectionFor(rtdb: ReturnType<typeof memoryRtdb>) {
    const geo = createRtdbGeoClient(rtdb.ref('/'));
    return { geo, svc: new RedisGeoProjectionService(geo) };
  }

  const base = {
    driverId: 'd1',
    lat: LAHORE.lat,
    lng: LAHORE.lng,
    accuracy: 8,
    homeCity: 'lahore',
    acceptedAt: new Date().toISOString(),
  };

  it('accepted location projects into geo presence', async () => {
    const { geo, svc } = projectionFor(memoryRtdb());
    await svc.projectAcceptedLocation({
      ...base,
      locationStreamId: 's1',
      locationSeq: 1,
      lastLocationTs: Date.now(),
    });
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: LAHORE.lng,
      latitude: LAHORE.lat,
      radiusKm: 5,
      count: 10,
    });
    expect(hits.map((h) => h.member)).toEqual(['d1']);
  });

  it('cross-stream: strictly older-ts packet rejected atomically', async () => {
    const { geo, svc } = projectionFor(memoryRtdb());
    const now = Date.now();
    await svc.projectAcceptedLocation({
      ...base,
      locationStreamId: 'trip',
      locationSeq: 1,
      lastLocationTs: now,
    });
    await svc.projectAcceptedLocation({
      ...base,
      locationStreamId: 'idle',
      locationSeq: 99,
      lastLocationTs: now - 5_000,
    });
    const marker = JSON.parse((await geo.get(driverOnlineKey('d1')))!);
    expect(marker.locationStreamId).toBe('trip');
  });

  it('newer-ts packet from different stream wins', async () => {
    const { geo, svc } = projectionFor(memoryRtdb());
    const now = Date.now();
    await svc.projectAcceptedLocation({
      ...base,
      locationStreamId: 'idle',
      locationSeq: 50,
      lastLocationTs: now - 5_000,
    });
    await svc.projectAcceptedLocation({
      ...base,
      locationStreamId: 'trip',
      locationSeq: 1,
      lastLocationTs: now,
    });
    const marker = JSON.parse((await geo.get(driverOnlineKey('d1')))!);
    expect(marker.locationStreamId).toBe('trip');
  });
});
