import type { RedisGeoClient } from './types';

/**
 * In-memory Redis stand-in for N2C unit proofs.
 * Supports GEOADD / ZREM / GEOPOS / GET / SET EX / DEL only.
 */
export function createMemoryRedis(): RedisGeoClient & {
  /** Test helper: dump geo members. */
  _geoMembers(key: string): Map<string, { lng: number; lat: number }>;
  _store: Map<string, { value: string; expiresAt: number | null }>;
} {
  const strings = new Map<
    string,
    { value: string; expiresAt: number | null }
  >();
  const geos = new Map<string, Map<string, { lng: number; lat: number }>>();

  function alive(key: string): string | null {
    const e = strings.get(key);
    if (!e) return null;
    if (e.expiresAt != null && Date.now() > e.expiresAt) {
      strings.delete(key);
      return null;
    }
    return e.value;
  }

  return {
    _store: strings,
    _geoMembers(key: string) {
      return geos.get(key) ?? new Map();
    },
    async geoadd(key, longitude, latitude, member) {
      let set = geos.get(key);
      if (!set) {
        set = new Map();
        geos.set(key, set);
      }
      const existed = set.has(member);
      set.set(member, { lng: longitude, lat: latitude });
      return existed ? 0 : 1;
    },
    async zrem(key, member) {
      const set = geos.get(key);
      if (!set || !set.has(member)) return 0;
      set.delete(member);
      return 1;
    },
    async geopos(key, member) {
      const set = geos.get(key);
      const pos = set?.get(member);
      if (!pos) return null;
      return [String(pos.lng), String(pos.lat)];
    },
    async get(key) {
      return alive(key);
    },
    async set(key, value, ttlSeconds) {
      strings.set(key, {
        value,
        expiresAt:
          ttlSeconds != null ? Date.now() + ttlSeconds * 1000 : null,
      });
      return 'OK';
    },
    async del(...keys) {
      let n = 0;
      for (const k of keys) {
        if (strings.delete(k)) n += 1;
        if (geos.delete(k)) n += 1;
      }
      return n;
    },
    async flushdb() {
      strings.clear();
      geos.clear();
      return 'OK';
    },
  };
}
