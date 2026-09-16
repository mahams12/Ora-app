import { LocationDomainError, type ParsedLocationUpdate } from './types';
import { logSafe } from '../http/errors';

const MAX_ACCURACY_M = 50;
const MAX_SPEED_KMH = 200;
const STALE_PAST_MS = 15_000;
const FUTURE_SKEW_MS = 5_000;

/** Soft Pakistan bbox — warn only; never hard-reject. */
const PK_LAT_MIN = 23.5;
const PK_LAT_MAX = 37.1;
const PK_LNG_MIN = 60.9;
const PK_LNG_MAX = 77.9;

function asFiniteNumber(value: unknown, field: string): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  throw new LocationDomainError(
    'INVALID_LOCATION',
    422,
    `Invalid ${field}.`,
  );
}

function asNonEmptyString(value: unknown, field: string): string {
  if (typeof value === 'string' && value.trim() !== '') return value.trim();
  throw new LocationDomainError(
    'INVALID_LOCATION',
    422,
    `Invalid ${field}.`,
  );
}

function parseTimestampMs(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    // Accept epoch ms or seconds.
    return value < 1e12 ? value * 1000 : value;
  }
  if (typeof value === 'string' && value.trim() !== '') {
    const asNum = Number(value);
    if (Number.isFinite(asNum)) {
      return asNum < 1e12 ? asNum * 1000 : asNum;
    }
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return parsed;
  }
  throw new LocationDomainError(
    'STALE_LOCATION',
    422,
    'Location timestamp is invalid or stale.',
  );
}

/**
 * Parse + validate N2A location payload (no stream/cursor checks).
 * Does not invent teleport thresholds — plausibility deferred beyond docs' soft rules.
 */
export function parseAndValidateLocationBody(
  body: unknown,
  nowMs: number = Date.now(),
  requestId?: string,
): ParsedLocationUpdate {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'Request body must be an object.',
    );
  }
  const b = body as Record<string, unknown>;

  let rideId: string | null = null;
  if (b.rideId != null && b.rideId !== '') {
    rideId = asNonEmptyString(b.rideId, 'rideId');
  }

  const locationSeq = asFiniteNumber(b.locationSeq, 'locationSeq');
  if (!Number.isInteger(locationSeq) || locationSeq < 0) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'locationSeq must be a non-negative integer.',
    );
  }

  const locationStreamId = asNonEmptyString(
    b.locationStreamId,
    'locationStreamId',
  );
  const lat = asFiniteNumber(b.lat, 'lat');
  const lng = asFiniteNumber(b.lng, 'lng');
  if (lat < -90 || lat > 90) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'lat out of range.',
    );
  }
  if (lng < -180 || lng > 180) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'lng out of range.',
    );
  }

  const accuracy = asFiniteNumber(b.accuracy, 'accuracy');
  if (accuracy < 0 || accuracy > MAX_ACCURACY_M) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'Location accuracy exceeds 50m or is invalid.',
    );
  }

  const heading = asFiniteNumber(b.heading, 'heading');
  const speed = asFiniteNumber(b.speed, 'speed');
  if (speed < 0 || speed > MAX_SPEED_KMH) {
    throw new LocationDomainError(
      'INVALID_LOCATION',
      422,
      'Speed exceeds 200 km/h or is invalid.',
    );
  }

  const provider = asNonEmptyString(b.provider, 'provider');
  const timestampMs = parseTimestampMs(b.timestamp);

  if (
    timestampMs < nowMs - STALE_PAST_MS ||
    timestampMs > nowMs + FUTURE_SKEW_MS
  ) {
    throw new LocationDomainError(
      'STALE_LOCATION',
      422,
      'Location timestamp too old or too far in the future.',
    );
  }

  let altitude: number | null = null;
  if (b.altitude != null && b.altitude !== '') {
    altitude = asFiniteNumber(b.altitude, 'altitude');
  }

  // Soft Pakistan bbox — warn only.
  if (
    lat < PK_LAT_MIN ||
    lat > PK_LAT_MAX ||
    lng < PK_LNG_MIN ||
    lng > PK_LNG_MAX
  ) {
    logSafe('location_soft_bbox_warn', {
      requestId: requestId ?? null,
      lat,
      lng,
    });
  }

  return {
    rideId,
    locationSeq,
    locationStreamId,
    lat,
    lng,
    accuracy,
    heading,
    speed,
    timestampMs,
    provider,
    altitude,
  };
}
