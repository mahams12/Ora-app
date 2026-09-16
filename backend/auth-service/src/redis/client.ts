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
    async get(key) {
      return client.get(key);
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
