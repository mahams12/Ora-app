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

/** Firestore `in` disjunction limit for assignedDriverId batch busy prefetch. */
export const N3_BUSY_PREFETCH_IN_CHUNK_SIZE = 30;

/** Firestore `in` disjunction limit for assignedDriverId batch busy prefetch. */
export const N3_FIRESTORE_IN_QUERY_MAX = 30;

/** Max document references per Firestore `getAll` batch. */
export const N3_FIRESTORE_GETALL_MAX = 100;

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

/** Bounded rejection buckets for N3 observability (aggregate log only). */
export const N3_REJECTION_BUCKETS = [
  'marker_missing',
  'marker_malformed',
  'marker_not_fresh',
  'marker_accuracy',
  'user_missing',
  'user_banned',
  'user_inactive',
  'user_not_approved',
  'driver_missing',
  'driver_offline',
  'driver_busy',
] as const;

export type N3RejectionBucket = (typeof N3_REJECTION_BUCKETS)[number];

export type N3RejectionCounts = Record<N3RejectionBucket, number>;

export interface N3NearbyDiagnostics {
  geoHits: number;
  /** One batched marker read (MGET) per findNearby when geoHits > 0. */
  redisGetCount: number;
  /** Logical user documents read (batch getAll document count). */
  firestoreUsersReads: number;
  /** Logical driver documents read (batch getAll document count). */
  firestoreDriversReads: number;
  /** Firestore `getAll` RPC count for users collection. */
  firestoreUsersBatchRpcs: number;
  /** Firestore `getAll` RPC count for drivers collection. */
  firestoreDriversBatchRpcs: number;
  firestoreBusyRideQueries: number;
  /** Sum of batch getAll RPCs + busy batch queries (+ per-driver reads on N4-only paths). */
  firestoreRpcTotal: number;
  eligibleCount: number;
  rejected: N3RejectionCounts;
}

/** Aggregate Firestore RPC round-trips from N3 diagnostics. */
export function computeN3FirestoreRpcTotal(d: N3NearbyDiagnostics): number {
  return (
    d.firestoreUsersBatchRpcs +
    d.firestoreDriversBatchRpcs +
    d.firestoreBusyRideQueries
  );
}

export function createEmptyN3RejectionCounts(): N3RejectionCounts {
  return {
    marker_missing: 0,
    marker_malformed: 0,
    marker_not_fresh: 0,
    marker_accuracy: 0,
    user_missing: 0,
    user_banned: 0,
    user_inactive: 0,
    user_not_approved: 0,
    driver_missing: 0,
    driver_offline: 0,
    driver_busy: 0,
  };
}

export function createEmptyN3NearbyDiagnostics(): N3NearbyDiagnostics {
  return {
    geoHits: 0,
    redisGetCount: 0,
    firestoreUsersReads: 0,
    firestoreDriversReads: 0,
    firestoreUsersBatchRpcs: 0,
    firestoreDriversBatchRpcs: 0,
    firestoreBusyRideQueries: 0,
    firestoreRpcTotal: 0,
    eligibleCount: 0,
    rejected: createEmptyN3RejectionCounts(),
  };
}

