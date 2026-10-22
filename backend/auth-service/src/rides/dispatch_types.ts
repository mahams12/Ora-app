/**
 * N4 — Dispatch wave orchestration types & frozen constants.
 * Invitation = durable wave ledger only. Never creates rideOffers or assigns.
 */

export const DISPATCH_WAVES = 'rideDispatchWaves';
/**
 * inDrive-style gradual radius expansion per wave: wave 1 → 10 km,
 * wave 2 → 15 km, wave 3 → 25 km (N3_MAX_RADIUS_KM). Nearest-first ordering
 * within each wave is unchanged — a later wave still prefers closer drivers
 * already in range over new far ones.
 */
export const N4_WAVE_RADII_KM: readonly [number, number, number] = [10, 15, 25];
export const N4_WAVE_CADENCE_MS = 5_000;
export const N4_MAX_WAVES = 3;
export const N4_MAX_TOTAL_INVITES = 30;
/** Wave 1 → 5, wave 2 → 10, wave 3 → 15. */
export const N4_WAVE_SIZES: readonly [number, number, number] = [5, 10, 15];
/**
 * Single authoritative driver-invitation TTL (inDrive-style countdown).
 * Server-generated per wave, capped at ride.expiresAt; enforced on
 * accept/decline — never trusts a client clock.
 */
export const N4_INVITE_TTL_MS = 20_000;

export const DRIVER_INVITE_RESPONSES = 'driverInviteResponses';

export const DISPATCHABLE_STATES = ['SEARCHING', 'OFFERS_AVAILABLE'] as const;

export type DispatchStatus = 'none' | 'active' | 'exhausted' | 'stopped';

export type DispatchWaveStatus = 'COMPLETED';

export interface DispatchWaveDoc {
  waveId: string;
  rideId: string;
  waveNumber: 1 | 2 | 3;
  requestVersion: number;
  driverIds: string[];
  radiusKm: number;
  status: DispatchWaveStatus;
  correlationId: string;
  createdAt: string;
  completedAt: string;
  /** ISO — authoritative accept deadline for every driverId on this wave. */
  inviteExpiresAt?: string;
}

export type InviteResponseKind = 'ACCEPTED' | 'DECLINED';

/** Durable per-driver response to a wave invitation (idempotent ledger). */
export interface DriverInviteResponseDoc {
  responseId: string;
  rideId: string;
  waveId: string;
  driverId: string;
  response: InviteResponseKind;
  /** Present only on ACCEPTED — the created rideOffer doc id. */
  offerId?: string;
  createdAt: string;
}

export function inviteResponseDocId(
  waveId: string,
  driverId: string,
): string {
  return `${waveId}_${driverId}`;
}

export type DispatchTickOutcome =
  | 'wave_completed'
  | 'already_completed'
  | 'not_due'
  | 'skipped'
  | 'stopped'
  | 'exhausted';

export interface DispatchTickResult {
  outcome: DispatchTickOutcome;
  rideId: string;
  waveNumber: number | null;
  invitedCount: number;
  driverIds: string[];
  reason?: string;
}

export interface SweepDispatchResult {
  scanned: number;
  completed: number;
  alreadyCompleted: number;
  notDue: number;
  skipped: number;
  stopped: number;
  exhausted: number;
  failed: number;
}

export function waveDocId(rideId: string, waveNumber: number): string {
  return `${rideId}_w${waveNumber}`;
}

export function waveInviteCapacity(waveNumber: 1 | 2 | 3): number {
  return N4_WAVE_SIZES[waveNumber - 1];
}

export function waveRadiusKm(waveNumber: 1 | 2 | 3): number {
  return N4_WAVE_RADII_KM[waveNumber - 1];
}
