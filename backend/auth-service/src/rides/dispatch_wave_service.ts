/**
 * N4 — Dispatch wave orchestration.
 *
 * Invites successive nearby-driver cohorts via durable `rideDispatchWaves`
 * create-once docs + ride cursor fields. NEVER creates rideOffers or assigns.
 * Candidate source: existing N3 NearbyDriversService (pickup lat/lng only).
 */

import { randomUUID } from 'node:crypto';
import type {
  DocumentReference,
  Firestore,
} from 'firebase-admin/firestore';
import {
  NearbyDomainError,
  NearbyDriversService,
  N3_MAX_LIMIT,
} from '../drivers/nearby_service';
import { logSafe } from '../http/errors';
import type { RideDoc } from './types';
import { RideDomainError } from './types';
import {
  DISPATCH_WAVES,
  DISPATCHABLE_STATES,
  N4_MAX_TOTAL_INVITES,
  N4_MAX_WAVES,
  N4_RADIUS_KM,
  N4_WAVE_CADENCE_MS,
  waveDocId,
  waveInviteCapacity,
  type DispatchTickResult,
  type DispatchWaveDoc,
  type SweepDispatchResult,
} from './dispatch_types';

const RIDES = 'rides';
const OUTBOX = 'outboxEvents';
const DEFAULT_SWEEP_BATCH = 25;
const MAX_SWEEP_BATCH = 100;

function isFiniteLatLng(lat: unknown, lng: unknown): boolean {
  return (
    typeof lat === 'number' &&
    typeof lng === 'number' &&
    Number.isFinite(lat) &&
    Number.isFinite(lng) &&
    lat >= -90 &&
    lat <= 90 &&
    lng >= -180 &&
    lng <= 180
  );
}

function currentDispatchWave(ride: RideDoc): number {
  const w = ride.dispatchWave;
  if (typeof w !== 'number' || !Number.isInteger(w) || w < 0) return 0;
  return w;
}

function isDispatchStoppedOrExhausted(ride: RideDoc): boolean {
  return ride.dispatchStatus === 'stopped' || ride.dispatchStatus === 'exhausted';
}

export function isRideDispatchable(ride: RideDoc, nowMs: number): boolean {
  if (
    !(DISPATCHABLE_STATES as readonly string[]).includes(ride.state)
  ) {
    return false;
  }
  if (ride.assignedDriverId != null) return false;
  const expiresAtMs = Date.parse(ride.expiresAt);
  if (!Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs) return false;
  const pickup = ride.pickup;
  if (!pickup || !isFiniteLatLng(pickup.lat, pickup.lng)) return false;
  return true;
}

function isWaveDue(ride: RideDoc, nowMs: number): boolean {
  const next = ride.dispatchNextAt;
  if (next == null || next === '') return true;
  const nextMs = Date.parse(next);
  if (!Number.isFinite(nextMs)) return true;
  return nextMs <= nowMs;
}

export class DispatchWaveService {
  constructor(
    private readonly db: Firestore,
    private readonly nearby: NearbyDriversService,
  ) {}

