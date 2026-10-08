/**
 * L2 Step 2 — safe RTDB path builders.
 * Rejects path-injection characters so rideId/uid cannot escape their segment.
 */

const FORBIDDEN = /[./#$\[\]]/;

export function assertSafeRtdbSegment(value: string, field: string): string {
  if (typeof value !== 'string') {
    throw new Error(`Invalid ${field}: must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed === '') {
    throw new Error(`Invalid ${field}: empty.`);
  }
  if (FORBIDDEN.test(trimmed) || trimmed.includes('/')) {
    throw new Error(`Invalid ${field}: path characters not allowed.`);
  }
  return trimmed;
}

export function tripLocationsRidePath(rideId: string): string {
  const id = assertSafeRtdbSegment(rideId, 'rideId');
  return `tripLocations/${id}`;
}

export function tripLocationLatestPath(rideId: string): string {
  return `${tripLocationsRidePath(rideId)}/latest`;
}

export function rideAccessRidePath(rideId: string): string {
  const id = assertSafeRtdbSegment(rideId, 'rideId');
  return `rideAccess/${id}`;
}

export function rideAccessUidPath(rideId: string, uid: string): string {
  const safeUid = assertSafeRtdbSegment(uid, 'uid');
  return `${rideAccessRidePath(rideId)}/${safeUid}`;
}
