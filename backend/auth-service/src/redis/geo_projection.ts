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
  type RedisGeoClient,
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

export interface RedisGeoProjectionOptions {
  /**
   * LOCATION_ADAPTIVE_FRESHNESS — when true, a declared publishIntervalMs
   * extends the marker's freshUntilMs to lastLocationTs + interval + grace
   * (clamped), and the marker TTL is extended to cover it.
   */
  adaptiveFreshness?: boolean;
}

/**
 * N2C — Redis GEO + driver:online projection (coordinate-primary).
 * Never throws to callers for Redis failures (non-authoritative) EXCEPT
 * LocationDomainError from merged-cursor validation — that is the durable
 * accept contract and must surface as 422.
 *
 * Matching index: `geo:drivers`
 * Legacy dual-write: `geo:drivers:{city}` when homeCity present (rollback/compat).
 */
export class RedisGeoProjectionService {
  private readonly adaptiveFreshness: boolean;

  constructor(
    private readonly redis: RedisGeoClient | null,
    options: RedisGeoProjectionOptions = {},
  ) {
    this.adaptiveFreshness = options.adaptiveFreshness === true;
  }

  /**
   * Whether the configured store can validate + advance the idle stream
   * cursor inside the marker write transaction (merged Phase B path).
   */
  supportsIdleCursor(): boolean {
    return (
      this.redis != null &&
      typeof this.redis.projectLocation === 'function' &&
      this.redis.supportsIdleCursor === true
    );
  }

  async projectAcceptedLocation(input: ProjectLocationInput): Promise<void> {
    if (!this.redis) {
      logSafe('REDIS_GEO_SKIP', {
        reason: 'redis_not_configured',
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
      const freshUntilMs =
        this.adaptiveFreshness && input.publishIntervalMs != null
          ? freshBaseMs +
            input.publishIntervalMs +
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
      if (this.redis.projectLocation) {
        const result = await this.redis.projectLocation({
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
          logSafe('REDIS_GEO_SKIP', {
            reason: 'stale_projection',
            driverId: input.driverId,
            requestId: input.requestId ?? null,
          });
          return;
        }
        // Legacy city-shard: remove from previous city key on homeCity
        // change. Best-effort, outside the projection write.
        if (prevCity && prevCity !== city) {
          await this.redis.zrem(geoDriversCityKey(prevCity), input.driverId);
        } else if (prevCity && !city) {
          await this.redis.zrem(geoDriversCityKey(prevCity), input.driverId);
        }
      } else {
        // Fallback for clients without projectLocation — preserves the old
        // read-then-write ordering (non-atomic guard is unavoidable here).
        const existingRaw = await this.redis.get(onlineKey);
        if (existingRaw) {
          const decision = guard({
            latitude: NaN,
            longitude: NaN,
            markerValue: existingRaw,
          });
          if (decision === 'skip') {
            logSafe('REDIS_GEO_SKIP', {
              reason: 'stale_projection',
              driverId: input.driverId,
              requestId: input.requestId ?? null,
            });
            return;
          }
        }
        await this.redis.geoadd(
          GEO_DRIVERS_KEY,
          input.lng,
          input.lat,
          input.driverId,
        );
        await this.redis.set(
          onlineKey,
          markerValue,
          markerTtlSeconds,
        );
        if (prevCity && prevCity !== city) {
          await this.redis.zrem(geoDriversCityKey(prevCity), input.driverId);
        } else if (prevCity && !city) {
          await this.redis.zrem(geoDriversCityKey(prevCity), input.driverId);
        }
      }

      // Dual-write legacy city shard when homeCity present (migration / rollback).
      if (city) {
        await this.redis.geoadd(
          geoDriversCityKey(city),
          input.lng,
          input.lat,
          input.driverId,
        );
      }

      logSafe('REDIS_GEO_PROJECTED', {
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
      logSafe('REDIS_GEO_PROJECT_FAILED', {
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
    if (!this.redis) {
      logSafe('REDIS_GEO_OFFLINE_SKIP', {
        reason: 'redis_not_configured',
        driverId: input.driverId,
        requestId: input.requestId ?? null,
      });
      return;
    }

    try {
      const onlineKey = driverOnlineKey(input.driverId);
      const existingRaw = await this.redis.get(onlineKey);
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

      await this.redis.zrem(GEO_DRIVERS_KEY, input.driverId);
      for (const city of cities) {
        await this.redis.zrem(geoDriversCityKey(city), input.driverId);
      }
      await this.redis.del(onlineKey);

      logSafe('REDIS_GEO_OFFLINE_REMOVED', {
        driverId: input.driverId,
        geoKey: GEO_DRIVERS_KEY,
        legacyCities: [...cities],
        requestId: input.requestId ?? null,
      });
    } catch (err) {
      logSafe('REDIS_GEO_OFFLINE_FAILED', {
        driverId: input.driverId,
        requestId: input.requestId ?? null,
        errorType: err instanceof Error ? err.name : 'unknown',
      });
    }
  }
}
