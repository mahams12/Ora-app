import {
  rideAccessRidePath,
  rideAccessUidPath,
  tripLocationLatestPath,
  tripLocationsRidePath,
} from './paths';
import type { TripLocationLatest, TripLocationRtdb } from './types';

/**
 * In-memory RTDB stand-in for unit proofs (no emulator / live Firebase required).
 * Stores values under the same path strings the Admin helper uses.
 */
export class MemoryTripLocationRtdb implements TripLocationRtdb {
  /** Full path → JSON value (primitives or objects). */
  readonly store = new Map<string, unknown>();

  async setTripLocationLatest(
    rideId: string,
    latest: TripLocationLatest,
  ): Promise<void> {
    this.store.set(tripLocationLatestPath(rideId), { ...latest });
  }

  async grantRideAccess(rideId: string, uid: string): Promise<void> {
    this.store.set(rideAccessUidPath(rideId, uid), true);
  }

  async revokeRideAccess(rideId: string): Promise<void> {
    const prefix = `${rideAccessRidePath(rideId)}/`;
    const ridePath = rideAccessRidePath(rideId);
    for (const key of [...this.store.keys()]) {
      if (key === ridePath || key.startsWith(prefix)) {
        this.store.delete(key);
      }
    }
  }

  async clearTripLocations(rideId: string): Promise<void> {
    const prefix = `${tripLocationsRidePath(rideId)}/`;
    const ridePath = tripLocationsRidePath(rideId);
    for (const key of [...this.store.keys()]) {
      if (key === ridePath || key.startsWith(prefix)) {
        this.store.delete(key);
      }
    }
  }

  get(path: string): unknown {
    return this.store.get(path);
  }
}
