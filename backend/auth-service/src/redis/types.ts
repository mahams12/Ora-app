/**
 * Minimal Redis command surface for N2C GEO projection + N3 GEORADIUS read.
 * Real: FirestoreGeoClient. Tests: in-memory fake.
 */
export interface GeoRadiusHit {
  member: string;
  /** Distance in kilometers from query point. */
  distanceKm: number;
  longitude: number;
  latitude: number;
  /**
   * Optional: online-marker value read from the same document the geo hit was
   * scanned from (Firestore client only — Redis GEORADIUS cannot return it).
   * Present-but-null means the marker is missing/expired (no refetch needed);
   * absent means the caller must fetch it separately (MGET).
   */
  markerValue?: string | null;
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
    /**
     * Optional server-side freshness floor: only return docs whose stored
     * lastLocationTs is strictly newer. Firestore client applies it as a range
     * filter (cutting billed reads); Redis GEORADIUS ignores it (caller-side
     * marker checks still enforce freshness identically).
     */
    minLastLocationTs?: number;
    /**
     * Adaptive-freshness variant: only return docs whose stored per-driver
     * freshUntilMs is strictly in the future. Firestore client applies it as
     * a range filter on the freshUntilMs twin (written on every marker doc);
     * takes precedence over minLastLocationTs when both are provided.
     */
    minFreshUntilMs?: number;
  }): Promise<GeoRadiusHit[]>;
  get(key: string): Promise<string | null>;
  /** Batch string GET (MGET); values align 1:1 with keys. */
  mget(keys: string[]): Promise<(string | null)[]>;
  set(key: string, value: string, ttlSeconds?: number): Promise<'OK'>;
  del(...keys: string[]): Promise<number>;
  /**
   * Optional hot-path write: GEO membership + online marker in one store
   * round-trip (N2C runs this every accepted GPS packet). Callers fall back
   * to geoadd + set when absent.
   */
  projectLocation?(input: {
    key: string;
    member: string;
    longitude: number;
    latitude: number;
    markerKey: string;
    markerValue: string;
    markerTtlSeconds?: number;
    /**
     * Optional atomic marker guard. Implementations evaluate it against the
     * CURRENTLY STORED marker while holding the write (same transaction —
     * no check-then-act gap between read and write). Return 'skip' to abort
     * the write; the existing projection is left untouched. When omitted
     * the write is unconditional.
     */
    markerGuard?: (existing: {
      latitude: number;
      longitude: number;
      markerValue: string | null;
    }) => 'write' | 'skip';
    /**
     * Merged idle-stream cursor (cost-optimization Phase B): when present the
     * implementation validates + advances the idle stream cursor inside the
     * SAME write/transaction as the marker+geo update, replacing the separate
     * locationStreams/{driverId} cursor accept. Violations throw
     * LocationDomainError (SEQUENCE_VIOLATION) — they must NOT be swallowed
     * like ordinary projection failures.
     */
    idleCursor?: {
      locationStreamId: string;
      locationSeq: number;
      updatedAtIso: string;
      expiresAtIso: string;
    };
  }): Promise<'written' | 'skipped'>;
  /**
   * Capability marker: the projectLocation implementation honors idleCursor
   * (merged idle-stream validation inside the write transaction). Callers
   * MUST NOT pass idleCursor to clients that don't declare this — cursor
   * validation would be silently skipped.
   */
  supportsIdleCursor?: boolean;
  /**
   * Optional storage-hygiene sweep — physically remove fully-expired
   * presence records. Matching never depends on this (TTL is enforced on
   * read); it only bounds index growth. Implemented by the RTDB client.
   */
  sweepExpired?(nowMs?: number): Promise<number>;
  /** Optional — used by live proofs / tests. */
  flushdb?(): Promise<'OK'>;
  quit?(): Promise<'OK'>;
}

/** N3 fixed Redis candidate COUNT (not derived from API limit). */
export const N3_REDIS_GEO_COUNT = 100;

/** N3 freshness window (independent of N2C 30s marker TTL). */
export const N3_FRESHNESS_MAX_AGE_MS = 15_000;

/**
 * Adaptive freshness (cost-optimization Phase A). When
 * LOCATION_ADAPTIVE_FRESHNESS is on and the client declares its current
 * publish interval, marker expiry is computed per driver as
 * lastLocationTs + interval + grace instead of a fixed 15s window.
 * Grace covers one missed publish + transport latency — bounded so a dead
 * driver can never linger in matching past interval + grace.
 */
export const N3_FRESHNESS_GRACE_MS = 15_000;
export const N3_MIN_PUBLISH_INTERVAL_MS = 4_000;
export const N3_MAX_PUBLISH_INTERVAL_MS = 60_000;

/**
 * Honest-position bound — the maximum age of the underlying GPS fix a
 * marker may claim for matching/eligibility. Independent of presence
 * freshness: a keepalive re-asserts an OLD fix (original timestamp) to keep
 * the driver's presence alive; this cap is what stops a stale position
 * from being treated as a current location at invite time. Sized to the
 * client keepaliveMaxFixAge (90 s) + transport margin.
 */
export const N3_MAX_FIX_AGE_MS = 120_000;

/** Clamp a client-declared publish interval into the accepted range. */
export function clampPublishIntervalMs(raw: unknown): number | null {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return null;
  return Math.min(
    N3_MAX_PUBLISH_INTERVAL_MS,
    Math.max(N3_MIN_PUBLISH_INTERVAL_MS, Math.round(raw)),
  );
}

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
  /**
   * Adaptive freshness — server-computed marker expiry
   * (lastLocationTs + declared interval + grace). Present only when the
   * client declared publishIntervalMs and LOCATION_ADAPTIVE_FRESHNESS is on.
   */
  freshUntilMs?: number;
  /** Client-declared publish cadence actually honored (clamped). */
  publishIntervalMs?: number;
  /** Presence keepalive — client re-asserted a stale-coord fix (adaptive only). */
  keepalive?: boolean;
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
