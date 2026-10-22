/**
 * NOTIF-RS-PUSH — Ride-state FCM outbox projector.
 *
 * Emits identifiers-only `{type: RIDE_UPDATE, rideId, eventId}` data pushes to
 * the passenger/driver of a ride on allowlisted lifecycle + offer events.
 * The push is a non-authoritative wake-up: clients re-fetch ride state over
 * HTTP. Recipients are resolved server-side from rides/{id} (and
 * rideOffers/{offerId} for offer.selected) — never from caller input.
 *
 * Delivery mechanics mirror D1 (docs/design/FCM_RIDE_STATE_PROJECTOR_DESIGN.md):
 * PENDING-first scan, expired-lease reclaim, CAS (leaseOwner, attemptCount)
 * fencing, durable per-recipient/per-token results, bounded retries, dead
 * letters, invalid-token cleanup.
 *
 * Does NOT: mutate ride lifecycle, pricing, matching, or driver-location state.
 */

import type { Firestore } from 'firebase-admin/firestore';
import { logSafe } from '../http/errors';
import { RideDomainError, type OutboxEventDoc } from '../rides/types';
import type { RideDoc } from '../rides/types';
import { DeviceTokenService } from './device_token_service';
import type { FcmSender } from './fcm_sender';
import {
  OUTBOX_DELIVERIES,
  OUTBOX_EVENTS,
  aggregateDriverStatus,
  d1NextAttemptAt,
  tokenResultKey,
  type DriverDeliveryResult,
  type OutboxDeliveryDoc,
  type OutboxPublishState,
  type TokenDeliveryResult,
} from './d1_types';
import {
  RS_DEFAULT_SWEEP_BATCH,
  RS_EVENT_TYPES,
  RS_FCM_TYPE,
  RS_LEASE_MS,
  RS_MAX_ATTEMPTS,
  RS_MAX_SWEEP_BATCH,
  RS_SUBSCRIBER,
  rsDeliveryDocId,
} from './ride_state_types';

const RIDES = 'rides';
const OFFERS = 'rideOffers';

export interface RideStateFcmSweepResult {
  scanned: number;
  processed: number;
  delivered: number;
  retryable: number;
  deadLetter: number;
  skipped: number;
  failed: number;
}

export interface RideStateProcessResult {
  eventId: string;
  outcome:
    | 'delivered'
    | 'retryable'
    | 'dead_letter'
    | 'skipped'
    | 'already_done'
    | 'stale_aborted';
  sent: number;
  skippedNoToken: number;
  invalidTokens: number;
  failedRecipients: number;
}

function isLeaseActive(
  leaseExpiresAt: string | null | undefined,
  nowMs: number,
): boolean {
  if (!leaseExpiresAt) return false;
  const ms = Date.parse(leaseExpiresAt);
  return Number.isFinite(ms) && ms > nowMs;
}

function isRecipientTerminal(status: DriverDeliveryResult['status']): boolean {
  return (
    status === 'SENT' ||
    status === 'SKIPPED_NO_TOKEN' ||
    status === 'INVALID_TOKEN_REMOVED'
  );
}

type FinishKind = 'retryable' | 'dead_letter' | 'delivered';
type TokenStore = 'driver' | 'passenger';

interface ResolvedRecipients {
  rideId: string;
  uids: string[];
}

export class RideStateFcmProjector {
  private readonly tokens: DeviceTokenService;

  constructor(
    private readonly db: Firestore,
    private readonly fcm: FcmSender,
  ) {
    this.tokens = new DeviceTokenService(db);
  }

