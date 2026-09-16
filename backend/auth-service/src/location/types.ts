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
}
