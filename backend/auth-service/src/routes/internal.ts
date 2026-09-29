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
} from '../drivers/nearby_service';
import { DispatchWaveService } from '../rides/dispatch_wave_service';
import { DispatchFcmProjector } from '../delivery/dispatch_fcm_projector';
import type { FcmSender } from '../delivery/fcm_sender';
import { createNullFcmSender } from '../delivery/fcm_sender';
import type { RedisGeoClient } from '../redis/types';

export function createInternalRouter(
  db: Firestore,
  redis: RedisGeoClient | null = null,
  fcm: FcmSender | null = null,
): Router {
  const router = Router();
  const rides = new RideService(db);
  const nearby = new NearbyDriversService(db, redis);
  const dispatch = new DispatchWaveService(db, nearby);
  const fcmSender = fcm ?? createNullFcmSender();
  const dispatchFcm = new DispatchFcmProjector(db, fcmSender);

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

  /** N3 — nearby driver candidates (worker-only; Redis GEO + Firestore filters). */
  router.get('/drivers/nearby', async (req, res) => {
    const started = Date.now();
    const requestId = getRequestId(req);
    try {
      const result = await nearby.findNearby({
        query: req.query as Record<string, unknown>,
        requestId,
      });
      logSafe('N3_NEARBY', {
        operation: 'N3_NEARBY',
        requestId,
        city: result.city ?? null,
        radiusKm: result.radiusKm,
        resultCount: result.candidates.length,
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

  return router;
}