  async sweep(input: {
    correlationId: string;
    limit?: number;
    nowMs?: number;
    workerId?: string;
  }): Promise<RideStateFcmSweepResult> {
    const limit = Math.min(
      Math.max(input.limit ?? RS_DEFAULT_SWEEP_BATCH, 1),
      RS_MAX_SWEEP_BATCH,
    );
    const nowMs = input.nowMs ?? Date.now();
    const workerId = input.workerId ?? input.correlationId;
    const allowlist = [...RS_EVENT_TYPES];

    // Same PENDING-first scan as D1: avoids re-reading terminal backlog.
    const pendingSnap = await this.db
      .collection(OUTBOX_EVENTS)
      .where('eventType', 'in', allowlist)
      .where('publishState', '==', 'PENDING')
      .limit(limit)
      .get();

    const docs = [...pendingSnap.docs];
    const claimedBudget = limit - pendingSnap.docs.length;
    if (claimedBudget > 0) {
      const claimedSnap = await this.db
        .collection(OUTBOX_EVENTS)
        .where('eventType', 'in', allowlist)
        .where('publishState', '==', 'CLAIMED')
        .limit(claimedBudget)
        .get();
      docs.push(...claimedSnap.docs);
    }

    const result: RideStateFcmSweepResult = {
      scanned: docs.length,
      processed: 0,
      delivered: 0,
      retryable: 0,
      deadLetter: 0,
      skipped: 0,
      failed: 0,
    };

    for (const doc of docs) {
      const event = doc.data() as OutboxEventDoc & {
        publishState: OutboxPublishState;
        leaseExpiresAt?: string | null;
      };
      if (
        event.publishState === 'DELIVERED' ||
        event.publishState === 'DEAD_LETTER'
      ) {
        result.skipped += 1;
        continue;
      }
      if (
        event.publishState === 'CLAIMED' &&
        isLeaseActive(event.leaseExpiresAt, nowMs)
      ) {
        result.skipped += 1;
        continue;
      }
      if (event.publishState === 'PENDING') {
        const nextMs = Date.parse(event.nextAttemptAt);
        if (Number.isFinite(nextMs) && nextMs > nowMs) {
          result.skipped += 1;
          continue;
        }
      }

      try {
        const outcome = await this.processEvent({
          eventId: doc.id,
          correlationId: input.correlationId,
          workerId,
          nowMs,
        });
        result.processed += 1;
        if (outcome.outcome === 'delivered' || outcome.outcome === 'already_done') {
          result.delivered += 1;
        } else if (outcome.outcome === 'retryable') {
          result.retryable += 1;
        } else if (outcome.outcome === 'dead_letter') {
          result.deadLetter += 1;
        } else {
          result.skipped += 1;
        }
      } catch {
        result.failed += 1;
      }
    }

    return result;
  }

  /**
   * Server-authoritative recipient resolution. Reads the ride doc once;
   * offer.selected falls back to rideOffers/{offerId}.driverId when the ride
   * has no assignedDriverId yet.
   */
  async resolveRecipients(event: OutboxEventDoc): Promise<ResolvedRecipients> {
    const rideId = String(event.aggregateId ?? event.payload.rideId ?? '');
    if (!rideId) return { rideId: '', uids: [] };

    const rideSnap = await this.db.collection(RIDES).doc(rideId).get();
    const ride = rideSnap.exists ? (rideSnap.data() as RideDoc) : null;
    const passengerId = ride?.passengerId ?? null;
    const assignedDriverId =
      typeof ride?.assignedDriverId === 'string' && ride.assignedDriverId
        ? ride.assignedDriverId
        : null;

    const both = [passengerId, assignedDriverId].filter(
      (u): u is string => !!u,
    );
    const passengerOnly = passengerId ? [passengerId] : [];

    let uids: string[];
    switch (event.eventType) {
      case 'ride.assigned':
      case 'ride.completed':
      case 'ride.closed':
      case 'ride.cancelled':
      case 'ride.no_show':
        uids = both;
        break;
      case 'ride.driver.en_route':
      case 'ride.driver.arrived':
      case 'ride.started':
      case 'ride.expired':
      case 'ride.offer.received':
      case 'ride.offer.withdrawn':
      case 'ride.offer.expired':
        uids = passengerOnly;
        break;
      case 'ride.offer.selected': {
        // Driver may not be on the ride doc yet — resolve from the offer doc.
        let offerDriverId: string | null = assignedDriverId;
        if (!offerDriverId) {
          const offerId = String(event.payload.offerId ?? '');
          if (offerId) {
            const offerSnap = await this.db
              .collection(OFFERS)
              .doc(offerId)
              .get();
            const offerDriver = offerSnap.exists
              ? (offerSnap.data() as { driverId?: unknown }).driverId
              : null;
            if (typeof offerDriver === 'string' && offerDriver) {
              offerDriverId = offerDriver;
            }
          }
        }
        if (!offerDriverId) {
          const payloadDriver = event.payload.driverId;
          if (typeof payloadDriver === 'string' && payloadDriver) {
            offerDriverId = payloadDriver;
          }
        }
        uids = offerDriverId ? [offerDriverId] : [];
        break;
      }
      default:
        uids = [];
    }

    return { rideId, uids: [...new Set(uids)] };
  }