  async tickRide(input: {
    rideId: string;
    correlationId: string;
    nowMs?: number;
  }): Promise<DispatchTickResult> {
    const nowMs = input.nowMs ?? Date.now();
    const nowIso = new Date(nowMs).toISOString();
    const rideRef = this.db.collection(RIDES).doc(input.rideId);

    const rideSnap = await rideRef.get();
    if (!rideSnap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ride = rideSnap.data() as RideDoc;

    if (isDispatchStoppedOrExhausted(ride)) {
      return {
        outcome: ride.dispatchStatus === 'exhausted' ? 'exhausted' : 'stopped',
        rideId: input.rideId,
        waveNumber: null,
        invitedCount: 0,
        driverIds: [],
        reason: `dispatch_${ride.dispatchStatus}`,
      };
    }

    if (!isRideDispatchable(ride, nowMs)) {
      await this.markStoppedIfActive(rideRef, ride, nowIso);
      return {
        outcome: 'stopped',
        rideId: input.rideId,
        waveNumber: null,
        invitedCount: 0,
        driverIds: [],
        reason: 'not_dispatchable',
      };
    }

    const lastWave = currentDispatchWave(ride);
    if (lastWave >= N4_MAX_WAVES) {
      await this.markExhausted(rideRef, ride, nowIso);
      return {
        outcome: 'exhausted',
        rideId: input.rideId,
        waveNumber: null,
        invitedCount: 0,
        driverIds: [],
        reason: 'max_waves',
      };
    }

    const nextWave = (lastWave + 1) as 1 | 2 | 3;
    const waveId = waveDocId(input.rideId, nextWave);
    const waveRef = this.db.collection(DISPATCH_WAVES).doc(waveId);

    // D-IDEM: create-once wave doc checked before cadence (freeze order).
    const existingWave = await waveRef.get();
    if (existingWave.exists) {
      const existing = existingWave.data() as DispatchWaveDoc;
      return {
        outcome: 'already_completed',
        rideId: input.rideId,
        waveNumber: nextWave,
        invitedCount: existing.driverIds?.length ?? 0,
        driverIds: existing.driverIds ?? [],
        reason: 'wave_doc_exists',
      };
    }

    if (!isWaveDue(ride, nowMs)) {
      return {
        outcome: 'not_due',
        rideId: input.rideId,
        waveNumber: nextWave,
        invitedCount: 0,
        driverIds: [],
        reason: 'dispatchNextAt',
      };
    }

    const alreadyInvited = await this.loadAlreadyInvited(input.rideId, lastWave);
    if (alreadyInvited.size >= N4_MAX_TOTAL_INVITES) {
      await this.markExhausted(rideRef, ride, nowIso);
      return {
        outcome: 'exhausted',
        rideId: input.rideId,
        waveNumber: nextWave,
        invitedCount: 0,
        driverIds: [],
        reason: 'max_invites',
      };
    }

    const capacity = waveInviteCapacity(nextWave);
    const remainingBudget = N4_MAX_TOTAL_INVITES - alreadyInvited.size;
    const need = Math.min(capacity, remainingBudget);

    let nearbyResult;
    try {
      nearbyResult = await this.nearby.findNearby({
        query: {
          lat: ride.pickup.lat,
          lng: ride.pickup.lng,
          radiusKm: N4_RADIUS_KM,
          limit: N3_MAX_LIMIT,
        },
        requestId: input.correlationId,
        nowMs,
      });
    } catch (err) {
      if (err instanceof NearbyDomainError) {
        throw new RideDomainError(err.code, err.httpStatus, err.message);
      }
      throw err;
    }

    const selected: string[] = [];
    for (const candidate of nearbyResult.candidates) {
      if (selected.length >= need) break;
      if (alreadyInvited.has(candidate.driverId)) continue;

      let stillOk: boolean;
      try {
        stillOk = await this.nearby.isStillEligibleForInvite(
          candidate.driverId,
          { nowMs, requestId: input.correlationId },
        );
      } catch (err) {
        if (err instanceof NearbyDomainError) {
          throw new RideDomainError(err.code, err.httpStatus, err.message);
        }
        throw err;
      }
      if (!stillOk) continue;
      selected.push(candidate.driverId);
    }

    const boundRequestVersion = ride.requestVersion;

    return this.db.runTransaction(async (tx) => {
      const rideSnapTx = await tx.get(rideRef);
      if (!rideSnapTx.exists) {
        throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
      }
      const rideTx = rideSnapTx.data() as RideDoc;

      const waveSnapTx = await tx.get(waveRef);
      if (waveSnapTx.exists) {
        const existing = waveSnapTx.data() as DispatchWaveDoc;
        return {
          outcome: 'already_completed' as const,
          rideId: input.rideId,
          waveNumber: nextWave,
          invitedCount: existing.driverIds?.length ?? 0,
          driverIds: existing.driverIds ?? [],
          reason: 'wave_doc_exists',
        };
      }

      if (isDispatchStoppedOrExhausted(rideTx)) {
        return {
          outcome:
            rideTx.dispatchStatus === 'exhausted'
              ? ('exhausted' as const)
              : ('stopped' as const),
          rideId: input.rideId,
          waveNumber: null,
          invitedCount: 0,
          driverIds: [],
          reason: `dispatch_${rideTx.dispatchStatus}`,
        };
      }

      if (!isRideDispatchable(rideTx, nowMs)) {
        tx.update(rideRef, {
          dispatchStatus: 'stopped',
          dispatchNextAt: null,
          updatedAt: nowIso,
        });
        return {
          outcome: 'stopped' as const,
          rideId: input.rideId,
          waveNumber: null,
          invitedCount: 0,
          driverIds: [],
          reason: 'not_dispatchable',
        };
      }

      if (rideTx.requestVersion !== boundRequestVersion) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          waveNumber: nextWave,
          invitedCount: 0,
          driverIds: [],
          reason: 'request_version_mismatch',
        };
      }

      if (currentDispatchWave(rideTx) !== lastWave) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          waveNumber: nextWave,
          invitedCount: 0,
          driverIds: [],
          reason: 'dispatch_wave_advanced',
        };
      }

      if (!isWaveDue(rideTx, nowMs)) {
        return {
          outcome: 'not_due' as const,
          rideId: input.rideId,
          waveNumber: nextWave,
          invitedCount: 0,
          driverIds: [],
          reason: 'dispatchNextAt',
        };
      }

      const waveDoc: DispatchWaveDoc = {
        waveId,
        rideId: input.rideId,
        waveNumber: nextWave,
        requestVersion: boundRequestVersion,
        driverIds: selected,
        radiusKm: N4_RADIUS_KM,
        status: 'COMPLETED',
        correlationId: input.correlationId,
        createdAt: nowIso,
        completedAt: nowIso,
      };
      tx.set(waveRef, waveDoc as unknown as Record<string, unknown>);

