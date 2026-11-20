import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logSafe } from '../http/errors';
import { LocationDomainError } from '../location/types';
import {
  GEO_DRIVERS_KEY,
  N3_FRESHNESS_MAX_AGE_MS,
  type GeoRadiusHit,
  type GeoStoreClient,
} from './types';

/**
 * Firestore-native implementation of the GeoStoreClient port.
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
 * - del() removes ONLY marker fields — matching geo-store parity, where DEL on the
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

/**
 * Progressive ring radii (km) probed before the full box. Benchmarked
 * (scripts/bench_geo.ts): at 5,000-driver density a 10km query reads ~250
 * docs via rings vs ~1,860 for a single box — 7x fewer billed reads — while
 * sparse fleets pay at most ~2 extra round-trips and near-zero extra reads.
 * Safe stop rule: once ≥count docs sit within ring r (haversine), every doc
 * outside the ring's box has distance > r, so the global nearest-count set
 * is already contained. Radii beyond the request collapse to one scan.
 */
const GEO_PROGRESSIVE_RINGS_KM = [2, 5];

export interface FirestoreGeoClientOptions {
  /** Test hook — defaults to GEO_QUERY_SCAN_LIMIT. */
  scanLimit?: number;
  /** Test hook — defaults to GEO_SPLIT_MAX_DEPTH. */
  maxSplitDepth?: number;
  /** Test hook — defaults to GEO_SPLIT_MAX_QUERIES. */
  maxScanQueries?: number;
  /** Test hook — defaults to GEO_PROGRESSIVE_RINGS_KM; [] disables rings. */
  progressiveRingsKm?: number[];
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
  // Geodesic bound: Δlon = asin(sin(δ)/cos φ) with δ the angular radius.
  // The linear km/(111.32·cos) approximation under-covers at box edges
  // (≈1e-4°) and can drop drivers sitting exactly on the circle arc.
  const ratio = Math.sin(km / 6371) / cos;
  if (ratio >= 1) return 180;
  return Math.min(180, (Math.asin(ratio) * 180) / Math.PI + 1e-4);
}

