/**
 * D1 — Minimal outbox projector for ride.dispatch.wave_completed → FCM.
 *
 * Does NOT: assign, create offers, call N3, use city/GEO, mutate ride lifecycle.
 * At-least-once FCM wake-up only; FCM is non-authoritative.
 *
 * H2: durable finish writes are fenced by (leaseOwner, attemptCount) CAS.
 * H5: per-token results; successful tokens are not resent while others retry.
 */

import type { Firestore } from 'firebase-admin/firestore';
import { logSafe } from '../http/errors';
import { RideDomainError, type OutboxEventDoc } from '../rides/types';
import { DeviceTokenService } from './device_token_service';
import type { FcmSender } from './fcm_sender';
import {
  D1_DEFAULT_SWEEP_BATCH,
  D1_EVENT_TYPE,
  D1_FCM_TYPE,
  D1_LEASE_MS,
  D1_MAX_ATTEMPTS,
  D1_MAX_SWEEP_BATCH,
  D1_SUBSCRIBER,
  OUTBOX_DELIVERIES,
  OUTBOX_EVENTS,
  aggregateDriverStatus,
  d1NextAttemptAt,
  outboxDeliveryDocId,
  tokenResultKey,
  type DriverDeliveryResult,
  type OutboxDeliveryDoc,
  type OutboxPublishState,
  type TokenDeliveryResult,
} from './d1_types';

export interface DispatchFcmSweepResult {
  scanned: number;
  processed: number;
  delivered: number;
  retryable: number;
  deadLetter: number;
  skipped: number;
  failed: number;
}

export interface ProcessEventResult {
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
  failedDrivers: number;
}

function isLeaseActive(
  leaseExpiresAt: string | null | undefined,
  nowMs: number,
): boolean {
  if (!leaseExpiresAt) return false;
  const ms = Date.parse(leaseExpiresAt);
  return Number.isFinite(ms) && ms > nowMs;
}

function parseDriverIds(payload: Record<string, unknown>): string[] {
  const raw = payload.driverIds;
  if (!Array.isArray(raw)) return [];
  return raw.filter((id): id is string => typeof id === 'string' && id.length > 0);
}

function isDriverTerminal(status: DriverDeliveryResult['status']): boolean {
  return (
    status === 'SENT' ||
    status === 'SKIPPED_NO_TOKEN' ||
    status === 'INVALID_TOKEN_REMOVED'
  );
}

type FinishKind = 'retryable' | 'dead_letter' | 'delivered';

