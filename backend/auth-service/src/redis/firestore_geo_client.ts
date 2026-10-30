import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logSafe } from '../http/errors';
import {
  GEO_DRIVERS_KEY,
  type GeoRadiusHit,
  type RedisGeoClient,
} from './types';

/**
 * Firestore-native implementation of the RedisGeoClient port.
 *
 * Why this exists: the geo index + online markers are a derived, rebuildable
 * projection (Firestore users/drivers remain authoritative), so they can live
 * in Firestore itself. This removes the always-on Memorystore + VPC connector
 * (~$84/mo standing cost) in exchange for per-document billing that stays
 * inside the free tier at test scale.
 *
 * Single-document schema — geo membership AND the online marker share one
 * document so the hot path (every accepted GPS packet) costs one write:
 *   geoDrivers/{driverId} = {
 *     driverId, lat, lng,                       // geo:drivers member
 *     markerValue?, markerExpiresAtMs?,          // driver:online:{id}
 *     lastLocationTs?, accuracy?,                // top-level twins of marker JSON
 *                                                // fields so georadius can filter
 *                                                // freshness server-side (reads)
 *     expiresAt?                                 // Timestamp twin for TTL policy
 *   }
 *
 * Key mapping:
 *   `geo:drivers`            -> geoDrivers collection (doc id = member)
 *   `geo:drivers:{city}`     -> ignored (legacy dual-write; never read by N3)
 *   `driver:online:{id}`     -> markerValue/markerExpiresAtMs on geoDrivers/{id}
 *
 * Semantics preserved:
 * - GEO membership persists until zrem; marker freshness is enforced by
 *   NearbyDriversService (unchanged) plus read-time expiresAtMs checks here.
 * - del() removes ONLY marker fields — matching Redis, where DEL on the
 *   string leaves GEO membership untouched until zrem.
 * - georadius uses a lat/lng bounding-box query then exact haversine filter +
 *   distance-asc sort — same output as GEORADIUS ... ASC WITHDIST COUNT n.
 *
 * Required composite index: geoDrivers (lat ASC, lng ASC).
 */
const GEO_COLLECTION = 'geoDrivers';
/** Legacy collection name kept only for flushdb cleanup. */
const LEGACY_ONLINE_COLLECTION = 'driverOnline';
const EARTH_RADIUS_KM = 6371;
/**
 * Defensive cap on bounding-box scans — box reads are billed per doc. Far
 * above any realistic fleet size; prevents unbounded reads on huge datasets.
 * When a box scan hits this cap, the box is split into quadrants and each is
 * rescanned (GEO_SPLIT_MAX_DEPTH levels deep) so a dense fleet cannot hide
 * the nearest drivers behind index-order truncation.
 */
const GEO_QUERY_SCAN_LIMIT = 5000;
/** Max recursive quadrant splits on a capped scan (4^4 = 256 leaf boxes). */
const GEO_SPLIT_MAX_DEPTH = 4;
/**
 * Hard bound on total box queries per georadius call (including splits).
 * Prevents pathological density from issuing unbounded sub-queries; any box
 * still capped at the bound is reported via GEORADIUS_SCAN_CAPPED.
 */
const GEO_SPLIT_MAX_QUERIES = 33;

export interface FirestoreGeoClientOptions {
  /** Test hook — defaults to GEO_QUERY_SCAN_LIMIT. */
  scanLimit?: number;
  /** Test hook — defaults to GEO_SPLIT_MAX_DEPTH. */
  maxSplitDepth?: number;
  /** Test hook — defaults to GEO_SPLIT_MAX_QUERIES. */
  maxScanQueries?: number;
}

function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
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
  // Near the poles the longitude span is effectively unlimited.
  if (Math.abs(cos) < 1e-6) return 180;
  return Math.min(180, km / (111.32 * cos));
}

