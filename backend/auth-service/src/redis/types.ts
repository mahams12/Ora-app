/**
 * Minimal Redis command surface for N2C GEO projection.
 * Real: ioredis. Tests: in-memory fake.
 */
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
  get(key: string): Promise<string | null>;
  set(key: string, value: string, ttlSeconds?: number): Promise<'OK'>;
  del(...keys: string[]): Promise<number>;
  /** Optional — used by live proofs / tests. */
  flushdb?(): Promise<'OK'>;
  quit?(): Promise<'OK'>;
}

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

export function geoDriversKey(city: string): string {
  return `geo:drivers:${city}`;
}

export function driverOnlineKey(driverId: string): string {
  return `driver:online:${driverId}`;
}

/** Normalize homeCity → GEO slug (trim + lowercase). */
export function normalizeCitySlug(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const slug = raw.trim().toLowerCase();
  return slug.length > 0 ? slug : null;
}
