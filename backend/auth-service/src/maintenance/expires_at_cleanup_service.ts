import type { Firestore } from 'firebase-admin/firestore';
import { PRICING_SNAPSHOTS_COLLECTION } from '../pricing/estimate_service';

export const IDEMPOTENCY_RECORDS_COLLECTION = 'idempotencyRecords';
export const LOCATION_STREAMS_COLLECTION = 'locationStreams';

/** Bounded batch per collection per worker invocation (matches ride sweeper scale). */
export const DEFAULT_EXPIRES_AT_CLEANUP_BATCH = 100;
export const MAX_EXPIRES_AT_CLEANUP_BATCH = 200;

export interface CollectionCleanupResult {
  collection: string;
  scanned: number;
  deleted: number;
  skipped: number;
  failed: number;
}

export interface ExpiresAtCleanupSummary {
  idempotencyRecords: CollectionCleanupResult;
  pricingSnapshots: CollectionCleanupResult;
  locationStreams: CollectionCleanupResult;
}

function parseExpiresAtMs(raw: unknown): number | null {
  if (typeof raw !== 'string' || raw.trim() === '') return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Defense-in-depth: only delete when expiresAt is strictly in the past vs server now.
 * Active location streams refresh expiresAt on each accepted update (sliding window).
 */
export function isRetentionExpired(
  expiresAt: unknown,
  nowMs: number,
): boolean {
  const expiresMs = parseExpiresAtMs(expiresAt);
  if (expiresMs == null) return false;
  return expiresMs <= nowMs;
}

export class ExpiresAtCleanupService {
  constructor(private readonly db: Firestore) {}

  async runCleanup(input?: {
    limit?: number;
    nowMs?: number;
  }): Promise<ExpiresAtCleanupSummary> {
    const limit = Math.min(
      Math.max(input?.limit ?? DEFAULT_EXPIRES_AT_CLEANUP_BATCH, 1),
      MAX_EXPIRES_AT_CLEANUP_BATCH,
    );
    const nowMs = input?.nowMs ?? Date.now();
    const nowIso = new Date(nowMs).toISOString();

    return {
      idempotencyRecords: await this.cleanupCollection(
        IDEMPOTENCY_RECORDS_COLLECTION,
        limit,
        nowIso,
        nowMs,
      ),
      pricingSnapshots: await this.cleanupCollection(
        PRICING_SNAPSHOTS_COLLECTION,
        limit,
        nowIso,
        nowMs,
      ),
      locationStreams: await this.cleanupCollection(
        LOCATION_STREAMS_COLLECTION,
        limit,
        nowIso,
        nowMs,
      ),
    };
  }

  private async cleanupCollection(
    collectionName: string,
    limit: number,
    nowIso: string,
    nowMs: number,
  ): Promise<CollectionCleanupResult> {
    const result: CollectionCleanupResult = {
      collection: collectionName,
      scanned: 0,
      deleted: 0,
      skipped: 0,
      failed: 0,
    };

    const snap = await this.db
      .collection(collectionName)
      .where('expiresAt', '<=', nowIso)
      .orderBy('expiresAt')
      .limit(limit)
      .get();

    result.scanned = snap.docs.length;

    for (const doc of snap.docs) {
      const data = doc.data();
      if (!isRetentionExpired(data.expiresAt, nowMs)) {
        result.skipped += 1;
        continue;
      }
      try {
        await doc.ref.delete();
        result.deleted += 1;
      } catch {
        result.failed += 1;
      }
    }

    return result;
  }
}
