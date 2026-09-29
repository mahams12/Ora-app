/**
 * N4 — Dispatch wave orchestration types & frozen constants.
 * Invitation = durable wave ledger only. Never creates rideOffers or assigns.
 */

export const DISPATCH_WAVES = 'rideDispatchWaves';
export const N4_RADIUS_KM = 10;
export const N4_WAVE_CADENCE_MS = 5_000;
export const N4_MAX_WAVES = 3;
export const N4_MAX_TOTAL_INVITES = 30;
/** Wave 1 → 5, wave 2 → 10, wave 3 → 15. */
export const N4_WAVE_SIZES: readonly [number, number, number] = [5, 10, 15];

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