      const exhausted = nextWave >= N4_MAX_WAVES;
      const nextAt = exhausted
        ? null
        : new Date(nowMs + N4_WAVE_CADENCE_MS).toISOString();

      tx.update(rideRef, {
        dispatchWave: nextWave,
        dispatchNextAt: nextAt,
        dispatchStatus: exhausted ? 'exhausted' : 'active',
        updatedAt: nowIso,
      });

      const eventId = randomUUID();
      tx.set(this.db.collection(OUTBOX).doc(eventId), {
        eventId,
        eventType: 'ride.dispatch.wave_completed',
        aggregateType: 'ride',
        aggregateId: input.rideId,
        aggregateVersion: rideTx.version,
        schemaVersion: 1,
        occurredAt: nowIso,
        correlationId: input.correlationId,
        causationId: waveId,
        payload: {
          rideId: input.rideId,
          waveNumber: nextWave,
          driverIds: selected,
          invitedCount: selected.length,
          radiusKm: N4_RADIUS_KM,
        },
        publishState: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: nowIso,
      });

      logSafe('N4_DISPATCH_WAVE', {
        operation: 'N4_DISPATCH_WAVE',
        requestId: input.correlationId,
        rideId: input.rideId,
        waveNumber: nextWave,
        invitedCount: selected.length,
      });

      return {
        outcome: 'wave_completed' as const,
        rideId: input.rideId,
        waveNumber: nextWave,
        invitedCount: selected.length,
        driverIds: selected,
      };
    });
  }

  async sweepDispatch(input: {
    correlationId: string;
    limit?: number;
    nowMs?: number;
  }): Promise<SweepDispatchResult> {
    const limit = Math.min(
      Math.max(input.limit ?? DEFAULT_SWEEP_BATCH, 1),
      MAX_SWEEP_BATCH,
    );
    const nowMs = input.nowMs ?? Date.now();

    const snap = await this.db
      .collection(RIDES)
      .where('state', 'in', [...DISPATCHABLE_STATES])
      .limit(limit)
      .get();

    const result: SweepDispatchResult = {
      scanned: snap.docs.length,
      completed: 0,
      alreadyCompleted: 0,
      notDue: 0,
      skipped: 0,
      stopped: 0,
      exhausted: 0,
      failed: 0,
    };

    for (const doc of snap.docs) {
      try {
        const ride = doc.data() as RideDoc;
        if (!isRideDispatchable(ride, nowMs)) {
          result.skipped += 1;
          continue;
        }
        if (isDispatchStoppedOrExhausted(ride)) {
          if (ride.dispatchStatus === 'exhausted') result.exhausted += 1;
          else result.stopped += 1;
          continue;
        }
        if (!isWaveDue(ride, nowMs)) {
          result.notDue += 1;
          continue;
        }

        const outcome = await this.tickRide({
          rideId: doc.id,
          correlationId: input.correlationId,
          nowMs,
        });

        switch (outcome.outcome) {
          case 'wave_completed':
            result.completed += 1;
            break;
          case 'already_completed':
            result.alreadyCompleted += 1;
            break;
          case 'not_due':
            result.notDue += 1;
            break;
          case 'stopped':
            result.stopped += 1;
            break;
          case 'exhausted':
            result.exhausted += 1;
            break;
          default:
            result.skipped += 1;
        }
      } catch {
        result.failed += 1;
      }
    }

    return result;
  }

  private async loadAlreadyInvited(
    rideId: string,
    lastCompletedWave: number,
  ): Promise<Set<string>> {
    const invited = new Set<string>();
    for (let w = 1; w <= lastCompletedWave; w += 1) {
      const snap = await this.db
        .collection(DISPATCH_WAVES)
        .doc(waveDocId(rideId, w))
        .get();
      if (!snap.exists) continue;
      const data = snap.data() as DispatchWaveDoc;
      for (const id of data.driverIds ?? []) {
        invited.add(id);
      }
    }
    return invited;
  }

  private async markStoppedIfActive(
    rideRef: DocumentReference,
    ride: RideDoc,
    nowIso: string,
  ): Promise<void> {
    if (ride.dispatchStatus === 'stopped' || ride.dispatchStatus === 'exhausted') {
      return;
    }
    if (
      ride.dispatchStatus === 'active' ||
      (typeof ride.dispatchWave === 'number' && ride.dispatchWave > 0)
    ) {
      await rideRef.update({
        dispatchStatus: 'stopped',
        dispatchNextAt: null,
        updatedAt: nowIso,
      });
    }
  }

  private async markExhausted(
    rideRef: DocumentReference,
    ride: RideDoc,
    nowIso: string,
  ): Promise<void> {
    if (ride.dispatchStatus === 'exhausted') return;
    await rideRef.update({
      dispatchStatus: 'exhausted',
      dispatchNextAt: null,
      updatedAt: nowIso,
    });
  }
}