/** Omit zero-valued rejection buckets to keep logs small. */
export function compactN3RejectionCounts(
  rejected: N3RejectionCounts,
): Partial<N3RejectionCounts> {
  const out: Partial<N3RejectionCounts> = {};
  for (const key of N3_REJECTION_BUCKETS) {
    if (rejected[key] > 0) out[key] = rejected[key];
  }
  return out;
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

/** First-seen GEO order; duplicate member IDs appear once. */
export function uniqueGeoMemberIdsInOrder(
  geoHits: ReadonlyArray<{ member: string }>,
): string[] {
  const seen = new Set<string>();
  const ordered: string[] = [];
  for (const hit of geoHits) {
    if (seen.has(hit.member)) continue;
    seen.add(hit.member);
    ordered.push(hit.member);
  }
  return ordered;
}

export type N3PrefetchedAuthoritativeDocs = {
  userByDriverId: Map<string, Record<string, unknown> | null>;
  driverByDriverId: Map<string, Record<string, unknown> | null>;
};

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
    /** Optional sink for aggregate diagnostics (not included in API response). */
    collectDiagnostics?: (diagnostics: N3NearbyDiagnostics) => void;
  }): Promise<NearbyResult> {
    const parsed = parseNearbyQuery(input.query);
    const nowMs = input.nowMs ?? Date.now();
    const diag = createEmptyN3NearbyDiagnostics();

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

    diag.geoHits = geoHits.length;
    const surviving: NearbyCandidate[] = [];

    const markerByMember = new Map<string, string | null>();
    if (geoHits.length > 0) {
      const markerKeys = geoHits.map((hit) => driverOnlineKey(hit.member));
      try {
        const markerValues = await this.redis.mget(markerKeys);
        diag.redisGetCount += 1;
        for (let i = 0; i < geoHits.length; i++) {
          markerByMember.set(geoHits[i].member, markerValues[i] ?? null);
        }
      } catch (err) {
        logSafe('N3_REDIS_MARKER_FAILED', {
          requestId: input.requestId ?? null,
          driverId: geoHits[0]?.member ?? null,
          errorType: err instanceof Error ? err.name : 'unknown',
        });
        throw new NearbyDomainError(
          'DEPENDENCY_ERROR',
          503,
          'Nearby candidate generation is temporarily unavailable.',
        );
      }
    }

    const geoMemberIds = geoHits.map((hit) => hit.member);
    const busyDriverIds = await this.prefetchBusyDriverIds(geoMemberIds, diag);
    const orderedUniqueGeoIds = uniqueGeoMemberIdsInOrder(geoHits);
    const prefetched = await this.prefetchAuthoritativeDocuments(
      orderedUniqueGeoIds,
      diag,
    );
    diag.firestoreRpcTotal = computeN3FirestoreRpcTotal(diag);

    for (const hit of geoHits) {
      if (surviving.length >= parsed.limit) break;

      const markerRaw = markerByMember.get(hit.member) ?? null;

      if (!markerRaw) {
        diag.rejected.marker_missing += 1;
        continue;
      }
      const marker = parseMarker(markerRaw);
      if (!marker) {
        diag.rejected.marker_malformed += 1;
        continue;
      }
      if (!isFresh(marker.lastLocationTs, nowMs)) {
        diag.rejected.marker_not_fresh += 1;
        continue;
      }
      if (marker.accuracy > N3_MAX_ACCURACY_M) {
        diag.rejected.marker_accuracy += 1;
        continue;
      }

      // city / homeCity MUST NOT gate matching (coordinate-primary).

      const eligible = await this.isAuthoritativelyEligible(hit.member, diag, {
        busyDriverIds,
        prefetched,
      });
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

    diag.eligibleCount = surviving.length;
    diag.firestoreRpcTotal = computeN3FirestoreRpcTotal(diag);
    input.collectDiagnostics?.(diag);

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

  /** Batch busy-ride lookup for geo member IDs (N3 findNearby only). */
  private async prefetchBusyDriverIds(
    driverIds: string[],
    diag?: N3NearbyDiagnostics,
  ): Promise<Set<string>> {
    const busy = new Set<string>();
    if (driverIds.length === 0) {
      return busy;
    }
    const unique = [...new Set(driverIds)];
    for (let i = 0; i < unique.length; i += N3_BUSY_PREFETCH_IN_CHUNK_SIZE) {
      const chunk = unique.slice(i, i + N3_BUSY_PREFETCH_IN_CHUNK_SIZE);
      if (diag) diag.firestoreBusyRideQueries += 1;
      const snap = await this.db
        .collection(RIDES)
        .where('assignedDriverId', 'in', chunk)
        .get();
      for (const doc of snap.docs) {
        const data = doc.data() ?? {};
        const state = data.state;
        if (
          typeof state !== 'string' ||
          !(N3_BUSY_RIDE_STATES as readonly string[]).includes(state)
        ) {
          continue;
        }
        const assigned = data.assignedDriverId;
        if (typeof assigned === 'string' && assigned.length > 0) {
          busy.add(assigned);
        }
      }
    }
    return busy;
  }

  /** N3 findNearby: batch users + drivers via sequential getAll (GEO-unique IDs). */
  private async prefetchAuthoritativeDocuments(
    orderedUniqueDriverIds: string[],
    diag: N3NearbyDiagnostics,
  ): Promise<N3PrefetchedAuthoritativeDocs> {
    const userByDriverId = new Map<string, Record<string, unknown> | null>();
    const driverByDriverId = new Map<string, Record<string, unknown> | null>();
    if (orderedUniqueDriverIds.length === 0) {
      return { userByDriverId, driverByDriverId };
    }

    for (let i = 0; i < orderedUniqueDriverIds.length; i += N3_FIRESTORE_GETALL_MAX) {
      const chunk = orderedUniqueDriverIds.slice(i, i + N3_FIRESTORE_GETALL_MAX);
      const userRefs = chunk.map((id) => this.db.collection(USERS).doc(id));
      diag.firestoreUsersBatchRpcs += 1;
      const userSnaps = await this.db.getAll(...userRefs);
      diag.firestoreUsersReads += userSnaps.length;
      for (const snap of userSnaps) {
        userByDriverId.set(
          snap.id,
          snap.exists ? (snap.data() ?? {}) : null,
        );
      }
    }

    for (let i = 0; i < orderedUniqueDriverIds.length; i += N3_FIRESTORE_GETALL_MAX) {
      const chunk = orderedUniqueDriverIds.slice(i, i + N3_FIRESTORE_GETALL_MAX);
      const driverRefs = chunk.map((id) => this.db.collection(DRIVERS).doc(id));
      diag.firestoreDriversBatchRpcs += 1;
      const driverSnaps = await this.db.getAll(...driverRefs);
      diag.firestoreDriversReads += driverSnaps.length;
      for (const snap of driverSnaps) {
        driverByDriverId.set(
          snap.id,
          snap.exists ? (snap.data() ?? {}) : null,
        );
      }
    }

    return { userByDriverId, driverByDriverId };
  }

  private async isAuthoritativelyEligible(
    driverId: string,
    diag?: N3NearbyDiagnostics,
    opts?: {
      busyDriverIds?: Set<string>;
      prefetched?: N3PrefetchedAuthoritativeDocs;
    },
  ): Promise<boolean> {
    let user: Record<string, unknown> | undefined;
    if (opts?.prefetched) {
      const entry = opts.prefetched.userByDriverId.get(driverId);
      if (entry === undefined || entry === null) {
        if (diag) diag.rejected.user_missing += 1;
        return false;
      }
      user = entry;
    } else {
      if (diag) diag.firestoreUsersReads += 1;
      const userSnap = await this.db.collection(USERS).doc(driverId).get();
      if (!userSnap.exists) {
        if (diag) diag.rejected.user_missing += 1;
        return false;
      }
      user = userSnap.data() ?? {};
    }
    if (user.banned === true) {
      if (diag) diag.rejected.user_banned += 1;
      return false;
    }
    if (user.isActive === false) {
      if (diag) diag.rejected.user_inactive += 1;
      return false;
    }
    if (user.role !== 'driver' || user.driverStatus !== 'approved') {
      if (diag) diag.rejected.user_not_approved += 1;
      return false;
    }

    let driver: Record<string, unknown> | undefined;
    if (opts?.prefetched) {
      const entry = opts.prefetched.driverByDriverId.get(driverId);
      if (entry === undefined || entry === null) {
        if (diag) diag.rejected.driver_missing += 1;
        return false;
      }
      driver = entry;
    } else {
      if (diag) diag.firestoreDriversReads += 1;
      const driverSnap = await this.db.collection(DRIVERS).doc(driverId).get();
      if (!driverSnap.exists) {
        if (diag) diag.rejected.driver_missing += 1;
        return false;
      }
      driver = driverSnap.data() ?? {};
    }
    if (driver.availabilityState !== 'online') {
      if (diag) diag.rejected.driver_offline += 1;
      return false;
    }

    if (opts?.busyDriverIds) {
      if (opts.busyDriverIds.has(driverId)) {
        if (diag) diag.rejected.driver_busy += 1;
        return false;
      }
      return true;
    }

    if (diag) diag.firestoreBusyRideQueries += 1;
    const busySnap = await this.db
      .collection(RIDES)
      .where('assignedDriverId', '==', driverId)
      .where('state', 'in', [...N3_BUSY_RIDE_STATES])
      .limit(1)
      .get();
    if (!busySnap.empty) {
      if (diag) diag.rejected.driver_busy += 1;
      return false;
    }

    return true;
  }
}
