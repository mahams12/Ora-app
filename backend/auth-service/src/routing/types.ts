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
  provider: 'google_routes' | 'haversine';
  rawRequestId?: string;
}

/** Ora Courier v2 — multi-stop route. legs[i] = waypoint[i] → waypoint[i+1]. */
export interface RouteLeg {
  distanceKm: number;
  durationMin: number;
}

export interface MultiLegRouteResult {
  legs: RouteLeg[];
  distanceKm: number;
  durationMin: number;
  encodedPolyline?: string;
  provider: 'google_routes' | 'haversine';
}

export interface RoutingProvider {
  computeDriveRoute(input: ComputeDriveRouteInput): Promise<DriveRouteResult>;
  /**
   * Ora Courier v2 — optional multi-waypoint route (2..maxStops points).
   * Callers fall back to per-leg computeDriveRoute when unimplemented.
   */
  computeRoute?(input: {
    waypoints: RouteLatLng[];
  }): Promise<MultiLegRouteResult>;
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
