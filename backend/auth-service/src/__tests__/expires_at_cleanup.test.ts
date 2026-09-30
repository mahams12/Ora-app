import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import {
  ExpiresAtCleanupService,
  IDEMPOTENCY_RECORDS_COLLECTION,
  LOCATION_STREAMS_COLLECTION,
  isRetentionExpired,
} from '../maintenance/expires_at_cleanup_service';
import { PRICING_SNAPSHOTS_COLLECTION } from '../pricing/estimate_service';
import { IDEMPOTENCY_TTL_MS } from '../rides/types';

const WORKER_TOKEN = 'test-worker-token-ttl-cleanup';

function workerApp(db: ReturnType<typeof memoryDb>) {
  return createApp({
    auth: { verifyIdToken: async () => ({ uid: 'u1' }) } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
    internalWorkerToken: WORKER_TOKEN,
  });
}

describe('expiresAt retention helper', () => {
  it('returns false for missing or future expiresAt', () => {
    const now = Date.parse('2026-01-15T12:00:00.000Z');
    expect(isRetentionExpired(undefined, now)).toBe(false);
    expect(isRetentionExpired('2026-01-16T00:00:00.000Z', now)).toBe(false);
  });

  it('returns true only when expiresAt <= now', () => {
    const now = Date.parse('2026-01-15T12:00:00.000Z');
    expect(isRetentionExpired('2026-01-15T12:00:00.000Z', now)).toBe(true);
    expect(isRetentionExpired('2026-01-14T00:00:00.000Z', now)).toBe(true);
  });
});

describe('ExpiresAtCleanupService', () => {
  const nowMs = Date.parse('2026-06-01T12:00:00.000Z');
  const pastIso = '2026-05-01T00:00:00.000Z';
  const futureIso = '2026-07-01T00:00:00.000Z';

  it('deletes expired idempotencyRecords and keeps non-expired', async () => {
    const db = memoryDb();
    db.seed(IDEMPOTENCY_RECORDS_COLLECTION, 'expired-key', {
      idempotencyKey: 'expired-key',
      expiresAt: pastIso,
      status: 'SUCCEEDED',
      requestHash: 'h1',
      actorId: 'u1',
    });
    db.seed(IDEMPOTENCY_RECORDS_COLLECTION, 'live-key', {
      idempotencyKey: 'live-key',
      expiresAt: futureIso,
      status: 'SUCCEEDED',
      requestHash: 'h2',
      actorId: 'u1',
      responseSnapshot: { httpStatus: 200, body: { data: { ok: true } } },
    });

    const svc = new ExpiresAtCleanupService(db as never);
    const summary = await svc.runCleanup({ limit: 50, nowMs });

    expect(summary.idempotencyRecords.deleted).toBe(1);
    expect(db.getDoc(IDEMPOTENCY_RECORDS_COLLECTION, 'expired-key')).toBeUndefined();
    expect(db.getDoc(IDEMPOTENCY_RECORDS_COLLECTION, 'live-key')).toBeDefined();
  });

  it('deletes expired pricingSnapshots and keeps non-expired', async () => {
    const db = memoryDb();
    db.seed(PRICING_SNAPSHOTS_COLLECTION, 'ps_old', {
      snapshotId: 'ps_old',
      expiresAt: pastIso,
      recommendedFareMinor: 100,
    });
    db.seed(PRICING_SNAPSHOTS_COLLECTION, 'ps_live', {
      snapshotId: 'ps_live',
      expiresAt: futureIso,
      recommendedFareMinor: 200,
    });

    const svc = new ExpiresAtCleanupService(db as never);
    const summary = await svc.runCleanup({ limit: 50, nowMs });

    expect(summary.pricingSnapshots.deleted).toBe(1);
    expect(db.getDoc(PRICING_SNAPSHOTS_COLLECTION, 'ps_old')).toBeUndefined();
    expect(db.getDoc(PRICING_SNAPSHOTS_COLLECTION, 'ps_live')).toBeDefined();
  });

  it('deletes expired locationStreams and keeps active sliding-window cursors', async () => {
    const db = memoryDb();
    db.seed(LOCATION_STREAMS_COLLECTION, 'stale-driver', {
      driverId: 'd1',
      streamState: 'ACTIVE',
      expiresAt: pastIso,
      lastAcceptedSeq: 1,
    });
    db.seed(LOCATION_STREAMS_COLLECTION, 'live-driver', {
      driverId: 'd2',
      streamState: 'ACTIVE',
      expiresAt: futureIso,
      lastAcceptedSeq: 99,
      activeStreamId: 'stream-live',
    });

    const svc = new ExpiresAtCleanupService(db as never);
    const summary = await svc.runCleanup({ limit: 50, nowMs });

    expect(summary.locationStreams.deleted).toBe(1);
    expect(db.getDoc(LOCATION_STREAMS_COLLECTION, 'stale-driver')).toBeUndefined();
    expect(db.getDoc(LOCATION_STREAMS_COLLECTION, 'live-driver')).toBeDefined();
  });

  it('respects bounded limit per collection', async () => {
    const db = memoryDb();
    for (let i = 0; i < 5; i += 1) {
      db.seed(IDEMPOTENCY_RECORDS_COLLECTION, `k${i}`, {
        expiresAt: pastIso,
        status: 'SUCCEEDED',
      });
    }

    const svc = new ExpiresAtCleanupService(db as never);
    const summary = await svc.runCleanup({ limit: 2, nowMs });

    expect(summary.idempotencyRecords.scanned).toBe(2);
    expect(summary.idempotencyRecords.deleted).toBe(2);
    const remaining = [...db.store.keys()].filter((k) =>
      k.startsWith(`${IDEMPOTENCY_RECORDS_COLLECTION}/`),
    ).length;
    expect(remaining).toBe(3);
  });

  it('preserves idempotency replay record when not expired (7-day contract)', async () => {
    const db = memoryDb();
    const liveExpires = new Date(nowMs + IDEMPOTENCY_TTL_MS).toISOString();
    db.seed(IDEMPOTENCY_RECORDS_COLLECTION, 'replay-key', {
      idempotencyKey: 'replay-key',
      expiresAt: liveExpires,
      status: 'SUCCEEDED',
      requestHash: 'same-body',
      actorId: 'passenger-1',
      responseSnapshot: {
        httpStatus: 201,
        body: { data: { rideId: 'r1' } },
      },
    });

    const svc = new ExpiresAtCleanupService(db as never);
    await svc.runCleanup({ nowMs });

    const rec = db.getDoc(IDEMPOTENCY_RECORDS_COLLECTION, 'replay-key');
    expect(rec?.responseSnapshot).toEqual({
      httpStatus: 201,
      body: { data: { rideId: 'r1' } },
    });
  });
});

describe('POST /v1/internal/storage/expires-at-cleanup', () => {
  it('requires worker token', async () => {
    const db = memoryDb();
    const app = workerApp(db);
    expect(
      (await request(app).post('/v1/internal/storage/expires-at-cleanup'))
        .status,
    ).toBe(403);
  });

  it('returns cleanup summary for worker', async () => {
    const db = memoryDb();
    const pastIso = '2020-01-01T00:00:00.000Z';
    db.seed(PRICING_SNAPSHOTS_COLLECTION, 'ps_x', {
      snapshotId: 'ps_x',
      expiresAt: pastIso,
    });

    const res = await request(workerApp(db))
      .post('/v1/internal/storage/expires-at-cleanup')
      .set('X-Ora-Worker-Token', WORKER_TOKEN);

    expect(res.status).toBe(200);
    expect(res.body.data.pricingSnapshots.deleted).toBe(1);
  });
});
