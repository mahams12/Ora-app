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
 */
const GEO_QUERY_SCAN_LIMIT = 5000;

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
): RedisGeoClient & { flushdb(): Promise<'OK'>; quit(): Promise<'OK'> } {
  const geoCol = db.collection(GEO_COLLECTION);

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
      if (!isGeoKey(input.key)) return;
      // Hot path: geo coords + marker in ONE document write.
      await geoCol.doc(input.member).set(
        {
          driverId: input.member,
          lat: input.latitude,
          lng: input.longitude,
          ...markerFields(input.markerValue, input.markerTtlSeconds),
        },
        { merge: true },
      );
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

      let query = geoCol
        .where('lat', '>=', minLat)
        .where('lat', '<=', maxLat);
      if (!wrapped) {
        query = query
          .where('lng', '>=', minLng)
          .where('lng', '<=', maxLng);
      }
      if (input.minLastLocationTs != null) {
        // Server-side freshness floor — docs without a parseable marker
        // timestamp never match, identical outcome to the N3 marker_missing/
        // marker_not_fresh rejections but without paying a document read.
        query = query.where('lastLocationTs', '>', input.minLastLocationTs);
      }
      const snap = await query.limit(GEO_QUERY_SCAN_LIMIT).get();
      const scanCapped = snap.docs.length >= GEO_QUERY_SCAN_LIMIT;
      if (scanCapped) {
        logSafe('GEORADIUS_SCAN_CAPPED', {
          scanLimit: GEO_QUERY_SCAN_LIMIT,
          radiusKm: input.radiusKm,
        });
      }

      const hits: GeoRadiusHit[] = [];
      for (const doc of snap.docs) {
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