export function createFirestoreGeoClient(
  db: Firestore,
  options?: FirestoreGeoClientOptions,
): RedisGeoClient & { flushdb(): Promise<'OK'>; quit(): Promise<'OK'> } {
  const geoCol = db.collection(GEO_COLLECTION);
  const scanLimit = options?.scanLimit ?? GEO_QUERY_SCAN_LIMIT;
  const maxSplitDepth = options?.maxSplitDepth ?? GEO_SPLIT_MAX_DEPTH;
  const maxScanQueries = options?.maxScanQueries ?? GEO_SPLIT_MAX_QUERIES;

  function isGeoKey(key: string): boolean {
    return key === GEO_DRIVERS_KEY;
  }

  /** `driver:online:{driverId}` -> driverId (only string-key shape in use). */
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
      Date.now() > expiresAtMs
    ) {
      return null;
    }
    return typeof data.markerValue === 'string' ? data.markerValue : null;
  }

  function markerFields(
    value: string,
    ttlSeconds?: number,
  ): Record<string, unknown> {
    const expiresAtMs =
      ttlSeconds != null ? Date.now() + ttlSeconds * 1000 : null;
    // Top-level twins of marker-JSON fields so georadius can apply server-side
    // freshness range filters (fewer billed reads). Marker remains
    // authoritative — NearbyDriversService re-checks freshness/accuracy
    // against markerValue for every hit.
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
      // Non-JSON marker (opaque value) — no queryable twins; N3 parseMarker
      // will reject it the same way it rejects malformed markers today.
    }
    return {
      markerValue: value,
      markerExpiresAtMs: expiresAtMs,
      lastLocationTs,
      accuracy,
      // Timestamp twin so a Firestore TTL policy on `expiresAt` can physically
      // remove fully-expired docs (reads already enforce TTL via
      // markerExpiresAtMs; without the policy expired docs just linger —
      // bounded to one doc per distinct driver, so cost is negligible).
      expiresAt: expiresAtMs != null ? Timestamp.fromMillis(expiresAtMs) : null,
    };
  }

  return {
    async geoadd(key, longitude, latitude, member) {
      if (!isGeoKey(key)) return 1; // legacy city shard — not read; no-op.
      // merge: standalone geoadd must not wipe marker fields written by set().
      await geoCol
        .doc(member)
        .set({ driverId: member, lat: latitude, lng: longitude }, { merge: true });
      return 1;
    },

    async projectLocation(input) {
      if (!isGeoKey(input.key)) return 'skipped';
      const ref = geoCol.doc(input.member);
      // Hot path: geo coords + marker in ONE document write. When a
      // markerGuard is provided the guard read + conditional write run in a
      // single transaction — concurrent same-driver packets (idle and trip
      // publishers overlap at mode transitions) can no longer interleave a
      // stale write between the guard check and the set.
      if (!input.markerGuard) {
        await ref.set(
          {
            driverId: input.member,
            lat: input.latitude,
            lng: input.longitude,
            ...markerFields(input.markerValue, input.markerTtlSeconds),
          },
          { merge: true },
        );
        return 'written';
      }
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const data = snap.exists ? (snap.data() ?? {}) : null;
        const decision = input.markerGuard!({
          latitude: typeof data?.lat === 'number' ? data.lat : NaN,
          longitude: typeof data?.lng === 'number' ? data.lng : NaN,
          markerValue: data ? liveMarkerValue(data) : null,
        });
        if (decision === 'skip') return 'skipped';
        tx.set(
          ref,
          {
            driverId: input.member,
            lat: input.latitude,
            lng: input.longitude,
            ...markerFields(input.markerValue, input.markerTtlSeconds),
          },
          { merge: true },
        );
        return 'written';
      });
    },

    async zrem(key, member) {
      if (!isGeoKey(key)) return 0; // legacy city shard — no-op.
      // Offline path only (infrequent) — keep accurate removed-count.
      const ref = geoCol.doc(member);
      const snap = await ref.get();
      if (!snap.exists) return 0;
      await ref.delete();
      return 1;
    },

    async geopos(key, member) {
      if (!isGeoKey(key)) return null;
      const snap = await geoCol.doc(member).get();
      if (!snap.exists) return null;
      const data = (snap.data() ?? {}) as { lat?: unknown; lng?: unknown };
      if (typeof data.lat !== 'number' || typeof data.lng !== 'number') {
        return null;
      }
      return [String(data.lng), String(data.lat)];
    },

    async georadius(input) {
      if (!isGeoKey(input.key)) return [];
      const latDelta = kmToLatDegrees(input.radiusKm);
      const lngDelta = kmToLngDegrees(input.radiusKm, input.latitude);
      const minLat = Math.max(-90, input.latitude - latDelta);
      const maxLat = Math.min(90, input.latitude + latDelta);
      const minLng = input.longitude - lngDelta;
      const maxLng = input.longitude + lngDelta;
      // Longitude wrap (antimeridian / polar) — widen to full range; the
      // haversine filter below keeps only true in-radius hits.
      const wrapped = minLng < -180 || maxLng > 180;
      const minTs = input.minLastLocationTs;

      type Box = {
        minLat: number;
        maxLat: number;
        minLng: number;
        maxLng: number;
      };
      type ScannedDoc = { id: string; data: () => Record<string, unknown> };

      // Docs deduped by id — quadrant splits share edge boundaries so the
      // same doc can legitimately appear in two sibling boxes.
      const docsById = new Map<string, ScannedDoc>();
      let queriesIssued = 0;
      let cappedLeaves = 0;

      const scan = async (box: Box, depth: number): Promise<void> => {
        let query = geoCol
          .where('lat', '>=', box.minLat)
          .where('lat', '<=', box.maxLat);
        if (!wrapped) {
          query = query
            .where('lng', '>=', box.minLng)
            .where('lng', '<=', box.maxLng);
        }
        if (minTs != null) {
          // Server-side freshness floor — docs without a parseable marker
          // timestamp never match, identical outcome to the N3 marker_missing/
          // marker_not_fresh rejections but without paying a document read.
          query = query.where('lastLocationTs', '>', minTs);
        }
        queriesIssued += 1;
        const snap = await query.limit(scanLimit).get();
        const capped = snap.docs.length >= scanLimit;

        if (
          capped &&
          depth < maxSplitDepth &&
          queriesIssued + 4 <= maxScanQueries
        ) {
          // Cap hit: Firestore returns index-ordered (lat,lng) rows, NOT
          // nearest-first — a dense fleet would hide the closest drivers.
          // Split the box into quadrants and rescan each; edge overlaps are
          // harmless (docsById dedup).
          const midLat = (box.minLat + box.maxLat) / 2;
          const midLng = (box.minLng + box.maxLng) / 2;
          const quadrants: Box[] = [
            {
              minLat: box.minLat,
              maxLat: midLat,
              minLng: box.minLng,
              maxLng: midLng,
            },
            {
              minLat: midLat,
              maxLat: box.maxLat,
              minLng: box.minLng,
              maxLng: midLng,
            },
            {
              minLat: box.minLat,
              maxLat: midLat,
              minLng: midLng,
              maxLng: box.maxLng,
            },
            {
              minLat: midLat,
              maxLat: box.maxLat,
              minLng: midLng,
              maxLng: box.maxLng,
            },
          ];
          for (const sub of quadrants) {
            if (sub.minLat === sub.maxLat && sub.minLng === sub.maxLng) {
              continue; // degenerate point box — parent result stands
            }
            await scan(sub, depth + 1);
          }
          return;
        }

        if (capped) cappedLeaves += 1;
        for (const doc of snap.docs) {
          docsById.set(doc.id, doc as ScannedDoc);
        }
      };

      await scan({ minLat, maxLat, minLng, maxLng }, 0);
      if (cappedLeaves > 0) {
        logSafe('GEORADIUS_SCAN_CAPPED', {
          scanLimit,
          cappedLeaves,
          queriesIssued,
          radiusKm: input.radiusKm,
        });
      }

      const hits: GeoRadiusHit[] = [];
      for (const doc of docsById.values()) {
        const data = (doc.data() ?? {}) as { lat?: unknown; lng?: unknown };
        if (typeof data.lat !== 'number' || typeof data.lng !== 'number') {
          continue;
        }
        const distanceKm = haversineKm(
          input.latitude,
          input.longitude,
          data.lat,
          data.lng,
        );
        if (distanceKm > input.radiusKm) continue;
        hits.push({
          member: doc.id,
          distanceKm,
          longitude: data.lng,
          latitude: data.lat,
          // Marker already read — callers can skip a redundant MGET.
          markerValue: liveMarkerValue(data),
        });
      }
      hits.sort((a, b) => a.distanceKm - b.distanceKm);
      return hits.slice(0, input.count);
    },

    async get(key) {
      const snap = await geoCol.doc(markerDocId(key)).get();
      if (!snap.exists) return null;
      return liveMarkerValue(snap.data() ?? {});
    },

    async mget(keys) {
      if (keys.length === 0) return [];
      const refs = keys.map((k) => geoCol.doc(markerDocId(k)));
      const snaps = await db.getAll(...refs);
      const now = Date.now();
      return snaps.map((snap) => {
        if (!snap.exists) return null;
        const data = (snap.data() ?? {}) as {
          markerValue?: unknown;
          markerExpiresAtMs?: unknown;
        };
        if (
          typeof data.markerExpiresAtMs === 'number' &&
          Number.isFinite(data.markerExpiresAtMs) &&
          now > data.markerExpiresAtMs
        ) {
          return null;
        }
        return typeof data.markerValue === 'string' ? data.markerValue : null;
      });
    },

    async set(key, value, ttlSeconds) {
      // merge: standalone set must not wipe geo coords written by geoadd().
      await geoCol
        .doc(markerDocId(key))
        .set(markerFields(value, ttlSeconds), { merge: true });
      return 'OK';
    },

    async del(...keys) {
      let removed = 0;
      for (const key of keys) {
        const ref = geoCol.doc(markerDocId(key));
        try {
          // Remove ONLY the marker fields — mirrors Redis DEL on the string
          // key leaving GEO membership intact until zrem.
          await ref.update({
            markerValue: FieldValue.delete(),
            markerExpiresAtMs: FieldValue.delete(),
            lastLocationTs: FieldValue.delete(),
            accuracy: FieldValue.delete(),
            expiresAt: FieldValue.delete(),
          });
          removed += 1;
        } catch {
          // NOT_FOUND — doc absent; nothing to clear.
        }
      }
      return removed;
    },

    async flushdb() {
      for (const name of [GEO_COLLECTION, LEGACY_ONLINE_COLLECTION]) {
        const snap = await db.collection(name).get();
        for (const doc of snap.docs) {
          await doc.ref.delete();
        }
      }
      return 'OK';
    },

    async quit() {
      return 'OK';
    },
  };
}
