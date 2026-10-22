/**
 * Driver-invitation API — inDrive-style incoming-request flow.
 *
 * A dispatch wave (rideDispatchWaves doc) IS the invitation: its driverIds are
 * the invited drivers and inviteExpiresAt (server-generated, N4_INVITE_TTL_MS)
 * is the single authoritative countdown deadline.
 *
 * Accept → creates a PASSENGER_PRICE_ACCEPTED fare offer through the existing
 * RideService.createOffer transaction (passenger still selects — accept is
 * NOT an assignment). Decline → durable per-driver response ledger
 * (driverInviteResponses). Both are idempotent and safe to retry.
 *
 * The response doc doubles as a claim: whichever of accept/decline commits
 * first wins, so concurrent taps cannot produce both an offer and a decline.
 */

import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { logSafe } from '../http/errors';
import { assertDriverEligible, loadActor } from './eligibility';
import { RideService } from './ride_service';
import { RideDomainError, type RideDoc } from './types';
import {
  DISPATCH_WAVES,
  DRIVER_INVITE_RESPONSES,
  DISPATCHABLE_STATES,
  inviteResponseDocId,
  type DispatchWaveDoc,
  type DriverInviteResponseDoc,
  type InviteResponseKind,
} from './dispatch_types';

const RIDES = 'rides';
/** Scan cap for the array-contains listing — bounded read, sorted in code. */
const INVITED_SCAN_LIMIT = 100;
const INVITED_PAGE_LIMIT = 25;

export type InviteStatus =
  | 'ACTIVE'
  | 'EXPIRED'
  | 'RESPONDED_ACCEPTED'
  | 'RESPONDED_DECLINED'
  | 'CLOSED';

export interface InvitedRideItem {
  rideId: string;
  waveId: string;
  waveNumber: number;
  status: InviteStatus;
  inviteExpiresAt: string | null;
  respondedAt: string | null;
  offerId: string | null;
  pickup: { lat: number; lng: number; address?: string };
  destination: { lat: number; lng: number; address?: string };
  passengerOfferMinor: number;
  currency: string;
  serviceType: string;
  category: string;
  distanceKm: number | null;
  passengerCount: number;
}

function inviteExpiryMs(wave: DispatchWaveDoc): number | null {
  if (!wave.inviteExpiresAt) return null;
  const ms = Date.parse(wave.inviteExpiresAt);
  return Number.isFinite(ms) ? ms : null;
}

function isInviteExpired(wave: DispatchWaveDoc, nowMs: number): boolean {
  const expiry = inviteExpiryMs(wave);
  if (expiry == null) return true; // legacy wave without deadline → treat as expired
  return nowMs >= expiry;
}

export class InviteService {
  constructor(
    private readonly db: Firestore,
    private readonly rides: RideService,
  ) {}

  /**
   * GET /v1/rides/invited — waves that invited this driver, newest first.
   * Bounded array-contains scan; join rides + responses via batched getAll.
   */
  async listInvited(input: {
    caller: AuthenticatedCaller;
    nowMs?: number;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const nowMs = input.nowMs ?? Date.now();
    const actor = await loadActor(this.db, input.caller.uid);
    assertDriverEligible(actor);

    const waveSnap = await this.db
      .collection(DISPATCH_WAVES)
      .where('driverIds', 'array-contains', input.caller.uid)
      .limit(INVITED_SCAN_LIMIT)
      .get();

    const waves = waveSnap.docs
      .map((d) => d.data() as DispatchWaveDoc)
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))
      .slice(0, INVITED_PAGE_LIMIT);

    // Batch-load rides + per-driver response docs.
    const rideRefs = waves.map((w) =>
      this.db.collection(RIDES).doc(w.rideId),
    );
    const responseRefs = waves.map((w) =>
      this.db
        .collection(DRIVER_INVITE_RESPONSES)
        .doc(inviteResponseDocId(w.waveId, input.caller.uid)),
    );
    const [rideSnaps, responseSnaps] = await Promise.all([
      rideRefs.length ? this.db.getAll(...rideRefs) : Promise.resolve([]),
      responseRefs.length
        ? this.db.getAll(...responseRefs)
        : Promise.resolve([]),
    ]);

