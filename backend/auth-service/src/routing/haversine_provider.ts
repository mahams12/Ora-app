import {
  RoutingError,
  type ComputeDriveRouteInput,
  type DriveRouteResult,
  type RoutingProvider,
} from './types';

const EARTH_RADIUS_KM = 6371;

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
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

/**
 * Local-dev routing provider — straight-line (haversine) distance.
 *
 * Zero-cost development/testing only: enabled exclusively via
 * ORA_ROUTING_PROVIDER=haversine. Never used in staging/production —
 * those keep google_routes via GOOGLE_MAPS_SERVER_KEY. Produces honest
 * "straight-line at ~25 km/h urban" numbers so the full pricing pipeline
 * (rules → fare bounds → snapshot) still runs end to end.
 */
const ASSUMED_SPEED_KMH = 25;

export class HaversineRoutingProvider implements RoutingProvider {
  async computeDriveRoute(
    input: ComputeDriveRouteInput,
  ): Promise<DriveRouteResult> {
    const { origin, destination } = input;
    for (const [name, p] of [
      ['origin', origin],
      ['destination', destination],
    ] as const) {
      if (
        !p ||
        typeof p.lat !== 'number' ||
        typeof p.lng !== 'number' ||
        !Number.isFinite(p.lat) ||
        !Number.isFinite(p.lng) ||
        Math.abs(p.lat) > 90 ||
        Math.abs(p.lng) > 180
      ) {
        throw new RoutingError(
          'VALIDATION_ERROR',
          400,
          `${name} must have finite lat/lng.`,
        );
      }
    }

    const distanceKm = haversineKm(
      origin.lat,
      origin.lng,
      destination.lat,
      destination.lng,
    );
    if (distanceKm < 0.05) {
      throw new RoutingError(
        'ROUTE_UNAVAILABLE',
        422,
        'Origin and destination are too close to route.',
      );
    }
    return {
      distanceKm,
      durationMin: (distanceKm / ASSUMED_SPEED_KMH) * 60,
      provider: 'haversine',
    };
  }
}
