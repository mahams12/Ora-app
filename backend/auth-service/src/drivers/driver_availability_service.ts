import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { loadActor, type EligibleActor } from '../rides/eligibility';
import { RideDomainError } from '../rides/types';
import type { RedisGeoProjectionService } from '../redis/geo_projection';
import {
  DriverDomainError,
  type AvailabilityState,
  type DriverAvailabilitySnapshot,
} from './types';

const DRIVERS = 'drivers';

/**
 * N1 — durable driver availability.
 * N2C — on go-offline, best-effort Redis GEO removal (non-authoritative).
 *
 * Authority:
 * - Firestore `drivers/{driverId}.availabilityState` (schema: offline | online)
 * - Approval gate via `users/{uid}` (existing loadActor / driverStatus)
 */
export class DriverAvailabilityService {
  constructor(
    private readonly db: Firestore,
    private readonly geoProjection: RedisGeoProjectionService | null = null,
  ) {}

  async goOnline(input: {
    caller: AuthenticatedCaller;
  }): Promise<{ httpStatus: number; body: { data: DriverAvailabilitySnapshot } }> {
    const actor = await this.loadApprovedDriver(input.caller.uid);
    const snapshot = await this.transition(actor.uid, 'online');
    return { httpStatus: 200, body: { data: snapshot } };
  }

  async goOffline(input: {
    caller: AuthenticatedCaller;
    requestId?: string;
  }): Promise<{ httpStatus: number; body: { data: DriverAvailabilitySnapshot } }> {
    const actor = await this.loadApprovedDriver(input.caller.uid);
    const homeCity = await this.readHomeCity(actor.uid);
    const snapshot = await this.transition(actor.uid, 'offline');
    if (this.geoProjection) {
      await this.geoProjection.removeDriverOnOffline({
        driverId: actor.uid,
        homeCity,
        requestId: input.requestId,
      });
    }
    return { httpStatus: 200, body: { data: snapshot } };
  }

  private async readHomeCity(driverId: string): Promise<unknown> {
    const snap = await this.db.collection(DRIVERS).doc(driverId).get();
    return snap.exists ? (snap.data() ?? {}).homeCity : undefined;
  }

  private async loadApprovedDriver(uid: string): Promise<EligibleActor> {
    let actor: EligibleActor;
    try {
      actor = await loadActor(this.db, uid);
    } catch (err) {
      if (err instanceof RideDomainError) {
        throw new DriverDomainError(err.code, err.httpStatus, err.message);
      }
      throw err;
    }
    if (actor.role !== 'driver' || actor.driverStatus !== 'approved') {
      throw new DriverDomainError(
        'DRIVER_NOT_APPROVED',
        403,
        'Driver must be approved to change availability.',
      );
    }
    return actor;
  }

  /**
   * Transactional upsert of `drivers/{driverId}.availabilityState`.
   * Missing doc is treated as offline. Already-at-target is an idempotent no-op.
   */
  private async transition(
    driverId: string,
    target: AvailabilityState,
  ): Promise<DriverAvailabilitySnapshot> {
    const nowIso = new Date().toISOString();
    return this.db.runTransaction(async (tx) => {
      const ref = this.db.collection(DRIVERS).doc(driverId);
      const snap = await tx.get(ref);
      const existing = snap.exists ? (snap.data() ?? {}) : null;
      const current: AvailabilityState =
        existing && existing.availabilityState === 'online'
          ? 'online'
          : 'offline';

      if (current === target && existing) {
        return {
          driverId,
          availabilityState: current,
        };
      }

      if (existing) {
        const patch: Record<string, unknown> = {
          availabilityState: target,
          updatedAt: nowIso,
        };
        if (target === 'online') {
          patch.lastOnlineAt = nowIso;
        }
        tx.update(ref, patch);
      } else {
        const created: Record<string, unknown> = {
          driverId,
          userId: driverId,
          availabilityState: target,
          createdAt: nowIso,
          updatedAt: nowIso,
        };
        if (target === 'online') {
          created.lastOnlineAt = nowIso;
        }
        tx.set(ref, created);
      }

      return {
        driverId,
        availabilityState: target,
      };
    });
  }
}
