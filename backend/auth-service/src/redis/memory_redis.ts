import type { GeoRadiusHit, RedisGeoClient } from './types';

/**
 * In-memory Redis stand-in for N2C / N3 unit proofs.
 * Supports GEOADD / ZREM / GEOPOS / GEORADIUS / GET / SET EX / DEL.
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

  function haversineKm(
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number,
  ): number {
    const R = 6371;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) *
        Math.cos(toRad(lat2)) *
        Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
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
    async georadius(input) {
      const set = geos.get(input.key);
      if (!set) return [];
      const hits: GeoRadiusHit[] = [];
      for (const [member, pos] of set.entries()) {
        const distanceKm = haversineKm(
          input.latitude,
          input.longitude,
          pos.lat,
          pos.lng,
        );
        if (distanceKm <= input.radiusKm) {
          hits.push({
            member,
            distanceKm,
            longitude: pos.lng,
            latitude: pos.lat,
          });
        }
      }
      hits.sort((a, b) => a.distanceKm - b.distanceKm);
      return hits.slice(0, input.count);
    },
    async get(key) {
      return alive(key);
    },
    async mget(keys) {
      return keys.map((key) => alive(key));
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
