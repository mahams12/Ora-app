/**
 * Server-side routing port — Phase 4B.
 * Implementations must not leak provider SDK types to callers.
 */

export type RouteLatLng = { lat: number; lng: number };

export interface ComputeDriveRouteInput {
  origin: RouteLatLng;
  destination: RouteLatLng;
}

export interface DriveRouteResult {
  distanceKm: number;
  durationMin: number;
  encodedPolyline?: string;
  provider: 'google_routes';
  rawRequestId?: string;
}

export interface RoutingProvider {
  computeDriveRoute(input: ComputeDriveRouteInput): Promise<DriveRouteResult>;
}

export class RoutingError extends Error {
  constructor(
    readonly code: 'PRICING_UNAVAILABLE' | 'ROUTE_UNAVAILABLE' | 'VALIDATION_ERROR',
    readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'RoutingError';
  }
}
