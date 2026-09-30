/**
 * Minimal Redis command surface for N2C GEO projection + N3 GEORADIUS read.
 * Real: ioredis. Tests: in-memory fake.
 */
export interface GeoRadiusHit {
  member: string;
  /** Distance in kilometers from query point. */
  distanceKm: number;
  longitude: number;
  latitude: number;
}

export interface RedisGeoClient {
  geoadd(
    key: string,
    longitude: number,
    latitude: number,
    member: string,
  ): Promise<number>;
  zrem(key: string, member: string): Promise<number>;
  geopos(
    key: string,
    member: string,
  ): Promise<[string, string] | null>;
  /**
   * N3 — GEORADIUS with ASC WITHCOORD WITHDIST COUNT.
   * Unit is always kilometers.
   */
  georadius(input: {
    key: string;
    longitude: number;
    latitude: number;
    radiusKm: number;
    count: number;
  }): Promise<GeoRadiusHit[]>;
  get(key: string): Promise<string | null>;
  /** Batch string GET (MGET); values align 1:1 with keys. */
  mget(keys: string[]): Promise<(string | null)[]>;
  set(key: string, value: string, ttlSeconds?: number): Promise<'OK'>;
  del(...keys: string[]): Promise<number>;
  /** Optional — used by live proofs / tests. */
  flushdb?(): Promise<'OK'>;
  quit?(): Promise<'OK'>;
}

/** N3 fixed Redis candidate COUNT (not derived from API limit). */
export const N3_REDIS_GEO_COUNT = 100;

/** N3 freshness window (independent of N2C 30s marker TTL). */
export const N3_FRESHNESS_MAX_AGE_MS = 15_000;

/** N3 max accepted location accuracy (metres). */
export const N3_MAX_ACCURACY_M = 50;

export interface DriverOnlineMarker {
  driverId: string;
  lastLocationTs: number;
  accuracy: number;
  city: string | null;
  locationStreamId: string;
  locationSeq: number;
  acceptedAt: string;
}

export const DRIVER_ONLINE_TTL_SECONDS = 30;

/**
 * Coordinate-primary GEO index (N2C/N3 cutover).
 * Matching reads/writes this key; city labels are not the spatial boundary.
 */
export const GEO_DRIVERS_KEY = 'geo:drivers';

/**
 * Legacy city-sharded GEO key — dual-write / offline cleanup only.
 * Not used for N3 matching after coordinate-primary cutover.
 */
export function geoDriversCityKey(city: string): string {
  return `geo:drivers:${city}`;
}

/** @deprecated Prefer GEO_DRIVERS_KEY for matching; retained as alias of city key helper. */
export function geoDriversKey(city: string): string {
  return geoDriversCityKey(city);
}

export function driverOnlineKey(driverId: string): string {
  return `driver:online:${driverId}`;
}

/** Normalize homeCity → slug (trim + lowercase). Optional metadata only for matching. */
export function normalizeCitySlug(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const slug = raw.trim().toLowerCase();
  return slug.length > 0 ? slug : null;
}
