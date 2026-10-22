import { logSafe } from '../http/errors';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
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
}

/**
 * N2C — Redis GEO + driver:online projection (coordinate-primary).
 * Never throws to callers for Redis failures (non-authoritative).
 *
 * Matching index: `geo:drivers`
 * Legacy dual-write: `geo:drivers:{city}` when homeCity present (rollback/compat).
 */
export class RedisGeoProjectionService {
  constructor(private readonly redis: RedisGeoClient | null) {}

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

      // Monotonic guard: do not let older accepted packets overwrite newer projection.
      // Seq comparison is per-stream (idle + trip streams count independently);
      // a different stream only loses when its packet is strictly older by ts.
      const existingRaw = await this.redis.get(onlineKey);
      if (existingRaw) {
        try {
          const prev = JSON.parse(existingRaw) as DriverOnlineMarker;
          const staleTs =
            typeof prev.lastLocationTs === 'number' &&
            prev.lastLocationTs > input.lastLocationTs;
          const staleSeq =
            prev.locationStreamId === input.locationStreamId &&
            typeof prev.locationSeq === 'number' &&
            prev.locationSeq > input.locationSeq;
          if (staleTs || staleSeq) {
            logSafe('REDIS_GEO_SKIP', {
              reason: 'stale_projection',
              driverId: input.driverId,
              requestId: input.requestId ?? null,
            });
            return;
          }
          // Legacy city-shard: remove from previous city key on homeCity change.
          if (prev.city && city && prev.city !== city) {
            await this.redis.zrem(geoDriversCityKey(prev.city), input.driverId);
          } else if (prev.city && !city) {
            await this.redis.zrem(geoDriversCityKey(prev.city), input.driverId);
          }
        } catch {
          // Corrupt marker — overwrite.
        }
      }

      const marker: DriverOnlineMarker = {
        driverId: input.driverId,
        lastLocationTs: input.lastLocationTs,
        accuracy: input.accuracy,
        city,
        locationStreamId: input.locationStreamId,
        locationSeq: input.locationSeq,
        acceptedAt: input.acceptedAt,
      };
      const markerValue = JSON.stringify(marker);

      // Coordinate-primary: always project live coords (homeCity not required).
      // projectLocation = single store round-trip (GEO membership + marker).
      if (this.redis.projectLocation) {
        await this.redis.projectLocation({
          key: GEO_DRIVERS_KEY,
          member: input.driverId,
          longitude: input.lng,
          latitude: input.lat,
          markerKey: onlineKey,
          markerValue,
          markerTtlSeconds: DRIVER_ONLINE_TTL_SECONDS,
        });
      } else {
        await this.redis.geoadd(
          GEO_DRIVERS_KEY,
          input.lng,
          input.lat,
          input.driverId,
        );
        await this.redis.set(
          onlineKey,
          markerValue,
          DRIVER_ONLINE_TTL_SECONDS,
        );
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
