import { logSafe } from '../http/errors';
import { LocationDomainError } from '../location/types';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  N3_FRESHNESS_GRACE_MS,
  driverOnlineKey,
  geoDriversCityKey,
  normalizeCitySlug,
  type DriverOnlineMarker,
  type GeoStoreClient,
} from './types';

export interface ProjectLocationInput {
  driverId: string;
  lat: number;
  lng: number;
  accuracy: number;
  locationStreamId: string;
  locationSeq: number;
  /** Client packet timestamp ms (already N2A-validated). */
  lastLocationTs: number;
  acceptedAt: string;
  /**
   * Raw drivers.homeCity from Firestore.
   * Optional metadata + legacy dual-write only — NOT required for GEO membership.
   */
  homeCity: unknown;
  requestId?: string;
  /**
   * Adaptive freshness — clamped client-declared cadence. Honored only when
   * the service was built with adaptiveFreshness: true.
   */
  publishIntervalMs?: number | null;
  /** Presence keepalive flag — recorded on the marker for observability. */
  keepalive?: boolean;
  /**
   * Update mode — 'trip' packets get marker-write throttling when the
   * service is built with tripMarkerMinIntervalMs > 0. Busy drivers are
   * eligibility-excluded from matching, so trip-mode geo writes only keep
   * the presence marker warm; a 45s refresh floor preserves that at ~1/8
   * the write cost.
   */
  mode?: 'idle' | 'trip';
  /**
   * Merged idle-cursor accept (Phase B): validated inside the store's write
   * transaction. SEQUENCE_VIOLATION errors propagate to the caller — they are
   * the durable-accept contract, not a best-effort projection failure.
   */
  idleCursor?: {
    locationStreamId: string;
    locationSeq: number;
    updatedAtIso: string;
    expiresAtIso: string;
  };
}

export interface GeoProjectionOptions {
  /**
   * LOCATION_ADAPTIVE_FRESHNESS — when true, a declared publishIntervalMs
   * extends the marker's freshUntilMs to lastLocationTs + interval + grace
   * (clamped), and the marker TTL is extended to cover it.
   */
  adaptiveFreshness?: boolean;
  /**
   * LOCATION_TRIP_GEO_MIN_INTERVAL_MS — minimum wall-clock gap between
   * geoDrivers marker writes for TRIP-mode packets from the same driver.
   * The trip publisher streams at 4–10s for live tracking, but the marker
   * only proves presence; writes are throttled to this interval. Requires
   * adaptiveFreshness (the marker's freshUntilMs horizon is extended to
   * cover the throttle gap); 0 disables.
   */
  tripMarkerMinIntervalMs?: number;
}

/** Trip-mode marker horizon: the declared interval written into freshUntilMs
 * so the marker stays fresh across the throttle gap (interval + grace). */
const TRIP_MARKER_DECLARED_INTERVAL_MS = 60_000;

/**
 * N2C — geo-store + driver:online projection (coordinate-primary).
 * Never throws to callers for geo-store failures (non-authoritative) EXCEPT
 * LocationDomainError from merged-cursor validation — that is the durable
 * accept contract and must surface as 422.
 *
 * Matching index: `geo:drivers`
 * Legacy dual-write: `geo:drivers:{city}` when homeCity present (rollback/compat).
 */
export class GeoProjectionService {
  private readonly adaptiveFreshness: boolean;
  private readonly tripMarkerMinIntervalMs: number;
  /** Last successful trip-mode marker write per driver (in-memory). */
  private readonly tripMarkerLastWriteMs = new Map<string, number>();

  constructor(
    private readonly geoStore: GeoStoreClient | null,
    options: GeoProjectionOptions = {},
  ) {
    this.adaptiveFreshness = options.adaptiveFreshness === true;
    this.tripMarkerMinIntervalMs =
      this.adaptiveFreshness &&
      typeof options.tripMarkerMinIntervalMs === 'number' &&
      options.tripMarkerMinIntervalMs > 0
        ? options.tripMarkerMinIntervalMs
        : 0;
  }

  /**
   * Whether the configured store can validate + advance the idle stream
   * cursor inside the marker write transaction (merged Phase B path).
   */
  supportsIdleCursor(): boolean {
    return (
      this.geoStore != null &&
      typeof this.geoStore.projectLocation === 'function' &&
      this.geoStore.supportsIdleCursor === true
    );
  }

