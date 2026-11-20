import { logSafe } from '../http/errors';
import {
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type GeoRadiusHit,
  type RedisGeoClient,
} from '../redis/types';
import {
  GEO_KEY_PRECISION,
  GEO_MAX_CELL_QUERIES,
  choosePrecision,
  coveringCells,
  geohashEncode,
  type GeoBox,
} from './geohash';

/**
 * RTDB geo index (GeoFire-style geohash cells).
 *
 * Layout: `geoPresence/{driverId}` = merged doc mirroring the Firestore
 * geoDrivers schema:
 *   { driverId, g: <geohash8>, lat, lng,
 *     markerValue, markerExpiresAtMs, lastLocationTs, accuracy, expiresAtMs }
 *
 * georadius = N parallel `orderByChild('g')` cell-prefix range queries +
 * exact haversine filter + distance sort. RTDB bills DOWNLOADS only, so
 * presence writes cost $0; only match queries download data.
 *
 * Freshness (`minLastLocationTs`) is applied post-fetch — RTDB can only
 * order on one key. Documented trade-off vs the Firestore client, which
 * pushes the timestamp into its range query: stale in-cell docs cost a
 * few extra bytes of download, never a correctness change (the N3 marker
 * checks re-validate freshness/accuracy per hit anyway).
 */

export interface RtdbSnapshotLike {
  exists(): boolean;
  val(): unknown;
  readonly key: string | null;
  forEach(cb: (child: RtdbSnapshotLike) => boolean | void): boolean;
}

export interface RtdbQueryLike {
  startAt(value: string | number): RtdbQueryLike;
  endAt(value: string | number): RtdbQueryLike;
  limitToFirst(n: number): RtdbQueryLike;
  get(): Promise<RtdbSnapshotLike>;
}

export interface RtdbRefLike {
  child(path: string): RtdbRefLike;
  get(): Promise<RtdbSnapshotLike>;
  set(value: unknown): Promise<unknown>;
  update(value: Record<string, unknown>): Promise<unknown>;
  remove(): Promise<unknown>;
  /** RTDB transaction — update returning undefined aborts (committed:false). */
  transaction(
    update: (current: unknown) => unknown,
  ): Promise<{ committed: boolean; snapshot: RtdbSnapshotLike | null }>;
  orderByChild(key: string): RtdbQueryLike;
}

export interface RtdbGeoClientOptions {
  nowMs?: () => number;
  /** Hard cap on docs scanned across all cells per georadius. */
  scanLimit?: number;
  /** Max cell queries per georadius (default GEO_MAX_CELL_QUERIES). */
  maxCellQueries?: number;
}

const GEO_QUERY_SCAN_LIMIT = 5000;
const EARTH_RADIUS_KM = 6371.0;
const GEO_ROOT = 'geoPresence';

function haversineKm(
  lat1: number, lng1: number, lat2: number, lng2: number,
): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(a)));
}

function kmToLatDegrees(km: number): number {
  return km / 111.32;
}

function kmToLngDegrees(km: number, atLat: number): number {
  const cos = Math.cos((atLat * Math.PI) / 180);
  if (Math.abs(cos) < 1e-6) return 180;
  return Math.min(180, km / (111.32 * cos));
}

