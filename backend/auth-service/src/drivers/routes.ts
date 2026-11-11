import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { DriverAvailabilityService } from './driver_availability_service';
import { DriverOnboardingService } from './driver_onboarding_service';
import { sendDriverData, sendDriverDomainError } from './http';
import { DriverDomainError } from './types';
import { DeviceTokenService } from '../delivery/device_token_service';

export function createDriversRouter(
  db: Firestore,
  geoProjection?: import('../redis/geo_projection').RedisGeoProjectionService | null,
  onAvailabilityTransition?: (
    driverId: string,
    state: import('./types').AvailabilityState,
  ) => void,
  driverAutoApprove = true,
): Router {
  const router = Router();
  const availability = new DriverAvailabilityService(
    db,
    geoProjection ?? null,
    onAvailabilityTransition,
  );
  const onboarding = new DriverOnboardingService(db, driverAutoApprove);
  const deviceTokens = new DeviceTokenService(db);

  router.post('/onboarding', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await onboarding.submit({
        caller: req.caller,
        body: req.body,
      });
      logSafe('DRIVER_ONBOARDING_SUBMIT', {
        operation: 'DRIVER_ONBOARDING_SUBMIT',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        driverStatus: result.body.data.driverStatus,
        approved: result.body.data.approved,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.body.data);
    } catch (err) {
      logSafe('DRIVER_ONBOARDING_SUBMIT', {
        operation: 'DRIVER_ONBOARDING_SUBMIT',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof DriverDomainError ? err.code : 'INTERNAL',
      });
      sendDriverDomainError(req, res, err);
    }
  });

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

  router.get('/availability', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await availability.getStatus({ caller: req.caller });
      logSafe('DRIVER_AVAILABILITY_GET', {
        operation: 'DRIVER_AVAILABILITY_GET',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        availabilityState: result.body.data.availabilityState,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.body.data);
    } catch (err) {
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

  /** D1 — register FCM device token (approved driver; own uid only). */
  router.post('/device-tokens', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await deviceTokens.register({
        caller: req.caller,
        body: req.body,
      });
      logSafe('D1_DEVICE_TOKEN_REGISTER', {
        operation: 'D1_DEVICE_TOKEN_REGISTER',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.data);
    } catch (err) {
      logSafe('D1_DEVICE_TOKEN_REGISTER', {
        operation: 'D1_DEVICE_TOKEN_REGISTER',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof DriverDomainError ? err.code : 'INTERNAL',
      });
      sendDriverDomainError(req, res, err);
    }
  });

  /** D1 — clear FCM device token (approved driver; own uid only). */
  router.delete('/device-tokens', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await deviceTokens.clear({
        caller: req.caller,
        body: req.body,
      });
      logSafe('D1_DEVICE_TOKEN_CLEAR', {
        operation: 'D1_DEVICE_TOKEN_CLEAR',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        cleared: result.data.cleared,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.data);
    } catch (err) {
      logSafe('D1_DEVICE_TOKEN_CLEAR', {
        operation: 'D1_DEVICE_TOKEN_CLEAR',
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
