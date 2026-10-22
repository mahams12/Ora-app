/**
 * NOTIF-RS-PUSH — Ride-state FCM projector types & constants.
 *
 * Identifiers-only pushes that nudge the passenger/driver app to re-fetch
 * authoritative ride state over HTTP. Push payloads are never state.
 * See docs/design/FCM_RIDE_STATE_PROJECTOR_DESIGN.md.
 */

import { createHash } from 'node:crypto';
import {
  D1_DEFAULT_SWEEP_BATCH,
  D1_LEASE_MS,
  D1_MAX_ATTEMPTS,
  D1_MAX_SWEEP_BATCH,
} from './d1_types';

export const PASSENGER_DEVICE_TOKENS = 'passengerDeviceTokens';

export const RS_SUBSCRIBER = 'fcm_ride_state';
export const RS_FCM_TYPE = 'RIDE_UPDATE';

/**
 * Closed allowlist of outbox eventTypes that produce a ride-state nudge.
 * Everything else (ride.created, ride.rating.submitted, dispatch waves, …)
 * is skipped — membership check is a Set lookup, not a prefix match.
 */
export const RS_EVENT_TYPES: ReadonlySet<string> = new Set([
  'ride.assigned',
  'ride.driver.en_route',
  'ride.driver.arrived',
  'ride.started',
  'ride.completed',
  'ride.closed',
  'ride.cancelled',
  'ride.no_show',
  'ride.expired',
  'ride.offer.received',
  'ride.offer.withdrawn',
  'ride.offer.expired',
  'ride.offer.selected',
]);

/** Scan queries use `in` — Firestore allows ≤30 values; assert at load. */
if (RS_EVENT_TYPES.size > 30) {
  throw new Error('RS_EVENT_TYPES exceeds the Firestore `in` query limit.');
}

export const RS_MAX_ATTEMPTS = D1_MAX_ATTEMPTS;
export const RS_LEASE_MS = D1_LEASE_MS;
export const RS_DEFAULT_SWEEP_BATCH = D1_DEFAULT_SWEEP_BATCH;
export const RS_MAX_SWEEP_BATCH = D1_MAX_SWEEP_BATCH;

export function rsDeliveryDocId(eventId: string): string {
  return `${eventId}_${RS_SUBSCRIBER}`;
}

/** Passenger token doc id — sha256(token) scoped under the uid. */
export function passengerTokenDocId(uid: string, token: string): string {
  const hash = createHash('sha256').update(token, 'utf8').digest('hex').slice(0, 40);
  return `${uid}_${hash}`;
}
