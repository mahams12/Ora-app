import { logSafe } from '../http/errors';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  driverOnlineKey,
  geoDriversKey,
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
  /** Raw drivers.homeCity from Firestore. */
  homeCity: unknown;
  requestId?: string;
}

/**
 * N2C — Redis GEO + driver:online projection.
 * Never throws to callers for Redis failures (non-authoritative).
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
      const existingRaw = await this.redis.get(onlineKey);
      if (existingRaw) {
        try {
          const prev = JSON.parse(existingRaw) as DriverOnlineMarker;
          if (
            typeof prev.locationSeq === 'number' &&
            typeof prev.lastLocationTs === 'number' &&
            (prev.locationSeq > input.locationSeq ||
              (prev.locationSeq === input.locationSeq &&
                prev.lastLocationTs > input.lastLocationTs))
          ) {
            logSafe('REDIS_GEO_SKIP', {
              reason: 'stale_projection',
              driverId: input.driverId,
              requestId: input.requestId ?? null,
            });
            return;
          }
          // City change: remove from previous GEO set.
          if (
            prev.city &&
            city &&
            prev.city !== city
          ) {
            await this.redis.zrem(geoDriversKey(prev.city), input.driverId);
          } else if (prev.city && !city) {
            await this.redis.zrem(geoDriversKey(prev.city), input.driverId);
          }
        } catch {
          // Corrupt marker — overwrite.
        }
      }

      if (!city) {
        logSafe('REDIS_GEO_SKIP', {
          reason: 'missing_home_city',
          driverId: input.driverId,
          requestId: input.requestId ?? null,
        });
        const marker: DriverOnlineMarker = {
          driverId: input.driverId,
          lastLocationTs: input.lastLocationTs,
          accuracy: input.accuracy,
          city: null,
          locationStreamId: input.locationStreamId,
          locationSeq: input.locationSeq,
          acceptedAt: input.acceptedAt,
        };
        await this.redis.set(
          onlineKey,
          JSON.stringify(marker),
          DRIVER_ONLINE_TTL_SECONDS,
        );
        return;
      }

      await this.redis.geoadd(
        geoDriversKey(city),
        input.lng,
        input.lat,
        input.driverId,
      );

      const marker: DriverOnlineMarker = {
        driverId: input.driverId,
        lastLocationTs: input.lastLocationTs,
        accuracy: input.accuracy,
        city,
        locationStreamId: input.locationStreamId,
        locationSeq: input.locationSeq,
        acceptedAt: input.acceptedAt,
      };
      await this.redis.set(
        onlineKey,
        JSON.stringify(marker),
        DRIVER_ONLINE_TTL_SECONDS,
      );

      logSafe('REDIS_GEO_PROJECTED', {
        driverId: input.driverId,
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

      for (const city of cities) {
        await this.redis.zrem(geoDriversKey(city), input.driverId);
      }
      await this.redis.del(onlineKey);

      logSafe('REDIS_GEO_OFFLINE_REMOVED', {
        driverId: input.driverId,
        cities: [...cities],
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