  /** A uid may have tokens in either collection; union both, tagged by store. */
  private async tokensForUid(
    uid: string,
  ): Promise<Array<{ token: string; store: TokenStore }>> {
    const [driverTokens, passengerTokens] = await Promise.all([
      this.tokens.listTokensForDriver(uid),
      this.tokens.listTokensForPassenger(uid),
    ]);
    const out = new Map<string, TokenStore>();
    for (const t of driverTokens) out.set(t, 'driver');
    for (const t of passengerTokens) {
      if (!out.has(t)) out.set(t, 'passenger');
    }
    return [...out.entries()].map(([token, store]) => ({ token, store }));
  }

  async processEvent(input: {
    eventId: string;
    correlationId: string;
    workerId: string;
    nowMs?: number;
  }): Promise<RideStateProcessResult> {
    const nowMs = input.nowMs ?? Date.now();
    const nowIso = new Date(nowMs).toISOString();
    const eventRef = this.db.collection(OUTBOX_EVENTS).doc(input.eventId);
    const deliveryId = rsDeliveryDocId(input.eventId);
    const deliveryRef = this.db.collection(OUTBOX_DELIVERIES).doc(deliveryId);

    const claimed = await this.db.runTransaction(async (tx) => {
      const eventSnap = await tx.get(eventRef);
      if (!eventSnap.exists) {
        throw new RideDomainError('NOT_FOUND', 404, 'Outbox event not found.');
      }
      const event = eventSnap.data() as OutboxEventDoc & {
        publishState: OutboxPublishState;
        leaseExpiresAt?: string | null;
        leaseOwner?: string | null;
      };

      if (!RS_EVENT_TYPES.has(event.eventType)) {
        return { skip: true as const, reason: 'not_allowlisted' as const };
      }
      if (event.publishState === 'DELIVERED') {
        return { skip: true as const, reason: 'already_delivered' as const };
      }
      if (event.publishState === 'DEAD_LETTER') {
        return { skip: true as const, reason: 'dead_letter' as const };
      }
      if (
        event.publishState === 'CLAIMED' &&
        isLeaseActive(event.leaseExpiresAt, nowMs) &&
        event.leaseOwner !== input.workerId
      ) {
        return { skip: true as const, reason: 'lease_held' as const };
      }

      const deliverySnap = await tx.get(deliveryRef);
      let delivery: OutboxDeliveryDoc;
      if (deliverySnap.exists) {
        delivery = deliverySnap.data() as OutboxDeliveryDoc;
        if (delivery.status === 'ACKED') {
          tx.update(eventRef, {
            publishState: 'DELIVERED',
            updatedAt: nowIso,
          });
          return { skip: true as const, reason: 'already_acked' as const };
        }
        if (delivery.status === 'DEAD_LETTER') {
          return { skip: true as const, reason: 'delivery_dead' as const };
        }
        delivery = {
          ...delivery,
          status: 'CLAIMED',
          attemptCount: delivery.attemptCount + 1,
          leaseOwner: input.workerId,
          leaseExpiresAt: new Date(nowMs + RS_LEASE_MS).toISOString(),
          updatedAt: nowIso,
        };
      } else {
        delivery = {
          deliveryId,
          eventId: input.eventId,
          subscriber: RS_SUBSCRIBER,
          status: 'CLAIMED',
          attemptCount: 1,
          leaseOwner: input.workerId,
          leaseExpiresAt: new Date(nowMs + RS_LEASE_MS).toISOString(),
          driverResults: {},
          lastError: null,
          createdAt: nowIso,
          updatedAt: nowIso,
        };
      }

      tx.set(deliveryRef, delivery as unknown as Record<string, unknown>);
      tx.update(eventRef, {
        publishState: 'CLAIMED',
        leaseOwner: input.workerId,
        leaseExpiresAt: delivery.leaseExpiresAt,
        attemptCount: delivery.attemptCount,
        updatedAt: nowIso,
      });

      return { skip: false as const, event, delivery };
    });

    if (claimed.skip) {
      return {
        eventId: input.eventId,
        outcome:
          claimed.reason === 'already_delivered' ||
          claimed.reason === 'already_acked'
            ? 'already_done'
            : 'skipped',
        sent: 0,
        skippedNoToken: 0,
        invalidTokens: 0,
        failedRecipients: 0,
      };
    }

    const { event, delivery } = claimed;
    const fence = {
      workerId: input.workerId,
      attemptCount: delivery.attemptCount,
    };
    const { rideId, uids } = await this.resolveRecipients(event);
    const recipientResults: Record<string, DriverDeliveryResult> = {
      ...delivery.driverResults,
    };

    let sent = 0;
    let skippedNoToken = 0;
    let invalidTokens = 0;
    let failedRecipients = 0;

    for (const uid of uids) {
      const prior = recipientResults[uid];
      if (prior && isRecipientTerminal(prior.status)) {
        if (prior.status === 'SENT') sent += 1;
        if (prior.status === 'SKIPPED_NO_TOKEN') skippedNoToken += 1;
        if (prior.status === 'INVALID_TOKEN_REMOVED') invalidTokens += 1;
        continue;
      }

      const tokenEntries = await this.tokensForUid(uid);
      if (tokenEntries.length === 0) {
        recipientResults[uid] = {
          status: 'SKIPPED_NO_TOKEN',
          lastError: null,
          updatedAt: new Date().toISOString(),
          tokenResults: {},
        };
        skippedNoToken += 1;
        continue;
      }

      const tokenResults: Record<string, TokenDeliveryResult> = {
        ...(prior?.tokenResults ?? {}),
      };
      const tickIso = new Date().toISOString();

      for (const { token, store } of tokenEntries) {
        const key = tokenResultKey(token);
        const priorTok = tokenResults[key];
        if (
          priorTok &&
          (priorTok.status === 'SENT' ||
            priorTok.status === 'INVALID_TOKEN_REMOVED')
        ) {
          continue;
        }

        const result = await this.fcm.sendDataOnly({
          token,
          data: {
            type: RS_FCM_TYPE,
            rideId,
            eventId: input.eventId,
          },
        });

        if (result === 'ok') {
          tokenResults[key] = {
            status: 'SENT',
            lastError: null,
            updatedAt: tickIso,
          };
        } else if (result === 'invalid_token') {
          if (store === 'driver') {
            await this.tokens.deleteTokenByValue(uid, token);
          } else {
            await this.tokens.deletePassengerTokenByValue(uid, token);
          }
          tokenResults[key] = {
            status: 'INVALID_TOKEN_REMOVED',
            lastError: 'invalid_token',
            updatedAt: tickIso,
          };
          invalidTokens += 1;
        } else {
          tokenResults[key] = {
            status: 'FAILED_RETRYABLE',
            lastError: 'fcm_transient',
            updatedAt: tickIso,
          };
        }
      }

      const uidStatus = aggregateDriverStatus(tokenResults);
      const lastError =
        uidStatus === 'FAILED_RETRYABLE'
          ? 'partial_or_transient_fcm_failure'
          : uidStatus === 'INVALID_TOKEN_REMOVED'
            ? 'all_tokens_invalid'
            : null;

      recipientResults[uid] = {
        status: uidStatus,
        lastError,
        updatedAt: tickIso,
        tokenResults,
      };

      if (uidStatus === 'SENT') sent += 1;
      else if (uidStatus === 'SKIPPED_NO_TOKEN') skippedNoToken += 1;
      else if (uidStatus === 'FAILED_RETRYABLE') failedRecipients += 1;
    }

    const anyRetryable = Object.values(recipientResults).some(
      (r) => r.status === 'FAILED_RETRYABLE',
    );
    const attemptCount = fence.attemptCount;
    const finishIso = new Date().toISOString();

    let kind: FinishKind;
    let deliveryStatus: OutboxDeliveryDoc['status'];
    let deliveryLastError: string | null;
    let eventPublish: OutboxPublishState;
    let nextAttemptAt: string | undefined;
    let outcome: RideStateProcessResult['outcome'];

    if (anyRetryable && attemptCount < RS_MAX_ATTEMPTS) {
      kind = 'retryable';
      deliveryStatus = 'FAILED_RETRYABLE';
      deliveryLastError = 'partial_or_transient_fcm_failure';
      eventPublish = 'PENDING';
      nextAttemptAt = d1NextAttemptAt(attemptCount, nowMs);
      outcome = 'retryable';
    } else if (anyRetryable && attemptCount >= RS_MAX_ATTEMPTS) {
      kind = 'dead_letter';
      deliveryStatus = 'DEAD_LETTER';
      deliveryLastError = 'max_attempts_exhausted';
      eventPublish = 'DEAD_LETTER';
      outcome = 'dead_letter';
    } else {
      kind = 'delivered';
      deliveryStatus = 'ACKED';
      deliveryLastError = null;
      eventPublish = 'DELIVERED';
      outcome = 'delivered';
    }

    const committed = await this.commitFenced({
      eventId: input.eventId,
      deliveryId,
      fence,
      recipientResults,
      deliveryStatus,
      deliveryLastError,
      eventPublish,
      nextAttemptAt,
      finishIso,
      attemptCount,
    });

    if (!committed) {
      logSafe('RS_RIDE_FCM', {
        operation: 'RS_RIDE_FCM',
        requestId: input.correlationId,
        eventId: input.eventId,
        outcome: 'stale_aborted',
        attemptCount: fence.attemptCount,
        workerId: fence.workerId,
      });
      return {
        eventId: input.eventId,
        outcome: 'stale_aborted',
        sent,
        skippedNoToken,
        invalidTokens,
        failedRecipients,
      };
    }

    logSafe('RS_RIDE_FCM', {
      operation: 'RS_RIDE_FCM',
      requestId: input.correlationId,
      eventId: input.eventId,
      outcome: kind,
      sent,
      skippedNoToken,
      invalidTokens,
      failedRecipients,
    });

    return {
      eventId: input.eventId,
      outcome,
      sent,
      skippedNoToken,
      invalidTokens,
      failedRecipients,
    };
  }

