import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { sendDriverData, sendDriverDomainError } from '../drivers/http';
import { DriverDomainError } from '../drivers/types';
import { DeviceTokenService } from '../delivery/device_token_service';

/**
 * NOTIF-RS-PUSH — passenger FCM device-token registration.
 * Role-gated to `role === 'passenger'` inside the service; the uid always comes
 * from the verified caller token, never from the request body.
 * Driver tokens stay on POST /v1/drivers/device-tokens (approved-driver gate).
 */
export function createDeviceTokensRouter(db: Firestore): Router {
  const router = Router();
  const deviceTokens = new DeviceTokenService(db);

  router.post('/', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await deviceTokens.registerPassenger({
        caller: req.caller,
        body: req.body,
      });
      logSafe('RS_DEVICE_TOKEN_REGISTER', {
        operation: 'RS_DEVICE_TOKEN_REGISTER',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.data);
    } catch (err) {
      logSafe('RS_DEVICE_TOKEN_REGISTER', {
        operation: 'RS_DEVICE_TOKEN_REGISTER',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof DriverDomainError ? err.code : 'INTERNAL',
      });
      sendDriverDomainError(req, res, err);
    }
  });

  router.delete('/', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await deviceTokens.clearPassenger({
        caller: req.caller,
        body: req.body,
      });
      logSafe('RS_DEVICE_TOKEN_CLEAR', {
        operation: 'RS_DEVICE_TOKEN_CLEAR',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        cleared: result.data.cleared,
        durationMs: Date.now() - started,
      });
      sendDriverData(req, res, result.httpStatus, result.data);
    } catch (err) {
      logSafe('RS_DEVICE_TOKEN_CLEAR', {
        operation: 'RS_DEVICE_TOKEN_CLEAR',
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
