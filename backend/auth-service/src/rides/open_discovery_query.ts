import { createHash } from 'node:crypto';
import { RideDomainError } from './types';
import {
  RIDE_LIST_CURSOR_VERSION,
  RIDE_LIST_SERVICE_TYPES,
  decodeListCursor,
  encodeListCursor,
} from './list_query';

export const OPEN_DISCOVERY_DEFAULT_LIMIT = 10;
export const OPEN_DISCOVERY_MAX_LIMIT = 50;

/** Max docs fetched per open-discovery scan (unordered query — no composite index). */
export const OPEN_DISCOVERY_SCAN_CAP = 200;

/**
 * Stable binding so discovery cursors cannot be reused on owner-scoped list
 * endpoints — or across different filter sets (serviceType/category are part
 * of the binding, so a cursor minted unfiltered cannot paginate a filtered
 * list and vice versa).
 */
export function discoveryBinding(filters?: {
  serviceType?: string;
  category?: string;
}): string {
  const serviceType = filters?.serviceType ?? '';
  const category = filters?.category ?? '';
  return createHash('sha256')
    .update(`open-discovery:v1:${serviceType}:${category}`)
    .digest('base64url')
    .slice(0, 22);
}

export { decodeListCursor, encodeListCursor, RIDE_LIST_CURSOR_VERSION };

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

export function parseOpenDiscoveryQuery(query: Record<string, unknown>): {
  limit: number;
  cursor: string | undefined;
  serviceType: string | undefined;
  category: string | undefined;
} {
  const allowed = new Set(['limit', 'cursor', 'serviceType', 'category']);
  const extra = Object.keys(query).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `Unknown or forbidden query parameters: ${extra.join(', ')}.`,
    );
  }

  const limitRaw = singleQueryValue(query.limit, 'limit');
  let limit = OPEN_DISCOVERY_DEFAULT_LIMIT;
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
      limit > OPEN_DISCOVERY_MAX_LIMIT
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'limit must be an integer between 1 and 50.',
      );
    }
  }

  const cursor = singleQueryValue(query.cursor, 'cursor');

  const serviceTypeRaw = singleQueryValue(query.serviceType, 'serviceType');
  let serviceType: string | undefined;
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
    serviceType = serviceTypeRaw;
  }

  const categoryRaw = singleQueryValue(query.category, 'category');
  let category: string | undefined;
  if (categoryRaw !== undefined) {
    const trimmed = categoryRaw.trim();
    if (trimmed.length === 0 || trimmed.length > 64) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'category must be a non-empty string up to 64 characters.',
      );
    }
    category = trimmed;
  }

  return { limit, cursor, serviceType, category };
}
