import { createHash } from 'node:crypto';
import { RideDomainError } from './types';
import {
  RIDE_LIST_CURSOR_VERSION,
  decodeListCursor,
  encodeListCursor,
} from './list_query';

export const OPEN_DISCOVERY_DEFAULT_LIMIT = 10;
export const OPEN_DISCOVERY_MAX_LIMIT = 50;

/** Stable binding so discovery cursors cannot be reused on owner-scoped list endpoints. */
export function discoveryBinding(): string {
  return createHash('sha256')
    .update('open-discovery:v1')
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
} {
  const allowed = new Set(['limit', 'cursor']);
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
  return { limit, cursor };
}