    const items: InvitedRideItem[] = [];
    for (let i = 0; i < waves.length; i += 1) {
      const wave = waves[i];
      const rideSnap = rideSnaps[i];
      if (!rideSnap.exists) continue; // ride gone — nothing actionable
      const ride = rideSnap.data() as RideDoc;
      const response = responseSnaps[i].exists
        ? (responseSnaps[i].data() as DriverInviteResponseDoc)
        : null;

      let status: InviteStatus;
      if (response?.response === 'ACCEPTED') {
        status = 'RESPONDED_ACCEPTED';
      } else if (response?.response === 'DECLINED') {
        status = 'RESPONDED_DECLINED';
      } else if (
        ride.assignedDriverId != null ||
        !(DISPATCHABLE_STATES as readonly string[]).includes(ride.state) ||
        ride.requestVersion !== wave.requestVersion
      ) {
        status = 'CLOSED';
      } else if (isInviteExpired(wave, nowMs)) {
        status = 'EXPIRED';
      } else {
        status = 'ACTIVE';
      }

      items.push({
        rideId: wave.rideId,
        waveId: wave.waveId,
        waveNumber: wave.waveNumber,
        status,
        inviteExpiresAt: wave.inviteExpiresAt ?? null,
        respondedAt: response?.createdAt ?? null,
        offerId: response?.offerId ?? null,
        pickup: ride.pickup,
        destination: ride.destination,
        passengerOfferMinor: ride.passengerOfferMinor,
        currency: 'PKR',
        serviceType: ride.serviceType,
        category: ride.category,
        distanceKm: ride.distanceKm,
        passengerCount: ride.passengerCount,
      });
    }

