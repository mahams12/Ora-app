import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { getRequestId } from '../http/request_id';
import { logSafe, sendApiError } from '../http/errors';
import { RideService } from '../rides/ride_service';
import { sendRideData, sendRideDomainError } from '../rides/http';
import { RideDomainError } from '../rides/types';
import {
  NearbyDomainError,
  NearbyDriversService,
  compactN3RejectionCounts,
  createEmptyN3RejectionCounts,
  type N3NearbyDiagnostics,
} from '../drivers/nearby_service';
import { DispatchWaveService } from '../rides/dispatch_wave_service';
import { DispatchFcmProjector } from '../delivery/dispatch_fcm_projector';
import { RideStateFcmProjector } from '../delivery/ride_state_fcm_projector';
import type { FcmSender } from '../delivery/fcm_sender';
import { createNullFcmSender } from '../delivery/fcm_sender';
import type { RedisGeoClient } from '../redis/types';
import { ExpiresAtCleanupService } from '../maintenance/expires_at_cleanup_service';

export function createInternalRouter(
  db: Firestore,
  redis: RedisGeoClient | null = null,
  fcm: FcmSender | null = null,
  tripLocationRtdb: import('../rtdb/types').TripLocationRtdb | null = null,
  streamStore: import('../location/stream_store').LocationStreamStore | null = null,
  options?: { adaptiveFreshness?: boolean },
): Router {
  const router = Router();
  const rides = new RideService(db, tripLocationRtdb, streamStore);
  const nearby = new NearbyDriversService(
    db,
    redis,
    options?.adaptiveFreshness === true,
  );
  const dispatch = new DispatchWaveService(db, nearby);
  const fcmSender = fcm ?? createNullFcmSender();
  const dispatchFcm = new DispatchFcmProjector(db, fcmSender);
  const rideStateFcm = new RideStateFcmProjector(db, fcmSender);
  const expiresAtCleanup = new ExpiresAtCleanupService(db, streamStore);

  router.post('/rides/expire-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await rides.sweepExpiredRides({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('RIDE_EXPIRE_SWEEP', {
        operation: 'RIDE_EXPIRE_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        expired: result.expired,
        alreadyExpired: result.alreadyExpired,
        skipped: result.skipped,
        failed: result.failed,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('RIDE_EXPIRE_SWEEP', {
        operation: 'RIDE_EXPIRE_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** Phase 2K — durable offer TTL sweeper (worker-only). */
  router.post('/rides/offer-expire-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await rides.sweepExpiredOffers({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('RIDE_OFFER_EXPIRE_SWEEP', {
        operation: 'RIDE_OFFER_EXPIRE_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        expired: result.expired,
        alreadyExpired: result.alreadyExpired,
        skipped: result.skipped,
        failed: result.failed,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('RIDE_OFFER_EXPIRE_SWEEP', {
        operation: 'RIDE_OFFER_EXPIRE_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** N4 — primary dispatch sweeper (worker-only). */
  router.post('/rides/dispatch-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await dispatch.sweepDispatch({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('N4_DISPATCH_SWEEP', {
        operation: 'N4_DISPATCH_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        completed: result.completed,
        alreadyCompleted: result.alreadyCompleted,
        notDue: result.notDue,
        skipped: result.skipped,
        stopped: result.stopped,
        exhausted: result.exhausted,
        failed: result.failed,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('N4_DISPATCH_SWEEP', {
        operation: 'N4_DISPATCH_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** RTDB GEO — storage-hygiene sweep of fully-expired presence nodes. */
  router.post('/geo/presence-sweep', async (req, res) => {
    const started = Date.now();
    try {
      const removed = (await redis?.sweepExpired?.()) ?? 0;
      logSafe('GEO_PRESENCE_SWEEP', {
        operation: 'GEO_PRESENCE_SWEEP',
        requestId: getRequestId(req),
        removed,
        supported: typeof redis?.sweepExpired === 'function',
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, { removed });
    } catch (err) {
      logSafe('GEO_PRESENCE_SWEEP', {
        operation: 'GEO_PRESENCE_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof Error ? err.name : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** N4 — per-ride dispatch tick (worker-only; ops/tests). */
  router.post('/rides/:rideId/dispatch-tick', async (req, res) => {
    const started = Date.now();
    const rideId = String(req.params.rideId ?? '');
    if (!rideId) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', 'rideId is required.');
      return;
    }

    try {
      const result = await dispatch.tickRide({
        rideId,
        correlationId: getRequestId(req),
      });
      logSafe('N4_DISPATCH_TICK', {
        operation: 'N4_DISPATCH_TICK',
        requestId: getRequestId(req),
        rideId: result.rideId,
        outcome: result.outcome,
        waveNumber: result.waveNumber,
        invitedCount: result.invitedCount,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('N4_DISPATCH_TICK', {
        operation: 'N4_DISPATCH_TICK',
        requestId: getRequestId(req),
        rideId,
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** D1 — minimal outbox→FCM projector for ride.dispatch.wave_completed. */
  router.post('/outbox/dispatch-fcm-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await dispatchFcm.sweep({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('D1_DISPATCH_FCM_SWEEP', {
        operation: 'D1_DISPATCH_FCM_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        processed: result.processed,
        delivered: result.delivered,
        retryable: result.retryable,
        deadLetter: result.deadLetter,
        skipped: result.skipped,
        failed: result.failed,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('D1_DISPATCH_FCM_SWEEP', {
        operation: 'D1_DISPATCH_FCM_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /**
   * NOTIF-RS-PUSH — outbox→FCM projector for ride-state nudges.
   * Emits identifiers-only RIDE_UPDATE pushes for the allowlisted lifecycle/
   * offer events; recipients resolved server-side from rides/rideOffers docs.
   */
  router.post('/outbox/ride-state-fcm-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await rideStateFcm.sweep({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('RS_RIDE_FCM_SWEEP', {
        operation: 'RS_RIDE_FCM_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        processed: result.processed,
        delivered: result.delivered,
        retryable: result.retryable,
        deadLetter: result.deadLetter,
        skipped: result.skipped,
        failed: result.failed,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('RS_RIDE_FCM_SWEEP', {
        operation: 'RS_RIDE_FCM_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /** N3 — nearby driver candidates (worker-only; geo index + Firestore filters). */
  router.get('/drivers/nearby', async (req, res) => {
    const started = Date.now();
    const requestId = getRequestId(req);
    try {
      let diagnostics: N3NearbyDiagnostics | undefined;
      const result = await nearby.findNearby({
        query: req.query as Record<string, unknown>,
        requestId,
        collectDiagnostics: (d) => {
          diagnostics = d;
        },
      });
      logSafe('N3_NEARBY', {
        operation: 'N3_NEARBY',
        requestId,
        city: result.city ?? null,
        radiusKm: result.radiusKm,
        resultCount: result.candidates.length,
        geoHits: diagnostics?.geoHits ?? 0,
        redisGetCount: diagnostics?.redisGetCount ?? 0,
        firestoreUsersReads: diagnostics?.firestoreUsersReads ?? 0,
        firestoreDriversReads: diagnostics?.firestoreDriversReads ?? 0,
        firestoreUsersBatchRpcs: diagnostics?.firestoreUsersBatchRpcs ?? 0,
        firestoreDriversBatchRpcs: diagnostics?.firestoreDriversBatchRpcs ?? 0,
        firestoreBusyRideQueries: diagnostics?.firestoreBusyRideQueries ?? 0,
        firestoreRpcTotal: diagnostics?.firestoreRpcTotal ?? 0,
        eligibleCount: diagnostics?.eligibleCount ?? result.candidates.length,
        rejected: compactN3RejectionCounts(
          diagnostics?.rejected ?? createEmptyN3RejectionCounts(),
        ),
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('N3_NEARBY', {
        operation: 'N3_NEARBY',
        requestId,
        durationMs: Date.now() - started,
        errorCode:
          err instanceof NearbyDomainError
            ? err.code
            : err instanceof RideDomainError
              ? err.code
              : 'INTERNAL',
      });
      if (err instanceof NearbyDomainError) {
        sendApiError(req, res, err.httpStatus, err.code, err.message);
        return;
      }
      sendRideDomainError(req, res, err);
    }
  });

  /** Phase 2M — durable DRIVER_ARRIVED wait NO_SHOW sweeper (worker-only). */
  router.post('/rides/no-show-sweep', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await rides.sweepNoShowRides({
        correlationId: getRequestId(req),
        limit,
      });
      logSafe('RIDE_NO_SHOW_SWEEP', {
        operation: 'RIDE_NO_SHOW_SWEEP',
        requestId: getRequestId(req),
        scanned: result.scanned,
        noShowed: result.noShowed,
        alreadyNoShow: result.alreadyNoShow,
        skipped: result.skipped,
        failed: result.failed,
        passes: result.passes,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('RIDE_NO_SHOW_SWEEP', {
        operation: 'RIDE_NO_SHOW_SWEEP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  /**
   * Cost-optimization Phase D — coalesced sweep entrypoint. One scheduled
   * invocation runs every per-minute sweep sequentially in a single request,
   * replacing 7 separate Cloud Run Job executions (~7,600/day → ~1,440/day).
   *
   * Guarantees preserved per sweep: each step keeps its own `limit` and
   * internal deadline semantics; failures are isolated (one failing sweep
   * cannot abort the others); all underlying sweeps are idempotent — a retry
   * or overlapping invocation only repeats bounded, state-checked work.
   *
   * Traffic-aware guard: dispatch-wave progression strictly requires
   * SEARCHING rides, so a single cheap probe (state==SEARCHING limit 1)
   * skips that sweep when no ride can advance. Time-driven sweeps (ride
   * expiry, offer expiry, no-show, FCM outbox, storage cleanup) always run —
   * their work exists independent of traffic and skipping them could break
   * deadlines.
   *
   * Response contract: 200 only when every executed sweep succeeded. Any
   * step failure yields 503 with the same per-sweep `results` + `failures`
   * payload — Cloud Scheduler retries are safe because every sweep is
   * idempotent, and failed executions surface in job metrics/alerting
   * instead of hiding behind HTTP 200. Monitoring contract: alert on
   * non-2xx / `SWEEPS_ALL` log entries with non-empty `failures`.
   */
  router.post('/sweeps/all', async (req, res) => {
    const started = Date.now();
    const requestId = getRequestId(req);

    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    const guards = String(req.query.guards ?? 'true') !== 'false';
    const cleanup = String(req.query.cleanup ?? 'true') !== 'false';
    const results: Record<string, unknown> = {};
    const failures: string[] = [];

    const run = async (
      name: string,
      fn: () => Promise<unknown>,
    ): Promise<void> => {
      const t0 = Date.now();
      try {
        results[name] = await fn();
        logSafe('SWEEPS_ALL_STEP', {
          requestId,
          step: name,
          outcome: 'ok',
          durationMs: Date.now() - t0,
        });
      } catch (err) {
        failures.push(name);
        results[name] = {
          error: err instanceof Error ? err.name : 'unknown',
        };
        logSafe('SWEEPS_ALL_STEP', {
          requestId,
          step: name,
          outcome: 'failed',
          errorType: err instanceof Error ? err.name : 'unknown',
          durationMs: Date.now() - t0,
        });
      }
    };

    // SEARCHING probe — mirrors the dispatch sweep's own first query. When
    // no ride is searching, dispatch cannot have work this tick.
    let searchingActive = true;
    if (guards) {
      try {
        const probe = await db
          .collection('rides')
          .where('state', '==', 'SEARCHING')
          .limit(1)
          .get();
        searchingActive = !probe.empty;
      } catch (err) {
        // Probe failure must not skip the sweep — fail open (run it).
        logSafe('SWEEPS_ALL_PROBE_FAILED', {
          requestId,
          errorType: err instanceof Error ? err.name : 'unknown',
        });
        searchingActive = true;
      }
    }

    if (searchingActive) {
      await run('dispatch', () =>
        dispatch.sweepDispatch({ correlationId: requestId, limit }),
      );
    } else {
      results.dispatch = { skipped: 'no_searching_rides' };
    }

    await run('expire', () =>
      rides.sweepExpiredRides({ correlationId: requestId, limit }),
    );
    await run('offerExpire', () =>
      rides.sweepExpiredOffers({ correlationId: requestId, limit }),
    );
    await run('noShow', () =>
      rides.sweepNoShowRides({ correlationId: requestId, limit }),
    );
    await run('dispatchFcm', () =>
      dispatchFcm.sweep({ correlationId: requestId, limit }),
    );
    await run('rideStateFcm', () =>
      rideStateFcm.sweep({ correlationId: requestId, limit }),
    );
    if (typeof redis?.sweepExpired === 'function') {
      await run('geoPresence', async () => ({
        removed: await redis.sweepExpired!(),
      }));
    }
    if (cleanup) {
      await run('expiresAtCleanup', () =>
        expiresAtCleanup.runCleanup({ limit }),
      );
    }

    logSafe('SWEEPS_ALL', {
      operation: 'SWEEPS_ALL',
      requestId,
      searchingActive,
      failures,
      durationMs: Date.now() - started,
    });
    // Never report success when a sweep failed — scheduler retries are
    // safe (all sweeps idempotent) and failed executions are observable.
    sendRideData(req, res, failures.length > 0 ? 503 : 200, {
      searchingActive,
      results,
      failures,
    });
  });

  /** Phase 2 storage — worker-only TTL cleanup (idempotency, pricing snapshots, location stream cursors). */
  router.post('/storage/expires-at-cleanup', async (req, res) => {
    const started = Date.now();
    const limitRaw = req.query.limit;
    let limit: number | undefined;
    if (limitRaw != null) {
      const parsed = Number(String(limitRaw));
      if (!Number.isInteger(parsed) || parsed < 1) {
        sendApiError(
          req,
          res,
          400,
          'VALIDATION_ERROR',
          'limit must be a positive integer.',
        );
        return;
      }
      limit = parsed;
    }

    try {
      const result = await expiresAtCleanup.runCleanup({ limit });
      logSafe('EXPIRES_AT_CLEANUP', {
        operation: 'EXPIRES_AT_CLEANUP',
        requestId: getRequestId(req),
        idempotencyDeleted: result.idempotencyRecords.deleted,
        pricingSnapshotsDeleted: result.pricingSnapshots.deleted,
        locationStreamsDeleted: result.locationStreams.deleted,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, 200, result);
    } catch (err) {
      logSafe('EXPIRES_AT_CLEANUP', {
        operation: 'EXPIRES_AT_CLEANUP',
        requestId: getRequestId(req),
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  return router;
}
