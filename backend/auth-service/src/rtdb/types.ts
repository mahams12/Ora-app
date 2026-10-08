/**
 * L2 Step 2 — RTDB trip location foundation types (no client SDK).
 * Paths are server-composed only; never accept raw RTDB paths from clients.
 */

/** Payload written to tripLocations/{rideId}/latest (server-validated fields only). */
export interface TripLocationLatest {
  lat: number;
  lng: number;
  accuracy: number;
  heading: number;
  speed: number;
  /** Client fix timestamp (ms epoch), already server-validated. */
  ts: number;
  /** Server accept time (ISO-8601). */
  acceptedAt: string;
  driverId: string;
  locationSeq: number;
  locationStreamId: string;
}

/**
 * Minimal Admin RTDB surface for trip live-location ACL + latest projection.
 * Implementations: Firebase Admin Database, or in-memory fake for unit tests.
 */
export interface TripLocationRtdb {
  setTripLocationLatest(
    rideId: string,
    latest: TripLocationLatest,
  ): Promise<void>;
  grantRideAccess(rideId: string, uid: string): Promise<void>;
  revokeRideAccess(rideId: string): Promise<void>;
  clearTripLocations(rideId: string): Promise<void>;
}