  async projectAcceptedLocation(input: ProjectLocationInput): Promise<void> {
    if (!this.geoStore) {
      logSafe('GEO_STORE_SKIP', {
        reason: 'geo_store_not_configured',
        driverId: input.driverId,
        requestId: input.requestId ?? null,
      });
      return;
    }

    try {
      const city = normalizeCitySlug(input.homeCity);
      const onlineKey = driverOnlineKey(input.driverId);

      // Monotonic guard: do not let older accepted packets overwrite newer
      // projection. Seq comparison is per-stream (idle + trip streams count
      // independently); a different stream only loses when its packet is
      // strictly older by ts. The guard is evaluated inside the client's
      // projectLocation transaction (atomic with the write) — the previous
      // standalone get() left a check-then-act window where a stale packet
      // could interleave and overwrite a fresher projection.
      let prevCity: string | null = null;
      const guard = (existing: {
        latitude: number;
        longitude: number;
        markerValue: string | null;
      }): 'write' | 'skip' => {
        if (!existing.markerValue) return 'write';
        try {
          const prev = JSON.parse(existing.markerValue) as DriverOnlineMarker;
          const staleTs =
            typeof prev.lastLocationTs === 'number' &&
            prev.lastLocationTs > input.lastLocationTs;
          const staleSeq =
            prev.locationStreamId === input.locationStreamId &&
            typeof prev.locationSeq === 'number' &&
            prev.locationSeq > input.locationSeq;
          if (staleTs || staleSeq) return 'skip';
          prevCity = typeof prev.city === 'string' ? prev.city : null;
        } catch {
          // Corrupt marker — overwrite.
        }
        return 'write';
      };

      // Adaptive freshness: per-driver marker expiry derived from the
      // declared publish cadence. Marker TTL is extended to cover it so the
      // marker cannot expire before its own freshUntilMs.
      // Keepalive packets carry the ORIGINAL fix timestamp — presence is
      // asserted "as of acceptedAt", while lastLocationTs keeps the honest
      // GPS age for the eligibility fix-age cap.
      const acceptedMs = Date.parse(input.acceptedAt);
      const freshBaseMs = input.keepalive ? acceptedMs : input.lastLocationTs;

      // Trip-mode marker throttle: geo writes on trip packets only keep the
      // presence marker warm (busy drivers are eligibility-excluded anyway).
      // Skip when this instance wrote a marker inside the min-interval; the
      // written horizon (declared interval + grace) covers the gap.
      const throttledTrip =
        input.mode === 'trip' && this.tripMarkerMinIntervalMs > 0;
      if (throttledTrip && Number.isFinite(acceptedMs)) {
        const last = this.tripMarkerLastWriteMs.get(input.driverId) ?? 0;
        if (acceptedMs - last < this.tripMarkerMinIntervalMs) {
          return;
        }
        // Opportunistic bound: drop stale entries when the map grows.
        if (this.tripMarkerLastWriteMs.size > 10_000) {
          const cutoff = acceptedMs - this.tripMarkerMinIntervalMs * 4;
          for (const [id, ts] of this.tripMarkerLastWriteMs) {
            if (ts < cutoff) this.tripMarkerLastWriteMs.delete(id);
          }
        }
      }

      // Throttled trip writes declare a longer interval so freshUntilMs
      // spans the throttle gap; the marker stays continuously fresh.
      const effectivePublishIntervalMs = throttledTrip
        ? Math.max(
            input.publishIntervalMs ?? 0,
            TRIP_MARKER_DECLARED_INTERVAL_MS,
          )
        : input.publishIntervalMs;
      const freshUntilMs =
        this.adaptiveFreshness && effectivePublishIntervalMs != null
          ? freshBaseMs +
            effectivePublishIntervalMs +
            N3_FRESHNESS_GRACE_MS
          : null;
      const markerTtlSeconds =
        freshUntilMs != null && Number.isFinite(acceptedMs)
          ? Math.max(
              DRIVER_ONLINE_TTL_SECONDS,
              Math.ceil((freshUntilMs - acceptedMs) / 1000) + 10,
            )
          : DRIVER_ONLINE_TTL_SECONDS;

      const marker: DriverOnlineMarker = {
        driverId: input.driverId,
        lastLocationTs: input.lastLocationTs,
        accuracy: input.accuracy,
        city,
        locationStreamId: input.locationStreamId,
        locationSeq: input.locationSeq,
        acceptedAt: input.acceptedAt,
        ...(freshUntilMs != null
          ? {
              freshUntilMs,
              publishIntervalMs: input.publishIntervalMs ?? undefined,
            }
          : {}),
        ...(input.keepalive === true ? { keepalive: true } : {}),
      };
      const markerValue = JSON.stringify(marker);

      // Coordinate-primary: always project live coords (homeCity not required).
      // projectLocation = single store round-trip (GEO membership + marker),
      // guard applied atomically inside the write.
      if (this.geoStore.projectLocation) {
        const result = await this.geoStore.projectLocation({
          key: GEO_DRIVERS_KEY,
          member: input.driverId,
          longitude: input.lng,
          latitude: input.lat,
          markerKey: onlineKey,
          markerValue,
          markerTtlSeconds,
          markerGuard: guard,
          ...(input.idleCursor ? { idleCursor: input.idleCursor } : {}),
        });
        if (result === 'skipped') {
          logSafe('GEO_STORE_SKIP', {
            reason: 'stale_projection',
            driverId: input.driverId,
            requestId: input.requestId ?? null,
          });
          return;
        }
        if (throttledTrip) {
          this.tripMarkerLastWriteMs.set(input.driverId, acceptedMs);
        }
        // Legacy city-shard: remove from previous city key on homeCity
        // change. Best-effort, outside the projection write.
        if (prevCity && prevCity !== city) {
          await this.geoStore.zrem(geoDriversCityKey(prevCity), input.driverId);
        } else if (prevCity && !city) {
          await this.geoStore.zrem(geoDriversCityKey(prevCity), input.driverId);
        }
      } else {
        // Fallback for clients without projectLocation — preserves the old
        // read-then-write ordering (non-atomic guard is unavoidable here).
        const existingRaw = await this.geoStore.get(onlineKey);
        if (existingRaw) {
          const decision = guard({
            latitude: NaN,
            longitude: NaN,
            markerValue: existingRaw,
          });
          if (decision === 'skip') {
            logSafe('GEO_STORE_SKIP', {
              reason: 'stale_projection',
              driverId: input.driverId,
              requestId: input.requestId ?? null,
            });
            return;
          }
        }
        await this.geoStore.geoadd(
          GEO_DRIVERS_KEY,
          input.lng,
          input.lat,
          input.driverId,
        );
        await this.geoStore.set(
          onlineKey,
          markerValue,
          markerTtlSeconds,
        );
        if (throttledTrip) {
          this.tripMarkerLastWriteMs.set(input.driverId, acceptedMs);
        }
        if (prevCity && prevCity !== city) {
          await this.geoStore.zrem(geoDriversCityKey(prevCity), input.driverId);
        } else if (prevCity && !city) {
          await this.geoStore.zrem(geoDriversCityKey(prevCity), input.driverId);
        }
      }

      // Dual-write legacy city shard when homeCity present (migration / rollback).
      if (city) {
        await this.geoStore.geoadd(
          geoDriversCityKey(city),
          input.lng,
          input.lat,
          input.driverId,
        );
      }

      logSafe('GEO_STORE_PROJECTED', {
        driverId: input.driverId,
        geoKey: GEO_DRIVERS_KEY,
        city,
        locationSeq: input.locationSeq,
        requestId: input.requestId ?? null,
      });
    } catch (err) {
      // Merged-cursor violations are the durable-accept contract (422) —
      // never downgrade them to a swallowed projection failure.
      if (err instanceof LocationDomainError) throw err;
      logSafe('GEO_STORE_PROJECT_FAILED', {
        driverId: input.driverId,
        requestId: input.requestId ?? null,
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      // Non-authoritative: swallow.
    }
  }

  /**
   * Remove driver from GEO candidacy after durable go-offline.
   * Always removes from coordinate-primary key; also cleans known legacy city keys.
   * Idempotent. Failures are logged and swallowed.
   */
  async removeDriverOnOffline(input: {
    driverId: string;
    homeCity: unknown;
    requestId?: string;
  }): Promise<void> {
    if (!this.geoStore) {
      logSafe('GEO_STORE_OFFLINE_SKIP', {
        reason: 'geo_store_not_configured',
        driverId: input.driverId,
        requestId: input.requestId ?? null,
      });
      return;
    }

    try {
      const onlineKey = driverOnlineKey(input.driverId);
      const existingRaw = await this.geoStore.get(onlineKey);
      const cities = new Set<string>();
      const fromHome = normalizeCitySlug(input.homeCity);
      if (fromHome) cities.add(fromHome);
      if (existingRaw) {
        try {
          const prev = JSON.parse(existingRaw) as DriverOnlineMarker;
          if (prev.city) cities.add(prev.city);
        } catch {
          /* ignore */
        }
      }

      await this.geoStore.zrem(GEO_DRIVERS_KEY, input.driverId);
      for (const city of cities) {
        await this.geoStore.zrem(geoDriversCityKey(city), input.driverId);
      }
      await this.geoStore.del(onlineKey);

      logSafe('GEO_STORE_OFFLINE_REMOVED', {
        driverId: input.driverId,
        geoKey: GEO_DRIVERS_KEY,
        legacyCities: [...cities],
        requestId: input.requestId ?? null,
      });
    } catch (err) {
      logSafe('GEO_STORE_OFFLINE_FAILED', {
        driverId: input.driverId,
        requestId: input.requestId ?? null,
        errorType: err instanceof Error ? err.name : 'unknown',
      });
    }
  }
}
