import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import { getRequestId } from '../http/request_id';
import { logSafe, sendApiError } from '../http/errors';
import { RideService } from '../rides/ride_service';
import { sendRideData, sendRideDomainError } from '../rides/http';
import { RideDomainError } from '../rides/types';

export function createInternalRouter(db: Firestore): Router {
  const router = Router();
  const rides = new RideService(db);

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
