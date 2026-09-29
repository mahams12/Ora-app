import type { Firestore } from 'firebase-admin/firestore';
import {
  GEO_DRIVERS_KEY,
  N3_FRESHNESS_MAX_AGE_MS,
  N3_MAX_ACCURACY_M,
  N3_REDIS_GEO_COUNT,
  driverOnlineKey,
  normalizeCitySlug,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../redis/types';
import { logSafe } from '../http/errors';

const USERS = 'users';
const DRIVERS = 'drivers';
const RIDES = 'rides';

export const N3_BUSY_RIDE_STATES = [
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
] as const;

export const N3_DEFAULT_RADIUS_KM = 10;
export const N3_MIN_RADIUS_KM = 1;
export const N3_MAX_RADIUS_KM = 25;
export const N3_DEFAULT_LIMIT = 30;
export const N3_MAX_LIMIT = 100;
export const N3_MIN_LIMIT = 1;

export class NearbyDomainError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'NearbyDomainError';
  }
}

export interface NearbyCandidate {
  driverId: string;
  distanceKm: number;
  lat: number;
  lng: number;
  lastLocationTs: number;
  accuracy: number;
}

export interface NearbyResult {
  /** Optional echo only — never used for GEO matching. */
  city?: string;
  pickup: { lat: number; lng: number };
  radiusKm: number;
  candidates: NearbyCandidate[];
}

function singleQueryValue(
  value: unknown,
  field: string,
): string | undefined {
  if (value === undefined) return undefined;
  if (Array.isArray(value)) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      `Query parameter ${field} must be a single value.`,
    );
  }
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      `Query parameter ${field} is invalid.`,
    );
  }
  return String(value);
}

