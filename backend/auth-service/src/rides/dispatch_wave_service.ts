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
  type N3InviteRevalidationContext,
} from '../drivers/nearby_service';
import { logSafe } from '../http/errors';
import type { DispatchTaskScheduler } from '../tasks/dispatch_tasks';
import { driverCourierVehicle, type RideDoc } from './types';
import { RideDomainError } from './types';
import {
  DISPATCH_WAVES,
  DISPATCHABLE_STATES,
  DRIVER_INVITE_RESPONSES,
  N4_INVITE_TTL_MS,
  N4_MAX_TOTAL_INVITES,
  N4_MAX_WAVES,
  N4_WAVE_CADENCE_MS,
  waveDocId,
  waveInviteCapacity,
  waveRadiusKm,
  type DispatchTickResult,
  type DispatchWaveDoc,
  type DriverInviteResponseDoc,
  type SweepDispatchResult,
} from './dispatch_types';

const RIDES = 'rides';
const OUTBOX = 'outboxEvents';
const DEFAULT_SWEEP_BATCH = 25;
const MAX_SWEEP_BATCH = 100;
/**
 * Candidates revalidated per batched context load. Wave capacity is ≤15;
 * 25 covers the selection plus typical ineligible candidates in one
 * parallel read batch, while bounding worst-case reads at 4 loads for a
 * full 100-candidate result.
 */
