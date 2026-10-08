import type { Database } from 'firebase-admin/database';
import {
  rideAccessRidePath,
  rideAccessUidPath,
  tripLocationLatestPath,
  tripLocationsRidePath,
} from './paths';
import type { TripLocationLatest, TripLocationRtdb } from './types';

/**
 * Admin-SDK RTDB writer for tripLocations + rideAccess.
 * Clients never call this; paths are never taken from request bodies as raw paths.
 */
export class AdminTripLocationRtdb implements TripLocationRtdb {
  constructor(private readonly database: Database) {}

  async setTripLocationLatest(
    rideId: string,
    latest: TripLocationLatest,
  ): Promise<void> {
    await this.database.ref(tripLocationLatestPath(rideId)).set({
      lat: latest.lat,
      lng: latest.lng,
      accuracy: latest.accuracy,
      heading: latest.heading,
      speed: latest.speed,
      ts: latest.ts,
      acceptedAt: latest.acceptedAt,
      driverId: latest.driverId,
      locationSeq: latest.locationSeq,
      locationStreamId: latest.locationStreamId,
    });
  }

  async grantRideAccess(rideId: string, uid: string): Promise<void> {
    await this.database.ref(rideAccessUidPath(rideId, uid)).set(true);
  }

  async revokeRideAccess(rideId: string): Promise<void> {
    await this.database.ref(rideAccessRidePath(rideId)).remove();
  }

  async clearTripLocations(rideId: string): Promise<void> {
    await this.database.ref(tripLocationsRidePath(rideId)).remove();
  }
}

/** No-op when FIREBASE_DATABASE_URL is unset (local/tests without RTDB). */
export class NullTripLocationRtdb implements TripLocationRtdb {
  async setTripLocationLatest(): Promise<void> {
    /* no-op */
  }
  async grantRideAccess(): Promise<void> {
    /* no-op */
  }
  async revokeRideAccess(): Promise<void> {
    /* no-op */
  }
  async clearTripLocations(): Promise<void> {
    /* no-op */
  }
}
