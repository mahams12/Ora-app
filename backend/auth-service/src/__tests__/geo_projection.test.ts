import { describe, expect, it } from 'vitest';
import { RedisGeoProjectionService } from '../redis/geo_projection';
import { createMemoryRedis } from '../redis/memory_redis';
import {
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  geoDriversCityKey,
} from '../redis/types';

function baseInput(
  overrides: Partial<{
    driverId: string;
    lat: number;
    lng: number;
    accuracy: number;
    locationStreamId: string;
    locationSeq: number;
    lastLocationTs: number;
    acceptedAt: string;
    homeCity: unknown;
  }> = {},
) {
  return {
    driverId: 'd1',
    lat: 31.52,
    lng: 74.35,
    accuracy: 8,
    locationStreamId: 's1',
    locationSeq: 1,
    lastLocationTs: Date.now(),
    acceptedAt: new Date().toISOString(),
    homeCity: 'lahore',
    ...overrides,
  };
}

describe('N2C coordinate-primary GEO projection', () => {
  it('1. accepted location projects into geo:drivers', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(baseInput());
    const pos = await redis.geopos(GEO_DRIVERS_KEY, 'd1');
    expect(pos).not.toBeNull();
    expect(Math.abs(Number(pos![1]) - 31.52)).toBeLessThan(1e-6);
  });

  it('2. driver with no homeCity still projects', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(baseInput({ homeCity: null }));
    expect(await redis.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
    expect(await redis.geopos(geoDriversCityKey('lahore'), 'd1')).toBeNull();
    const marker = JSON.parse((await redis.get(driverOnlineKey('d1')))!);
    expect(marker.city).toBeNull();
  });

  it('3. changing homeCity does not leave primary index; dual-writes legacy', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(
      baseInput({ homeCity: 'lahore', locationSeq: 1 }),
    );
    expect(await redis.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
    expect(await redis.geopos(geoDriversCityKey('lahore'), 'd1')).not.toBeNull();

    await geo.projectAcceptedLocation(
      baseInput({
        homeCity: 'islamabad',
        locationSeq: 2,
        lat: 33.7,
        lng: 73.0,
      }),
    );
    // Primary index still holds the driver at new coords
    const pos = await redis.geopos(GEO_DRIVERS_KEY, 'd1');
    expect(pos).not.toBeNull();
    expect(Math.abs(Number(pos![1]) - 33.7)).toBeLessThan(1e-6);
    // Legacy: moved city shard
    expect(await redis.geopos(geoDriversCityKey('lahore'), 'd1')).toBeNull();
    expect(await redis.geopos(geoDriversCityKey('islamabad'), 'd1')).not.toBeNull();
  });

  it('4–5. newer sequence wins; older does not overwrite', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    const t0 = Date.now();
    await geo.projectAcceptedLocation(
      baseInput({
        locationSeq: 5,
        lastLocationTs: t0,
        lat: 31.6,
        lng: 74.4,
      }),
    );
    await geo.projectAcceptedLocation(
      baseInput({
        locationSeq: 4,
        lastLocationTs: t0 + 1000,
        lat: 31.1,
        lng: 74.1,
      }),
    );
    const pos = await redis.geopos(GEO_DRIVERS_KEY, 'd1');
    expect(Math.abs(Number(pos![1]) - 31.6)).toBeLessThan(1e-6);
    const marker = JSON.parse((await redis.get(driverOnlineKey('d1')))!);
    expect(marker.locationSeq).toBe(5);
  });

  it('7. offline removes from geo:drivers', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(baseInput());
    await geo.removeDriverOnOffline({ driverId: 'd1', homeCity: 'lahore' });
    expect(await redis.geopos(GEO_DRIVERS_KEY, 'd1')).toBeNull();
    expect(await redis.geopos(geoDriversCityKey('lahore'), 'd1')).toBeNull();
    expect(await redis.get(driverOnlineKey('d1'))).toBeNull();
  });

  it('7b. offline without homeCity still removes primary membership', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(baseInput({ homeCity: null }));
    await geo.removeDriverOnOffline({ driverId: 'd1', homeCity: null });
    expect(await redis.geopos(GEO_DRIVERS_KEY, 'd1')).toBeNull();
  });

  it('8. re-project after offline restores membership', async () => {
    const redis = createMemoryRedis();
    const geo = new RedisGeoProjectionService(redis);
    await geo.projectAcceptedLocation(baseInput({ locationSeq: 1 }));
    await geo.removeDriverOnOffline({ driverId: 'd1', homeCity: 'lahore' });
    await geo.projectAcceptedLocation(baseInput({ locationSeq: 2 }));
    expect(await redis.geopos(GEO_DRIVERS_KEY, 'd1')).not.toBeNull();
  });

  it('9. Redis failure remains best-effort (no throw)', async () => {
    const failing = {
      async geoadd() {
        throw new Error('REDIS_DOWN');
      },
      async zrem() {
        throw new Error('REDIS_DOWN');
      },
      async geopos() {
        return null;
      },
      async get() {
        throw new Error('REDIS_DOWN');
      },
      async set() {
        throw new Error('REDIS_DOWN');
      },
      async del() {
        throw new Error('REDIS_DOWN');
      },
      async georadius() {
        return [];
      },
    };
    const geo = new RedisGeoProjectionService(failing);
    await expect(
      geo.projectAcceptedLocation(baseInput()),
    ).resolves.toBeUndefined();
    await expect(
      geo.removeDriverOnOffline({ driverId: 'd1', homeCity: 'lahore' }),
    ).resolves.toBeUndefined();
  });
});