    return {
      httpStatus: 200,
      body: {
        data: {
          items,
          // Client computes remaining = inviteExpiresAt - (serverNow + rtt/2).
          serverNowMs: nowMs,
        },
      },
    };
  }

  /**
   * POST /v1/rides/:rideId/invites/:waveId/accept
   * Validates the invitation (ownership + authoritative expiry), then creates
   * the fare offer via createOffer under a deterministic idempotency key.
   */
  async acceptInvite(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    waveId: string;
    correlationId: string;
    nowMs?: number;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const nowMs = input.nowMs ?? Date.now();
    const wave = await this.loadOwnedWave(input);

    const responseRef = this.db
      .collection(DRIVER_INVITE_RESPONSES)
      .doc(inviteResponseDocId(wave.waveId, input.caller.uid));

    // Fast path: idempotent replay.
    const prior = await responseRef.get();
    if (prior.exists) {
      const doc = prior.data() as DriverInviteResponseDoc;
      if (doc.response === 'DECLINED') {
        throw new RideDomainError(
          'INVITE_ALREADY_RESPONDED',
          409,
          'Invitation already declined.',
        );
      }
      if (doc.offerId != null) {
        return this.acceptedResponse(input.rideId, wave, doc.offerId);
      }
      // Claim exists but offer creation did not finish — fall through to retry
      // (deterministic idempotency key replays the prior createOffer).
    } else {
      if (isInviteExpired(wave, nowMs)) {
        throw new RideDomainError(
          'INVITE_EXPIRED',
          409,
          'Invitation has expired.',
        );
      }
      // Claim the invite before creating the offer — first writer wins vs
      // a concurrent decline.
      const claimed = await this.db.runTransaction(async (tx) => {
        const snap = await tx.get(responseRef);
        if (snap.exists) return false;
        const claim: DriverInviteResponseDoc = {
          responseId: inviteResponseDocId(wave.waveId, input.caller.uid),
          rideId: input.rideId,
          waveId: wave.waveId,
          driverId: input.caller.uid,
          response: 'ACCEPTED',
          createdAt: new Date(nowMs).toISOString(),
        };
        tx.set(responseRef, claim as unknown as Record<string, unknown>);
        return true;
      });
      if (!claimed) {
        const now2 = await responseRef.get();
        const doc = now2.data() as DriverInviteResponseDoc;
        if (doc.response === 'DECLINED') {
          throw new RideDomainError(
            'INVITE_ALREADY_RESPONDED',
            409,
            'Invitation already declined.',
          );
        }
        if (doc.offerId != null) {
          return this.acceptedResponse(input.rideId, wave, doc.offerId);
        }
      }
    }

    // Re-read the ride for the accept-amount (createOffer revalidates all of
    // this inside its own transaction anyway).
    const rideSnap = await this.db.collection(RIDES).doc(input.rideId).get();
    if (!rideSnap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ride = rideSnap.data() as RideDoc;

    const result = await this.rides.createOffer({
      caller: input.caller,
      rideId: input.rideId,
      body: {
        type: 'PASSENGER_PRICE_ACCEPTED',
        amountMinor: ride.passengerOfferMinor,
        expectedRequestVersion: wave.requestVersion,
      },
      // Deterministic key → network retries and double taps replay, never
      // duplicate.
      idempotencyKeyHeader: `invite_accept_${wave.waveId}_${input.caller.uid}`,
      correlationId: input.correlationId,
    });

    const offerId = (
      (result.body as { data?: { offerId?: string } }).data ?? {}
    ).offerId;
    if (offerId) {
      await responseRef.set(
        { offerId } as Record<string, unknown>,
        { merge: true },
      );
    }

    logSafe('INVITE_ACCEPT', {
      operation: 'INVITE_ACCEPT',
      requestId: input.correlationId,
      actorId: input.caller.uid,
      rideId: input.rideId,
      waveId: wave.waveId,
      offerId: offerId ?? null,
    });
    return result;
  }

  /**
   * POST /v1/rides/:rideId/invites/:waveId/decline
   * Durable + idempotent. Declining after expiry is allowed (records intent;
   * the invite can no longer be accepted either way). Dispatch waves never
   * wait on responses, so decline/expiry never blocks other drivers.
   */
  async declineInvite(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    waveId: string;
    correlationId: string;
    nowMs?: number;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const nowMs = input.nowMs ?? Date.now();
    const wave = await this.loadOwnedWave(input);

    const responseRef = this.db
      .collection(DRIVER_INVITE_RESPONSES)
      .doc(inviteResponseDocId(wave.waveId, input.caller.uid));

    const outcome = await this.db.runTransaction(async (tx) => {
      const snap = await tx.get(responseRef);
      if (snap.exists) {
        return snap.data() as DriverInviteResponseDoc;
      }
      const doc: DriverInviteResponseDoc = {
        responseId: inviteResponseDocId(wave.waveId, input.caller.uid),
        rideId: input.rideId,
        waveId: wave.waveId,
        driverId: input.caller.uid,
        response: 'DECLINED',
        createdAt: new Date(nowMs).toISOString(),
      };
      tx.set(responseRef, doc as unknown as Record<string, unknown>);
      return doc;
    });

    if (outcome.response === 'ACCEPTED') {
      throw new RideDomainError(
        'INVITE_ALREADY_RESPONDED',
        409,
        'Invitation already accepted.',
      );
    }

    logSafe('INVITE_DECLINE', {
      operation: 'INVITE_DECLINE',
      requestId: input.correlationId,
      actorId: input.caller.uid,
      rideId: input.rideId,
      waveId: wave.waveId,
    });
    return {
      httpStatus: 200,
      body: {
        data: {
          rideId: input.rideId,
          waveId: wave.waveId,
          response: 'DECLINED' as InviteResponseKind,
        },
      },
    };
  }

  /** Load wave, verify it belongs to this ride and invited this driver. */
  private async loadOwnedWave(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    waveId: string;
  }): Promise<DispatchWaveDoc> {
    const actor = await loadActor(this.db, input.caller.uid);
    assertDriverEligible(actor);

    const snap = await this.db
      .collection(DISPATCH_WAVES)
      .doc(input.waveId)
      .get();
    if (!snap.exists) {
      throw new RideDomainError('INVITE_NOT_FOUND', 404, 'Invite not found.');
    }
    const wave = snap.data() as DispatchWaveDoc;
    if (wave.rideId !== input.rideId) {
      throw new RideDomainError('INVITE_NOT_FOUND', 404, 'Invite not found.');
    }
    if (!(wave.driverIds ?? []).includes(input.caller.uid)) {
      throw new RideDomainError(
        'FORBIDDEN',
        403,
        'This invitation belongs to another driver.',
      );
    }
    return wave;
  }

  private acceptedResponse(
    rideId: string,
    wave: DispatchWaveDoc,
    offerId: string,
  ): { httpStatus: number; body: unknown } {
    return {
      httpStatus: 200,
      body: {
        data: {
          rideId,
          waveId: wave.waveId,
          response: 'ACCEPTED' as InviteResponseKind,
          offerId,
        },
      },
    };
  }
}