const N4_INVITE_REVALIDATION_CHUNK = 25;

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
    private readonly scheduler?: DispatchTaskScheduler,
  ) {}

  /**
   * Arms a Cloud Task for the next dispatch wake-up. Best-effort by design:
   * failure is logged, not thrown — the low-frequency sweep and event-driven
   * ticks recover any missed wake-up.
   */
  private async armNextTick(input: {
    rideId: string;
    waveNumber: number;
    runAtMs: number;
    correlationId: string;
  }): Promise<void> {
    if (!this.scheduler) return;
    try {
      await this.scheduler.scheduleDispatchTick(input);
    } catch (err) {
      logSafe('N4_DISPATCH_TASK_FAILED', {
        operation: 'N4_DISPATCH_TASK_FAILED',
        requestId: input.correlationId,
        rideId: input.rideId,
        waveNumber: input.waveNumber,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

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
      // Self-heal: a task that fired early (or a manual tick) re-arms at the
      // true deadline so a single wake-up miss can't stall progression.
      const nextMs = Date.parse(ride.dispatchNextAt ?? '');
      if (Number.isFinite(nextMs)) {
        await this.armNextTick({
          rideId: input.rideId,
          waveNumber: nextWave,
          runAtMs: nextMs,
          correlationId: input.correlationId,
        });
      }
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
    const searchRadiusKm = waveRadiusKm(nextWave);

    let nearbyResult;
    try {
      nearbyResult = await this.nearby.findNearby({
        query: {
          lat: ride.pickup.lat,
          lng: ride.pickup.lng,
          radiusKm: searchRadiusKm,
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
    const candidateIds = nearbyResult.candidates.map((c) => c.driverId);
    // Revalidation contexts are loaded lazily in nearest-first chunks: the
    // selection loop almost always finishes inside the first chunk, so a
    // wave costs ~1 batched read set instead of up to 4 serial round-trips
    // per candidate. Every eligibility rule is identical — only the read
    // pattern changed.
    let revalidationCtx: N3InviteRevalidationContext | null = null;
    let ctxCoveredUntil = 0;
    for (let i = 0; i < nearbyResult.candidates.length; i++) {
      const candidate = nearbyResult.candidates[i];
      if (selected.length >= need) break;
      if (alreadyInvited.has(candidate.driverId)) continue;

      if (i >= ctxCoveredUntil) {
        const end = Math.min(
          i + N4_INVITE_REVALIDATION_CHUNK,
          candidateIds.length,
        );
        try {
          revalidationCtx = await this.nearby.loadInviteRevalidationContext(
            candidateIds.slice(i, end),
            { requestId: input.correlationId },
          );
        } catch (err) {
          if (err instanceof NearbyDomainError) {
            throw new RideDomainError(err.code, err.httpStatus, err.message);
          }
          throw err;
        }
        ctxCoveredUntil = end;
      }

      let stillOk: boolean;
      try {
        stillOk = await this.nearby.isStillEligibleForInvite(
          candidate.driverId,
          {
            nowMs,
            requestId: input.correlationId,
            revalidation: revalidationCtx ?? undefined,
          },
        );
      } catch (err) {
        if (err instanceof NearbyDomainError) {
          throw new RideDomainError(err.code, err.httpStatus, err.message);
        }
        throw err;
      }
      if (!stillOk) continue;

      // Ora Courier — sender-requested vehicle class: only invite drivers
      // whose registered vehicle maps to it. Driver docs are already in the
      // batched revalidation context — no extra reads.
      if (ride.serviceType === 'courier' && ride.courierVehicle) {
        const driverDoc =
          revalidationCtx?.prefetched.driverByDriverId.get(
            candidate.driverId,
          ) ?? null;
        if (driverCourierVehicle(driverDoc) !== ride.courierVehicle) {
          continue;
        }
      }

      selected.push(candidate.driverId);
    }

    const boundRequestVersion = ride.requestVersion;

    const result = await this.db.runTransaction(async (tx) => {
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

      // Authoritative invite deadline: 20s from wave completion, never past
      // the ride's own expiry (isRideDispatchable already guarantees a finite
      // future expiresAt).
      const rideExpiryMs = Date.parse(rideTx.expiresAt);
      const inviteExpiresAt = new Date(
        Math.min(nowMs + N4_INVITE_TTL_MS, rideExpiryMs),
      ).toISOString();

      const waveDoc: DispatchWaveDoc = {
        waveId,
        rideId: input.rideId,
        waveNumber: nextWave,
        requestVersion: boundRequestVersion,
        driverIds: selected,
        radiusKm: searchRadiusKm,
        status: 'COMPLETED',
        correlationId: input.correlationId,
        createdAt: nowIso,
        completedAt: nowIso,
        inviteExpiresAt,
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
          radiusKm: searchRadiusKm,
          inviteExpiresAt,
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

    // Post-commit: arm the next wave's deadline wake-up. Task names embed
    // (rideId, wave, target-second) so concurrent armers dedupe at the queue.
    if (
      result.outcome === 'wave_completed' &&
      (result.waveNumber ?? 0) < N4_MAX_WAVES
    ) {
      await this.armNextTick({
        rideId: input.rideId,
        waveNumber: (result.waveNumber ?? 0) + 1,
        runAtMs: nowMs + N4_WAVE_CADENCE_MS,
        correlationId: input.correlationId,
      });
    }

    return result;
  }

  /**
   * Event-driven fast path: when every driver in the LATEST wave has a
   * durable response (accept/decline), pull the next wave forward instead of
   * waiting out the cadence. Overlapping earlier-wave invites stay valid —
   * this never invalidates a live invitation.
   */
  async accelerateIfWaveResolved(input: {
    rideId: string;
    correlationId: string;
    nowMs?: number;
  }): Promise<{ accelerated: boolean; tick?: DispatchTickResult; reason: string }> {
    const nowMs = input.nowMs ?? Date.now();
    const rideRef = this.db.collection(RIDES).doc(input.rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists) {
      return { accelerated: false, reason: 'ride_not_found' };
    }
    const ride = rideSnap.data() as RideDoc;
    if (
      isDispatchStoppedOrExhausted(ride) ||
      !isRideDispatchable(ride, nowMs)
    ) {
      return { accelerated: false, reason: 'dispatch_inactive' };
    }
    const lastWave = currentDispatchWave(ride);
    if (lastWave < 1 || lastWave >= N4_MAX_WAVES) {
      return { accelerated: false, reason: 'no_pending_wave' };
    }
    const nextMs = Date.parse(ride.dispatchNextAt ?? '');
    if (!Number.isFinite(nextMs) || nextMs <= nowMs) {
      return { accelerated: false, reason: 'already_due' };
    }

    const waveRef = this.db
      .collection(DISPATCH_WAVES)
      .doc(waveDocId(input.rideId, lastWave));
    const waveSnap = await waveRef.get();
    if (!waveSnap.exists) {
      return { accelerated: false, reason: 'wave_missing' };
    }
    const wave = waveSnap.data() as DispatchWaveDoc;
    const invited = wave.driverIds ?? [];
    if (invited.length === 0) {
      return { accelerated: false, reason: 'empty_wave' };
    }

    const responsesSnap = await this.db
      .collection(DRIVER_INVITE_RESPONSES)
      .where('waveId', '==', waveSnap.id)
      .get();
    const responded = new Set(
      responsesSnap.docs.map(
        (d) => (d.data() as DriverInviteResponseDoc).driverId,
      ),
    );
    if (!invited.every((id) => responded.has(id))) {
      return { accelerated: false, reason: 'pending_responses' };
    }

    // All invited drivers resolved — advance dispatchNextAt to now inside a
    // transaction so a concurrent tick can't race us into double-advancing.
    const armed = await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(rideRef);
      if (!snap.exists) return false;
      const cur = snap.data() as RideDoc;
      if (currentDispatchWave(cur) !== lastWave) return false;
      const curNext = Date.parse(cur.dispatchNextAt ?? '');
      if (!Number.isFinite(curNext) || curNext <= nowMs) return false;
      tx.update(rideRef, {
        dispatchNextAt: new Date(nowMs).toISOString(),
      });
      return true;
    });
    if (!armed) {
      return { accelerated: false, reason: 'race_lost' };
    }

    const tick = await this.tickRide({
      rideId: input.rideId,
      correlationId: input.correlationId,
      nowMs,
    });
    return { accelerated: true, tick, reason: 'wave_resolved' };
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