export class DispatchFcmProjector {
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
  }): Promise<DispatchFcmSweepResult> {
    const limit = Math.min(
      Math.max(input.limit ?? D1_DEFAULT_SWEEP_BATCH, 1),
      D1_MAX_SWEEP_BATCH,
    );
    const nowMs = input.nowMs ?? Date.now();
    const workerId = input.workerId ?? input.correlationId;

    const snap = await this.db
      .collection(OUTBOX_EVENTS)
      .where('eventType', '==', D1_EVENT_TYPE)
      .limit(limit)
      .get();

    const result: DispatchFcmSweepResult = {
      scanned: snap.docs.length,
      processed: 0,
      delivered: 0,
      retryable: 0,
      deadLetter: 0,
      skipped: 0,
      failed: 0,
    };

    for (const doc of snap.docs) {
      const event = doc.data() as OutboxEventDoc & {
        publishState: OutboxPublishState;
        leaseExpiresAt?: string | null;
      };
      if (event.publishState === 'DELIVERED' || event.publishState === 'DEAD_LETTER') {
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

  async processEvent(input: {
    eventId: string;
    correlationId: string;
    workerId: string;
    nowMs?: number;
  }): Promise<ProcessEventResult> {
    const nowMs = input.nowMs ?? Date.now();
    const nowIso = new Date(nowMs).toISOString();
    const eventRef = this.db.collection(OUTBOX_EVENTS).doc(input.eventId);
    const deliveryId = outboxDeliveryDocId(input.eventId);
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

      if (event.eventType !== D1_EVENT_TYPE) {
        return { skip: true as const, reason: 'wrong_event_type' as const };
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
          leaseExpiresAt: new Date(nowMs + D1_LEASE_MS).toISOString(),
          updatedAt: nowIso,
        };
      } else {
        delivery = {
          deliveryId,
          eventId: input.eventId,
          subscriber: D1_SUBSCRIBER,
          status: 'CLAIMED',
          attemptCount: 1,
          leaseOwner: input.workerId,
          leaseExpiresAt: new Date(nowMs + D1_LEASE_MS).toISOString(),
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

      return {
        skip: false as const,
        event,
        delivery,
      };
    });

    if (claimed.skip) {
      return {
        eventId: input.eventId,
        outcome:
          claimed.reason === 'already_delivered' || claimed.reason === 'already_acked'
            ? 'already_done'
            : 'skipped',
        sent: 0,
        skippedNoToken: 0,
        invalidTokens: 0,
        failedDrivers: 0,
      };
    }

    const { event, delivery } = claimed;
    const fence = {
      workerId: input.workerId,
      attemptCount: delivery.attemptCount,
    };
    const driverIds = parseDriverIds(event.payload);
    const rideId = String(event.payload.rideId ?? event.aggregateId);
    const waveNumber = String(event.payload.waveNumber ?? '');
    const driverResults: Record<string, DriverDeliveryResult> = {
      ...delivery.driverResults,
    };

    let sent = 0;
    let skippedNoToken = 0;
    let invalidTokens = 0;
    let failedDrivers = 0;

    for (const driverId of driverIds) {
      const prior = driverResults[driverId];
      if (prior && isDriverTerminal(prior.status)) {
        if (prior.status === 'SENT') sent += 1;
        if (prior.status === 'SKIPPED_NO_TOKEN') skippedNoToken += 1;
        if (prior.status === 'INVALID_TOKEN_REMOVED') invalidTokens += 1;
        continue;
      }

      const tokens = await this.tokens.listTokensForDriver(driverId);
      if (tokens.length === 0) {
        driverResults[driverId] = {
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

      for (const token of tokens) {
        const key = tokenResultKey(token);
        const priorTok = tokenResults[key];
        if (
          priorTok &&
          (priorTok.status === 'SENT' || priorTok.status === 'INVALID_TOKEN_REMOVED')
        ) {
          continue;
        }

        const result = await this.fcm.sendDataOnly({
          token,
          data: {
            type: D1_FCM_TYPE,
            rideId,
            waveNumber,
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
          await this.tokens.deleteTokenByValue(driverId, token);
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

      // Tokens that existed in prior results but were removed from registry stay as-is.
      const driverStatus = aggregateDriverStatus(tokenResults);
      const lastError =
        driverStatus === 'FAILED_RETRYABLE'
          ? 'partial_or_transient_fcm_failure'
          : driverStatus === 'INVALID_TOKEN_REMOVED'
            ? 'all_tokens_invalid'
            : null;

      driverResults[driverId] = {
        status: driverStatus,
        lastError,
        updatedAt: tickIso,
        tokenResults,
      };

      if (driverStatus === 'SENT') sent += 1;
      else if (driverStatus === 'SKIPPED_NO_TOKEN') skippedNoToken += 1;
      else if (driverStatus === 'FAILED_RETRYABLE') failedDrivers += 1;
    }

    const anyRetryable = Object.values(driverResults).some(
      (r) => r.status === 'FAILED_RETRYABLE',
    );
    const attemptCount = fence.attemptCount;
    const finishIso = new Date().toISOString();

    let kind: FinishKind;
    let deliveryStatus: OutboxDeliveryDoc['status'];
    let deliveryLastError: string | null;
    let eventPublish: OutboxPublishState;
    let nextAttemptAt: string | undefined;
    let outcome: ProcessEventResult['outcome'];

    if (anyRetryable && attemptCount < D1_MAX_ATTEMPTS) {
      kind = 'retryable';
      deliveryStatus = 'FAILED_RETRYABLE';
      deliveryLastError = 'partial_or_transient_fcm_failure';
      eventPublish = 'PENDING';
      nextAttemptAt = d1NextAttemptAt(attemptCount, nowMs);
      outcome = 'retryable';
    } else if (anyRetryable && attemptCount >= D1_MAX_ATTEMPTS) {
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
      driverResults,
      deliveryStatus,
      deliveryLastError,
      eventPublish,
      nextAttemptAt,
      finishIso,
      attemptCount,
    });

    if (!committed) {
      logSafe('D1_DISPATCH_FCM', {
        operation: 'D1_DISPATCH_FCM',
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
        failedDrivers,
      };
    }

    logSafe('D1_DISPATCH_FCM', {
      operation: 'D1_DISPATCH_FCM',
      requestId: input.correlationId,
      eventId: input.eventId,
      outcome: kind,
      sent,
      skippedNoToken,
      invalidTokens,
      failedDrivers,
    });

    return {
      eventId: input.eventId,
      outcome,
      sent,
      skippedNoToken,
      invalidTokens,
      failedDrivers,
    };
  }

  /**
   * H2 — CAS finish: only the worker that owns this exact attempt may write.
   * Stale workers (lease reclaimed / attempt advanced) become durable no-ops.
   */
  private async commitFenced(input: {
    eventId: string;
    deliveryId: string;
    fence: { workerId: string; attemptCount: number };
    driverResults: Record<string, DriverDeliveryResult>;
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
        driverResults: input.driverResults,
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