export function createFirestoreGeoClient(
  db: Firestore,
  options?: FirestoreGeoClientOptions,
): GeoStoreClient & { flushdb(): Promise<'OK'>; quit(): Promise<'OK'> } {
  const geoCol = db.collection(GEO_COLLECTION);
  const scanLimit = options?.scanLimit ?? GEO_QUERY_SCAN_LIMIT;
  const maxSplitDepth = options?.maxSplitDepth ?? GEO_SPLIT_MAX_DEPTH;
  const maxScanQueries = options?.maxScanQueries ?? GEO_SPLIT_MAX_QUERIES;
  const progressiveRingsKm =
    options?.progressiveRingsKm ?? GEO_PROGRESSIVE_RINGS_KM;

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
    let freshUntilMs: number | null = null;
    try {
      const parsed = JSON.parse(value) as {
        lastLocationTs?: unknown;
        accuracy?: unknown;
        freshUntilMs?: unknown;
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
      if (
        typeof parsed.freshUntilMs === 'number' &&
        Number.isFinite(parsed.freshUntilMs)
      ) {
        freshUntilMs = parsed.freshUntilMs;
      }
    } catch {
      // Non-JSON marker (opaque value) — no queryable twins; N3 parseMarker
      // will reject it the same way it rejects malformed markers today.
    }
    // Queryable per-driver freshness twin. Defaults to the fixed 15s window so
    // markers written without adaptive fields behave byte-identically to the
    // legacy lastLocationTs filter (freshUntilMs = lastLocationTs + 15s).
    const effectiveFreshUntilMs =
      freshUntilMs ??
      (lastLocationTs != null
        ? lastLocationTs + N3_FRESHNESS_MAX_AGE_MS
        : null);
    return {
      markerValue: value,
      markerExpiresAtMs: expiresAtMs,
      lastLocationTs,
      freshUntilMs: effectiveFreshUntilMs,
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

    supportsIdleCursor: true,

    async projectLocation(input) {
      if (!isGeoKey(input.key)) return 'skipped';
      const ref = geoCol.doc(input.member);
      // Hot path: geo coords + marker in ONE document write. When a
      // markerGuard is provided the guard read + conditional write run in a
      // single transaction — concurrent same-driver packets (idle and trip
      // publishers overlap at mode transitions) can no longer interleave a
      // stale write between the guard check and the set.
      if (!input.markerGuard && !input.idleCursor) {
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

        const write: Record<string, unknown> = {
          driverId: input.member,
          lat: input.latitude,
          lng: input.longitude,
          ...markerFields(input.markerValue, input.markerTtlSeconds),
        };

        // Merged idle-stream cursor (Phase B): identical semantics to
        // FirestoreLocationStreamStore.accept — CLOSED rejects, same-stream
        // requires strictly increasing seq, previousStreamIds rejects late
        // packets, a new stream replaces the active one. Fields are ls*-
        // prefixed so they never collide with geo/marker twins. Violations
        // throw LocationDomainError — callers propagate them as 422.
        const cur = input.idleCursor;
        if (cur) {
          const streamState =
            typeof data?.lsStreamState === 'string'
              ? data.lsStreamState
              : 'ACTIVE';
          if (streamState === 'CLOSED') {
            throw new LocationDomainError(
              'SEQUENCE_VIOLATION',
              422,
              'Location stream is closed.',
            );
          }
          const active =
            typeof data?.lsActiveStreamId === 'string'
              ? data.lsActiveStreamId
              : '';
          const last =
            typeof data?.lsLastAcceptedSeq === 'number'
              ? data.lsLastAcceptedSeq
              : -1;
          const previous =
            Array.isArray(data?.lsPreviousStreamIds) &&
            data.lsPreviousStreamIds.every((x) => typeof x === 'string')
              ? ([...data.lsPreviousStreamIds] as string[])
              : [];

          if (active === cur.locationStreamId) {
            if (cur.locationSeq <= last) {
              throw new LocationDomainError(
                'SEQUENCE_VIOLATION',
                422,
                'locationSeq must be greater than last accepted sequence.',
              );
            }
            write.lsActiveStreamId = cur.locationStreamId;
            write.lsLastAcceptedSeq = cur.locationSeq;
            write.lsStreamState = 'ACTIVE';
            write.lsUpdatedAt = cur.updatedAtIso;
            write.lsExpiresAt = cur.expiresAtIso;
          } else {
            if (previous.includes(cur.locationStreamId)) {
              throw new LocationDomainError(
                'SEQUENCE_VIOLATION',
                422,
                'Location stream is no longer active.',
              );
            }
            if (active) previous.push(active);
            write.lsActiveStreamId = cur.locationStreamId;
            write.lsLastAcceptedSeq = cur.locationSeq;
            write.lsStreamState = 'ACTIVE';
            write.lsPreviousStreamIds = previous.slice(-5);
            write.lsUpdatedAt = cur.updatedAtIso;
            write.lsExpiresAt = cur.expiresAtIso;
          }
        }

        if (input.markerGuard) {
          const decision = input.markerGuard({
            latitude: typeof data?.lat === 'number' ? data.lat : NaN,
            longitude: typeof data?.lng === 'number' ? data.lng : NaN,
            markerValue: data ? liveMarkerValue(data) : null,
          });
          if (decision === 'skip') return 'skipped';
        }
        tx.set(ref, write, { merge: true });
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
      const minTs = input.minLastLocationTs;
      const minFreshUntil = input.minFreshUntilMs;

      type Box = {
        minLat: number;
        maxLat: number;
        minLng: number;
        maxLng: number;
        wrapped: boolean;
        radiusKm: number;
      };
      type ScannedDoc = { id: string; data: () => Record<string, unknown> };

      const boxFor = (radiusKm: number): Box => {
        const latDelta = kmToLatDegrees(radiusKm);
        // The longitude box must be computed at the circle's edge closest to
        // a pole — cos(lat) shrinks toward the poles, so the center-lat cos
        // under-covers the northern/southern arc and can miss edge drivers.
        const edgeLat = Math.min(
          89.9,
          Math.abs(input.latitude) + latDelta,
        );
        const lngDelta = kmToLngDegrees(radiusKm, edgeLat);
        const minLat = Math.max(-90, input.latitude - latDelta);
        const maxLat = Math.min(90, input.latitude + latDelta);
        const minLng = input.longitude - lngDelta;
        const maxLng = input.longitude + lngDelta;
        // Longitude wrap (antimeridian / polar) — widen to full range; the
        // haversine filter below keeps only true in-radius hits.
        return {
          minLat,
          maxLat,
          minLng,
          maxLng,
          wrapped: minLng < -180 || maxLng > 180,
          radiusKm,
        };
      };

      // Docs deduped by id — quadrant splits share edge boundaries so the
      // same doc can legitimately appear in two sibling boxes.
      const docsById = new Map<string, ScannedDoc>();
      let queriesIssued = 0;
      let cappedLeaves = 0;

      const scan = async (box: Box, depth: number): Promise<void> => {
        let query = geoCol
          .where('lat', '>=', box.minLat)
          .where('lat', '<=', box.maxLat);
        if (!box.wrapped) {
          query = query
            .where('lng', '>=', box.minLng)
            .where('lng', '<=', box.maxLng);
        }
        if (minFreshUntil != null) {
          // Per-driver freshness twin — each doc carries its own expiry so
          // variable publish cadences stay filterable server-side.
          query = query.where('freshUntilMs', '>', minFreshUntil);
        } else if (minTs != null) {
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
              wrapped: box.wrapped,
              radiusKm: box.radiusKm,
            },
            {
              minLat: midLat,
              maxLat: box.maxLat,
              minLng: box.minLng,
              maxLng: midLng,
              wrapped: box.wrapped,
              radiusKm: box.radiusKm,
            },
            {
              minLat: box.minLat,
              maxLat: midLat,
              minLng: midLng,
              maxLng: box.maxLng,
              wrapped: box.wrapped,
              radiusKm: box.radiusKm,
            },
            {
              minLat: midLat,
              maxLat: box.maxLat,
              minLng: midLng,
              maxLng: box.maxLng,
              wrapped: box.wrapped,
              radiusKm: box.radiusKm,
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

      // Progressive rings: probe small boxes first; stop when the ring alone
      // already contains ≥count true in-circle docs. Quadrant splits inside
      // scan() stay as the density cap backstop.
      const requested = input.count;
      const needProgressive =
        Number.isFinite(requested) && requested > 0
          ? requested
          : null;
      const ringRadii =
        needProgressive != null
          ? [
              ...progressiveRingsKm.filter((r) => r < input.radiusKm),
              input.radiusKm,
            ]
          : [input.radiusKm];

      for (let i = 0; i < ringRadii.length; i += 1) {
        const box = boxFor(ringRadii[i]);
        await scan(box, 0);
        const isLastRing = i === ringRadii.length - 1;
        if (isLastRing || needProgressive == null) break;
        // Safe stop: ≥count docs with dist ≤ ring means the global nearest-
        // count set is fully inside this box — farther docs can't displace.
        let inRing = 0;
        for (const doc of docsById.values()) {
          const data = (doc.data() ?? {}) as {
            lat?: unknown;
            lng?: unknown;
          };
          if (typeof data.lat !== 'number' || typeof data.lng !== 'number') {
            continue;
          }
          if (
            haversineKm(
              input.latitude,
              input.longitude,
              data.lat,
              data.lng,
            ) <= box.radiusKm
          ) {
            inRing += 1;
            if (inRing >= needProgressive) break;
          }
        }
        if (inRing >= needProgressive) break;
      }

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
          // Remove ONLY the marker fields — mirrors geo-store DEL on the string
          // key leaving GEO membership intact until zrem. Merged-cursor ls*
          // fields are deliberately retained — they are not marker state.
          await ref.update({
            markerValue: FieldValue.delete(),
            markerExpiresAtMs: FieldValue.delete(),
            lastLocationTs: FieldValue.delete(),
            freshUntilMs: FieldValue.delete(),
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
