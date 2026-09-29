/**
 * D1 — Dispatch invite delivery types & constants.
 */

import { createHash } from 'node:crypto';

export const DRIVER_DEVICE_TOKENS = 'driverDeviceTokens';
export const OUTBOX_EVENTS = 'outboxEvents';
export const OUTBOX_DELIVERIES = 'outboxDeliveries';

export const D1_EVENT_TYPE = 'ride.dispatch.wave_completed';
export const D1_SUBSCRIBER = 'fcm_dispatch_invite';
export const D1_FCM_TYPE = 'DISPATCH_INVITE';

/** Phase-1.6 FCM dispatcher target (~10 / 30 min). */
export const D1_MAX_ATTEMPTS = 10;
export const D1_LEASE_MS = 30_000;
export const D1_DEFAULT_SWEEP_BATCH = 25;
export const D1_MAX_SWEEP_BATCH = 100;

export type OutboxPublishState =
  | 'PENDING'
  | 'CLAIMED'
  | 'DELIVERED'
  | 'DEAD_LETTER';

export type OutboxDeliveryStatus =
  | 'PENDING'
  | 'CLAIMED'
  | 'ACKED'
  | 'FAILED_RETRYABLE'
  | 'DEAD_LETTER';

export type DriverDeliveryStatus =
  | 'PENDING'
  | 'SENT'
  | 'SKIPPED_NO_TOKEN'
  | 'INVALID_TOKEN_REMOVED'
  | 'FAILED_RETRYABLE';

/** Per-device token outcome within a driver's delivery result (H5). */
export type TokenDeliveryStatus =
  | 'SENT'
  | 'FAILED_RETRYABLE'
  | 'INVALID_TOKEN_REMOVED';

export interface DriverDeviceTokenDoc {
  tokenId: string;
  driverId: string;
  token: string;
  createdAt: string;
  updatedAt: string;
}

export interface TokenDeliveryResult {
  status: TokenDeliveryStatus;
  lastError: string | null;
  updatedAt: string;
}

export interface DriverDeliveryResult {
  status: DriverDeliveryStatus;
  lastError: string | null;
  updatedAt: string;
  /**
   * Per-device outcomes keyed by sha256(token)[:40].
   * A successful token must not hide another token's FAILED_RETRYABLE (H5).
   */
  tokenResults?: Record<string, TokenDeliveryResult>;
}

export interface OutboxDeliveryDoc {
  deliveryId: string;
  eventId: string;
  subscriber: typeof D1_SUBSCRIBER;
  status: OutboxDeliveryStatus;
  attemptCount: number;
  leaseOwner: string | null;
  leaseExpiresAt: string | null;
  driverResults: Record<string, DriverDeliveryResult>;
  lastError: string | null;
  createdAt: string;
  updatedAt: string;
}

export function deviceTokenDocId(driverId: string, token: string): string {
  const hash = createHash('sha256').update(token, 'utf8').digest('hex').slice(0, 40);
  return `${driverId}_${hash}`;
}

/** Stable key for per-token delivery results (hash only; scoped under driverResults). */
export function tokenResultKey(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex').slice(0, 40);
}

export function outboxDeliveryDocId(eventId: string): string {
  return `${eventId}_${D1_SUBSCRIBER}`;
}

/** Aggregate driver-level status from per-token outcomes. */
export function aggregateDriverStatus(
  tokenResults: Record<string, TokenDeliveryResult>,
): DriverDeliveryStatus {
  const statuses = Object.values(tokenResults).map((r) => r.status);
  if (statuses.length === 0) return 'SKIPPED_NO_TOKEN';
  if (statuses.some((s) => s === 'FAILED_RETRYABLE')) return 'FAILED_RETRYABLE';
  if (statuses.every((s) => s === 'INVALID_TOKEN_REMOVED')) {
    return 'INVALID_TOKEN_REMOVED';
  }
  if (statuses.some((s) => s === 'SENT')) return 'SENT';
  return 'SKIPPED_NO_TOKEN';
}

/** Exponential backoff with jitter; capped for D1 FCM window. */
export function d1NextAttemptAt(attemptCount: number, nowMs: number): string {
  const baseMs = Math.min(60_000 * 2 ** Math.max(0, attemptCount - 1), 5 * 60_000);
  const jitter = Math.floor(Math.random() * 1_000);
  return new Date(nowMs + baseMs + jitter).toISOString();
}
