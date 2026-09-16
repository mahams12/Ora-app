import { createHash } from 'node:crypto';
import { RideDomainError } from './types';

export const RIDE_LIST_DEFAULT_LIMIT = 10;
export const RIDE_LIST_MAX_LIMIT = 50;
export const RIDE_LIST_CURSOR_VERSION = 1;

export const RIDE_LIST_STATUSES = ['all', 'completed', 'cancelled'] as const;
export type RideListStatus = (typeof RIDE_LIST_STATUSES)[number];

export const RIDE_LIST_SERVICE_TYPES = [
  'ride',
  'courier',
  'intercity',
  'move',
] as const;
export type RideListServiceType = (typeof RIDE_LIST_SERVICE_TYPES)[number];

export type RideListQueryRole = 'passenger' | 'driver';

export interface RideListCursor {
  createdAt: string;
  rideId: string;
  v: number;
  ob: string;
}

export function ownerBinding(
  uid: string,
  queryRole: RideListQueryRole,
): string {
  return createHash('sha256')
    .update(`${uid}:${queryRole}`)
    .digest('base64url')
    .slice(0, 22);
}

export function encodeListCursor(cursor: RideListCursor): string {
  return Buffer.from(JSON.stringify(cursor), 'utf8').toString('base64url');
}

export function decodeListCursor(
  raw: string,
  expectedOwnerBinding: string,
): RideListCursor {
  let json: string;
  try {
    json = Buffer.from(raw, 'base64url').toString('utf8');
  } catch {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Invalid cursor encoding.',
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Invalid cursor payload.',
    );
  }
  if (parsed == null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Invalid cursor payload.',
    );
  }
  const obj = parsed as Record<string, unknown>;
  if (obj.v !== RIDE_LIST_CURSOR_VERSION) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Unsupported cursor version.',
    );
  }
  if (typeof obj.createdAt !== 'string' || !obj.createdAt.trim()) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Cursor missing createdAt.',
    );
  }
  if (Number.isNaN(Date.parse(obj.createdAt))) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Cursor createdAt is invalid.',
    );
  }
  if (typeof obj.rideId !== 'string' || !obj.rideId.trim()) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Cursor missing rideId.',
    );
  }
  if (typeof obj.ob !== 'string' || !obj.ob.trim()) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Cursor missing owner binding.',
    );
  }
  if (obj.ob !== expectedOwnerBinding) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Cursor is not valid for this actor.',
    );
  }
  return {
    createdAt: obj.createdAt,
    rideId: obj.rideId,
    v: RIDE_LIST_CURSOR_VERSION,
    ob: obj.ob,
  };
}

function singleQueryValue(
  value: unknown,
  field: string,
): string | undefined {
  if (value === undefined) return undefined;
  if (Array.isArray(value)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `Query parameter ${field} must be a single value.`,
    );
  }
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `Query parameter ${field} is invalid.`,
    );
  }
  return String(value);
}

export function parseRideListQuery(query: Record<string, unknown>): {
  limit: number;
  cursor: string | undefined;
  status: RideListStatus;
  serviceType: RideListServiceType | undefined;
} {
  const allowed = new Set(['limit', 'cursor', 'status', 'serviceType']);
  const extra = Object.keys(query).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `Unknown or forbidden query parameters: ${extra.join(', ')}.`,
    );
  }

  const limitRaw = singleQueryValue(query.limit, 'limit');
  let limit = RIDE_LIST_DEFAULT_LIMIT;
  if (limitRaw !== undefined) {
    if (!/^\d+$/.test(limitRaw)) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'limit must be an integer between 1 and 50.',
      );
    }
    limit = Number(limitRaw);
    if (
      !Number.isInteger(limit) ||
      limit < 1 ||
      limit > RIDE_LIST_MAX_LIMIT
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'limit must be an integer between 1 and 50.',
      );
    }
  }

  const cursor = singleQueryValue(query.cursor, 'cursor');

  const statusRaw = singleQueryValue(query.status, 'status');
  let status: RideListStatus = 'all';
  if (statusRaw !== undefined) {
    if (!(RIDE_LIST_STATUSES as readonly string[]).includes(statusRaw)) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'status must be one of: all, completed, cancelled.',
      );
    }
    status = statusRaw as RideListStatus;
  }

  const serviceTypeRaw = singleQueryValue(query.serviceType, 'serviceType');
  let serviceType: RideListServiceType | undefined;
  if (serviceTypeRaw !== undefined) {
    if (
      !(RIDE_LIST_SERVICE_TYPES as readonly string[]).includes(serviceTypeRaw)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'serviceType must be one of: ride, courier, intercity, move.',
      );
    }
    serviceType = serviceTypeRaw as RideListServiceType;
  }

  return { limit, cursor, status, serviceType };
}

export function completedStates(): string[] {
  return ['RIDE_COMPLETED', 'RIDE_CLOSED'];
}
