import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { DriverAvailabilityService } from './driver_availability_service';
import { sendDriverData, sendDriverDomainError } from './http';
import { DriverDomainError } from './types';

export function createDriversRouter(
  db: Firestore,
  geoProjection?: import('../redis/geo_projection').RedisGeoProjectionService | null,
): Router {
  const router = Router();
  const availability = new DriverAvailabilityService(db, geoProjection ?? null);

  router.post('/go-online', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await availability.goOnline({ caller: req.caller });
      logSafe('DRIVER_GO_ONLINE', {
        operation: 'DRIVER_GO_ONLINE',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        availabilityState: result.body.data.availabilityState,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.body.data);
    } catch (err) {
      logSafe('DRIVER_GO_ONLINE', {
        operation: 'DRIVER_GO_ONLINE',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof DriverDomainError ? err.code : 'INTERNAL',
      });
      sendDriverDomainError(req, res, err);
    }
  });

  router.post('/go-offline', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const requestId = getRequestId(req);
      const result = await availability.goOffline({
        caller: req.caller,
        requestId,
      });
      logSafe('DRIVER_GO_OFFLINE', {
        operation: 'DRIVER_GO_OFFLINE',
        requestId,
        actorId: req.caller.uid,
        availabilityState: result.body.data.availabilityState,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.body.data);
    } catch (err) {
      logSafe('DRIVER_GO_OFFLINE', {
        operation: 'DRIVER_GO_OFFLINE',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof DriverDomainError ? err.code : 'INTERNAL',
      });
      sendDriverDomainError(req, res, err);
    }
  });

  return router;
}