function parseFiniteNumber(raw: string, field: string): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must be a finite number.`,
    );
  }
  return n;
}

/**
 * Coordinate-primary nearby query.
 * `city` is optional metadata (ignored for matching) for backward-compatible callers.
 */
export function parseNearbyQuery(query: Record<string, unknown>): {
  city?: string;
  lat: number;
  lng: number;
  radiusKm: number;
  limit: number;
} {
  const allowed = new Set(['city', 'lat', 'lng', 'radiusKm', 'limit']);
  const extra = Object.keys(query).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      `Unknown or forbidden query parameters: ${extra.join(', ')}.`,
    );
  }

  let city: string | undefined;
  const cityRaw = singleQueryValue(query.city, 'city');
  if (cityRaw !== undefined) {
    const slug = normalizeCitySlug(cityRaw);
    if (slug) city = slug;
  }

  const latRaw = singleQueryValue(query.lat, 'lat');
  const lngRaw = singleQueryValue(query.lng, 'lng');
  if (latRaw === undefined || lngRaw === undefined) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      'lat and lng are required.',
    );
  }
  const lat = parseFiniteNumber(latRaw, 'lat');
  const lng = parseFiniteNumber(lngRaw, 'lng');
  if (lat < -90 || lat > 90) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      'lat out of range.',
    );
  }
  if (lng < -180 || lng > 180) {
    throw new NearbyDomainError(
      'VALIDATION_ERROR',
      400,
      'lng out of range.',
    );
  }

  let radiusKm = N3_DEFAULT_RADIUS_KM;
  const radiusRaw = singleQueryValue(query.radiusKm, 'radiusKm');
  if (radiusRaw !== undefined) {
    radiusKm = parseFiniteNumber(radiusRaw, 'radiusKm');
    if (radiusKm < N3_MIN_RADIUS_KM || radiusKm > N3_MAX_RADIUS_KM) {
      throw new NearbyDomainError(
        'VALIDATION_ERROR',
        400,
        `radiusKm must be between ${N3_MIN_RADIUS_KM} and ${N3_MAX_RADIUS_KM}.`,
      );
    }
  }

  let limit = N3_DEFAULT_LIMIT;
  const limitRaw = singleQueryValue(query.limit, 'limit');
  if (limitRaw !== undefined) {
    if (!/^\d+$/.test(limitRaw)) {
      throw new NearbyDomainError(
        'VALIDATION_ERROR',
        400,
        `limit must be an integer between ${N3_MIN_LIMIT} and ${N3_MAX_LIMIT}.`,
      );
    }
    limit = Number(limitRaw);
    if (
      !Number.isInteger(limit) ||
      limit < N3_MIN_LIMIT ||
      limit > N3_MAX_LIMIT
    ) {
      throw new NearbyDomainError(
        'VALIDATION_ERROR',
        400,
        `limit must be an integer between ${N3_MIN_LIMIT} and ${N3_MAX_LIMIT}.`,
      );
    }
  }

  return { city, lat, lng, radiusKm, limit };
}

function parseMarker(raw: string): DriverOnlineMarker | null {
  try {
    const parsed = JSON.parse(raw) as DriverOnlineMarker;
    if (
      typeof parsed.lastLocationTs !== 'number' ||
      !Number.isFinite(parsed.lastLocationTs) ||
      typeof parsed.accuracy !== 'number' ||
      !Number.isFinite(parsed.accuracy)
    ) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function isFresh(lastLocationTs: number, nowMs: number): boolean {
  const age = nowMs - lastLocationTs;
  return age >= 0 && age <= N3_FRESHNESS_MAX_AGE_MS;
}

/**
 * N3 — nearby driver candidate discovery (internal worker only).
 * Coordinate-primary: GEORADIUS on `geo:drivers` — city does not gate matching.
 */
export class NearbyDriversService {
  constructor(
    private readonly db: Firestore,
    private readonly redis: RedisGeoClient | null,
  ) {}

  async findNearby(input: {
    query: Record<string, unknown>;
    requestId?: string;
    nowMs?: number;
  }): Promise<NearbyResult> {
    const parsed = parseNearbyQuery(input.query);
    const nowMs = input.nowMs ?? Date.now();

    if (!this.redis) {
      throw new NearbyDomainError(
        'DEPENDENCY_ERROR',
        503,
        'Nearby candidate generation is temporarily unavailable.',
      );
    }

    let geoHits;
    try {
      geoHits = await this.redis.georadius({
        key: GEO_DRIVERS_KEY,
        longitude: parsed.lng,
        latitude: parsed.lat,
        radiusKm: parsed.radiusKm,
        count: N3_REDIS_GEO_COUNT,
      });
    } catch (err) {
      logSafe('N3_REDIS_GEORADIUS_FAILED', {
        requestId: input.requestId ?? null,
        geoKey: GEO_DRIVERS_KEY,
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      throw new NearbyDomainError(
        'DEPENDENCY_ERROR',
        503,
        'Nearby candidate generation is temporarily unavailable.',
      );
    }

    const surviving: NearbyCandidate[] = [];

    for (const hit of geoHits) {
      if (surviving.length >= parsed.limit) break;

      let markerRaw: string | null;
      try {
        markerRaw = await this.redis.get(driverOnlineKey(hit.member));
      } catch (err) {
        logSafe('N3_REDIS_MARKER_FAILED', {
          requestId: input.requestId ?? null,
          driverId: hit.member,
          errorType: err instanceof Error ? err.name : 'unknown',
        });
        throw new NearbyDomainError(
          'DEPENDENCY_ERROR',
          503,
          'Nearby candidate generation is temporarily unavailable.',
        );
      }

      if (!markerRaw) continue;
      const marker = parseMarker(markerRaw);
      if (!marker) continue;
      if (!isFresh(marker.lastLocationTs, nowMs)) continue;
      if (marker.accuracy > N3_MAX_ACCURACY_M) continue;

      // city / homeCity MUST NOT gate matching (coordinate-primary).

      const eligible = await this.isAuthoritativelyEligible(hit.member);
      if (!eligible) continue;

      surviving.push({
        driverId: hit.member,
        distanceKm: hit.distanceKm,
        lat: hit.latitude,
        lng: hit.longitude,
        lastLocationTs: marker.lastLocationTs,
        accuracy: marker.accuracy,
      });
    }

    return {
      ...(parsed.city != null ? { city: parsed.city } : {}),
      pickup: { lat: parsed.lat, lng: parsed.lng },
      radiusKm: parsed.radiusKm,
      candidates: surviving,
    };
  }

  /**
   * N4 invite-time revalidation: Redis marker freshness/accuracy + Firestore
   * authoritative eligibility. Does NOT check city/homeCity.
   */
  async isStillEligibleForInvite(
    driverId: string,
    opts?: { nowMs?: number; requestId?: string },
  ): Promise<boolean> {
    const nowMs = opts?.nowMs ?? Date.now();

    if (!this.redis) {
      throw new NearbyDomainError(
        'DEPENDENCY_ERROR',
        503,
        'Nearby candidate generation is temporarily unavailable.',
      );
    }

    let markerRaw: string | null;
    try {
      markerRaw = await this.redis.get(driverOnlineKey(driverId));
    } catch (err) {
      logSafe('N3_REDIS_MARKER_FAILED', {
        requestId: opts?.requestId ?? null,
        driverId,
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      throw new NearbyDomainError(
        'DEPENDENCY_ERROR',
        503,
        'Nearby candidate generation is temporarily unavailable.',
      );
    }

    if (!markerRaw) return false;
    const marker = parseMarker(markerRaw);
    if (!marker) return false;
    if (!isFresh(marker.lastLocationTs, nowMs)) return false;
    if (marker.accuracy > N3_MAX_ACCURACY_M) return false;

    return this.isAuthoritativelyEligible(driverId);
  }

  private async isAuthoritativelyEligible(driverId: string): Promise<boolean> {
    const userSnap = await this.db.collection(USERS).doc(driverId).get();
    if (!userSnap.exists) return false;
    const user = userSnap.data() ?? {};
    if (user.banned === true) return false;
    if (user.isActive === false) return false;
    if (user.role !== 'driver' || user.driverStatus !== 'approved') {
      return false;
    }

    const driverSnap = await this.db.collection(DRIVERS).doc(driverId).get();
    if (!driverSnap.exists) return false;
    const driver = driverSnap.data() ?? {};
    if (driver.availabilityState !== 'online') return false;

    const busySnap = await this.db
      .collection(RIDES)
      .where('assignedDriverId', '==', driverId)
      .where('state', 'in', [...N3_BUSY_RIDE_STATES])
      .limit(1)
      .get();
    if (!busySnap.empty) return false;

    return true;
  }
}