  /** CAS finish — identical fencing semantics to D1. */
  private async commitFenced(input: {
    eventId: string;
    deliveryId: string;
    fence: { workerId: string; attemptCount: number };
    recipientResults: Record<string, DriverDeliveryResult>;
    deliveryStatus: OutboxDeliveryDoc['status'];
    deliveryLastError: string | null;
    eventPublish: OutboxPublishState;
    nextAttemptAt?: string;
    finishIso: string;
    attemptCount: number;
  }): Promise<boolean> {
    const eventRef = this.db.collection(OUTBOX_EVENTS).doc(input.eventId);
    const deliveryRef = this.db
      .collection(OUTBOX_DELIVERIES)
      .doc(input.deliveryId);

    return this.db.runTransaction(async (tx) => {
      const deliverySnap = await tx.get(deliveryRef);
      if (!deliverySnap.exists) return false;
      const current = deliverySnap.data() as OutboxDeliveryDoc;

      if (current.leaseOwner !== input.fence.workerId) return false;
      if (current.attemptCount !== input.fence.attemptCount) return false;
      if (current.status !== 'CLAIMED') return false;

      const eventSnap = await tx.get(eventRef);
      if (!eventSnap.exists) return false;
      const event = eventSnap.data() as OutboxEventDoc & {
        publishState: OutboxPublishState;
        leaseOwner?: string | null;
        attemptCount?: number;
      };
      if (event.leaseOwner !== input.fence.workerId) return false;
      if (event.attemptCount !== input.fence.attemptCount) return false;
      if (event.publishState !== 'CLAIMED') return false;

      const nextDelivery: OutboxDeliveryDoc = {
        ...current,
        status: input.deliveryStatus,
        leaseOwner: null,
        leaseExpiresAt: null,
        driverResults: input.recipientResults,
        lastError: input.deliveryLastError,
        updatedAt: input.finishIso,
        attemptCount: input.attemptCount,
      };
      tx.set(deliveryRef, nextDelivery as unknown as Record<string, unknown>);

      const eventUpdate: Record<string, unknown> = {
        publishState: input.eventPublish,
        leaseOwner: null,
        leaseExpiresAt: null,
        attemptCount: input.attemptCount,
        updatedAt: input.finishIso,
      };
      if (input.nextAttemptAt != null) {
        eventUpdate.nextAttemptAt = input.nextAttemptAt;
      }
      tx.update(eventRef, eventUpdate);
      return true;
    });
  }
}
