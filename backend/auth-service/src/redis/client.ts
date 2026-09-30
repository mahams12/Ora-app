import type { RedisGeoClient } from './types';

/**
 * Create Redis GEO client from REDIS_URL, or null if unset.
 * Uses dynamic import of ioredis so unit tests without the package still load
 * when redis is not configured — package is a runtime dependency when URL set.
 */
export async function createRedisGeoClientFromEnv(
  env: NodeJS.ProcessEnv = process.env,
): Promise<RedisGeoClient | null> {
  const url = env.REDIS_URL?.trim();
  if (!url) return null;

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const Redis = require('ioredis') as typeof import('ioredis').default;
  const client = new Redis(url, {
    maxRetriesPerRequest: 1,
    enableReadyCheck: true,
    lazyConnect: false,
  });

  return {
    async geoadd(key, longitude, latitude, member) {
      return client.geoadd(key, longitude, latitude, member);
    },
    async zrem(key, member) {
      return client.zrem(key, member);
    },
    async geopos(key, member) {
      const rows = await client.geopos(key, member);
      const row = rows[0];
      if (!row || row[0] == null || row[1] == null) return null;
      return [row[0], row[1]];
    },
    async georadius(input) {
      // GEORADIUS key lng lat radius km ASC WITHCOORD WITHDIST COUNT n
      const rows = (await client.georadius(
        input.key,
        input.longitude,
        input.latitude,
        input.radiusKm,
        'km',
        'ASC',
        'WITHCOORD',
        'WITHDIST',
        'COUNT',
        input.count,
      )) as Array<[string, string, [string, string]]>;
      const out: import('./types').GeoRadiusHit[] = [];
      for (const row of rows ?? []) {
        if (!Array.isArray(row) || row.length < 3) continue;
        const member = row[0];
        const distRaw = row[1];
        const coord = row[2];
        if (typeof member !== 'string' || !Array.isArray(coord)) continue;
        const lng = Number(coord[0]);
        const lat = Number(coord[1]);
        const distanceKm = Number(distRaw);
        if (!Number.isFinite(lng) || !Number.isFinite(lat) || !Number.isFinite(distanceKm)) {
          continue;
        }
        out.push({ member, distanceKm, longitude: lng, latitude: lat });
      }
      return out;
    },
    async get(key) {
      return client.get(key);
    },
    async mget(keys) {
      if (keys.length === 0) return [];
      const values = await client.mget(...keys);
      return values.map((v) => (v == null ? null : v));
    },
    async set(key, value, ttlSeconds) {
      if (ttlSeconds != null) {
        await client.set(key, value, 'EX', ttlSeconds);
      } else {
        await client.set(key, value);
      }
      return 'OK';
    },
    async del(...keys) {
      if (keys.length === 0) return 0;
      return client.del(...keys);
    },
    async flushdb() {
      await client.flushdb();
      return 'OK';
    },
    async quit() {
      await client.quit();
      return 'OK';
    },
  };
}
