export class LocationDomainError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'LocationDomainError';
  }
}

export type LocationMode = 'idle' | 'trip';

export interface LocationUpdateSnapshot {
  driverId: string;
  mode: LocationMode;
  rideId: string | null;
  locationStreamId: string;
  locationSeq: number;
  acceptedAt: string;
}

export interface ParsedLocationUpdate {
  rideId: string | null;
  locationSeq: number;
  locationStreamId: string;
  lat: number;
  lng: number;
  accuracy: number;
  heading: number;
  speed: number;
  timestampMs: number;
  provider: string;
  altitude: number | null;
  /**
   * Adaptive freshness — client-declared publish cadence (clamped to
   * N3_MIN/MAX_PUBLISH_INTERVAL_MS). Honored only when
   * LOCATION_ADAPTIVE_FRESHNESS is on; otherwise ignored entirely.
   */
  publishIntervalMs: number | null;
  /**
   * Presence keepalive — the client re-asserted a still-accurate last-known
   * position with a fresh timestamp because no newer GPS fix exists. Marker
   * records it for observability; semantics identical to a normal update.
   */
  presenceKeepalive: boolean;
}