export function createRtdbGeoClient(
  rootRef: RtdbRefLike,
  options?: RtdbGeoClientOptions,
): RedisGeoClient & { flushdb(): Promise<'OK'>; quit(): Promise<'OK'> } {
  const geoRef = rootRef.child(GEO_ROOT);
  const now = options?.nowMs ?? Date.now;
  const scanLimit = options?.scanLimit ?? GEO_QUERY_SCAN_LIMIT;
  const maxCellQueries = options?.maxCellQueries ?? GEO_MAX_CELL_QUERIES;

  function isGeoKey(key: string): boolean {
    return key === GEO_DRIVERS_KEY;
  }

  function markerDocId(key: string): string {
    return key.startsWith('driver:online:')
      ? key.slice('driver:online:'.length)
      : key;
  }

  function liveMarkerValue(data: Record<string, unknown>): string | null {
    const expiresAtMs = data.markerExpiresAtMs;
    if (
      typeof expiresAtMs === 'number' &&
      Number.isFinite(expiresAtMs) &&
      now() > expiresAtMs
    ) {
      return null;
    }
    return typeof data.markerValue === 'string' ? data.markerValue : null;
  }

  function markerFields(
    value: string,
    ttlSeconds?: number,
  ): Record<string, unknown> {
    const expiresAtMs = ttlSeconds != null ? now() + ttlSeconds * 1000 : null;
    let lastLocationTs: number | null = null;
    let accuracy: number | null = null;
    try {
      const parsed = JSON.parse(value) as {
        lastLocationTs?: unknown;
        accuracy?: unknown;
      };
      if (
        typeof parsed.lastLocationTs === 'number' &&
        Number.isFinite(parsed.lastLocationTs)
      ) {
        lastLocationTs = parsed.lastLocationTs;
      }
      if (typeof parsed.accuracy === 'number' && Number.isFinite(parsed.accuracy)) {
        accuracy = parsed.accuracy;
      }
    } catch {
      // Non-JSON marker — N3 parseMarker rejects it identically.
    }
    return {
      markerValue: value,
      markerExpiresAtMs: expiresAtMs,
      lastLocationTs,
      accuracy,
      // Sweeper index (storage hygiene — matching never depends on it).
      expiresAtMs,
    };
  }

  function nodeData(snap: RtdbSnapshotLike): Record<string, unknown> | null {
    if (!snap.exists()) return null;
    const v = snap.val();
    return v && typeof v === 'object' ? (v as Record<string, unknown>) : null;
  }

  return {
    async geoadd(key, longitude, latitude, member) {
      if (!isGeoKey(key)) return 1;
      // update() merges — standalone geoadd must not wipe marker fields.
      await geoRef.child(member).update({
        driverId: member,
        g: geohashEncode(latitude, longitude),
        lat: latitude,
        lng: longitude,
      });
      return 1;
    },

    async projectLocation(input) {
      if (!isGeoKey(input.key)) return 'skipped';
      const fields = {
        driverId: input.member,
        g: geohashEncode(input.latitude, input.longitude),
        lat: input.latitude,
        lng: input.longitude,
        ...markerFields(input.markerValue, input.markerTtlSeconds),
      };
      const ref = geoRef.child(input.member);
      if (!input.markerGuard) {
        await ref.update(fields);
        return 'written';
      }
      // Guard + write inside ONE RTDB transaction — atomic per node.
      const result = await ref.transaction((current) => {
        const data =
          current && typeof current === 'object'
            ? (current as Record<string, unknown>)
            : null;
        const decision = input.markerGuard!({
          latitude: typeof data?.lat === 'number' ? data.lat : NaN,
          longitude: typeof data?.lng === 'number' ? data.lng : NaN,
          markerValue: data ? liveMarkerValue(data) : null,
        });
        if (decision === 'skip') return undefined; // abort
        return fields;
      });
      return result.committed ? 'written' : 'skipped';
    },

    async zrem(key, member) {
      if (!isGeoKey(key)) return 0;
      const ref = geoRef.child(member);
      const snap = await ref.get();
      if (!snap.exists()) return 0;
      await ref.remove();
      return 1;
    },

    async geopos(key, member) {
      if (!isGeoKey(key)) return null;
      const snap = await geoRef.child(member).get();
      const data = nodeData(snap);
      if (
        !data ||
        typeof data.lat !== 'number' ||
        typeof data.lng !== 'number'
      ) {
        return null;
      }
      return [String(data.lng), String(data.lat)];
    },

    async georadius(input) {
      if (!isGeoKey(input.key)) return [];
      const latDelta = kmToLatDegrees(input.radiusKm);
      const lngDelta = kmToLngDegrees(input.radiusKm, input.latitude);
      const box: GeoBox = {
        minLat: Math.max(-90, input.latitude - latDelta),
        maxLat: Math.min(90, input.latitude + latDelta),
        minLng: input.longitude - lngDelta,
        maxLng: input.longitude + lngDelta,
      };
      const precision = choosePrecision(box, maxCellQueries);
      const cells = coveringCells(box, precision);
      if (cells.length > maxCellQueries) {
        // Shouldn't happen (choosePrecision bounds it) — defensive degrade:
        // fall back to a coarser precision rather than issuing unbounded
        // queries that would silently truncate the candidate set.
        logSafe('GEORADIUS_CELL_OVERFLOW', {
          precision, cells: cells.length, maxCellQueries,
        });
      }

      const results = await Promise.all(
        cells.slice(0, maxCellQueries).map((cell) =>
          geoRef
            .orderByChild('g')
            .startAt(cell)
            .endAt(`${cell}~`) // '~' > all base32 chars — prefix range
            .get(),
        ),
      );

      // Dedupe by driverId — bbox edge cells can legitimately overlap.
      const docsById = new Map<string, Record<string, unknown>>();
      let scanned = 0;
      let capped = false;
      for (const snap of results) {
        snap.forEach((childSnap) => {
          if (scanned >= scanLimit) {
            capped = true;
            return true; // stop iterating this snapshot
          }
          const data =
            childSnap.val() && typeof childSnap.val() === 'object'
              ? (childSnap.val() as Record<string, unknown>)
              : null;
          if (data && childSnap.key) {
            docsById.set(childSnap.key, data);
            scanned += 1;
          }
          return false;
        });
      }
      if (capped) {
        logSafe('GEORADIUS_SCAN_CAPPED', { scanLimit, cells: cells.length });
      }

      const minTs = input.minLastLocationTs;
      const hits: GeoRadiusHit[] = [];
      for (const [driverId, data] of docsById) {
        if (typeof data.lat !== 'number' || typeof data.lng !== 'number') {
          continue;
        }
        // Post-fetch freshness floor (RTDB can't push a second range into
        // the query — documented trade-off, same eligibility outcome).
        if (
          minTs != null &&
          !(typeof data.lastLocationTs === 'number' && data.lastLocationTs > minTs)
        ) {
          continue;
        }
        const distanceKm = haversineKm(
          input.latitude, input.longitude, data.lat, data.lng,
        );
        if (distanceKm > input.radiusKm) continue;
        hits.push({
          member: driverId,
          distanceKm,
          longitude: data.lng,
          latitude: data.lat,
          markerValue: liveMarkerValue(data),
        });
      }
      hits.sort((a, b) => a.distanceKm - b.distanceKm);
      return hits.slice(0, input.count);
    },

    async get(key) {
      const snap = await geoRef.child(markerDocId(key)).get();
      const data = nodeData(snap);
      return data ? liveMarkerValue(data) : null;
    },

    async mget(keys) {
      // RTDB has no getAll — parallel single-doc reads.
      const getOne = async (key: string) => {
        const snap = await geoRef.child(markerDocId(key)).get();
        const data = nodeData(snap);
        return data ? liveMarkerValue(data) : null;
      };
      return Promise.all(keys.map(getOne));
    },

    async set(key, value, ttlSeconds) {
      // update() merges — standalone set must not wipe geo coords.
      await geoRef
        .child(markerDocId(key))
        .update(markerFields(value, ttlSeconds));
      return 'OK';
    },

    async del(...keys) {
      let removed = 0;
      for (const key of keys) {
        const ref = geoRef.child(markerDocId(key));
        const snap = await ref.get();
        if (!snap.exists()) continue;
        // null = field delete — mirrors Redis DEL leaving GEO membership.
        await ref.update({
          markerValue: null,
          markerExpiresAtMs: null,
          lastLocationTs: null,
          accuracy: null,
          expiresAtMs: null,
        });
        removed += 1;
      }
      return removed;
    },

    /**
     * Storage hygiene: physically remove fully-expired presence nodes.
     * Matching never depends on this (TTL enforced on read) — it only
     * bounds geoPresence growth. Requires `.indexOn: 'expiresAtMs'`.
     */
    async sweepExpired(nowMs?: number): Promise<number> {
      const cutoff = nowMs ?? now();
      const snap = await geoRef
        .orderByChild('expiresAtMs')
        .endAt(cutoff)
        .get();
      let removed = 0;
      const jobs: Promise<unknown>[] = [];
      snap.forEach((childSnap) => {
        if (childSnap.key) {
          jobs.push(geoRef.child(childSnap.key).remove());
          removed += 1;
        }
        return false;
      });
      await Promise.all(jobs);
      return removed;
    },

    async flushdb() {
      await geoRef.remove();
      return 'OK';
    },

    async quit() {
      return 'OK';
    },
  };
}
