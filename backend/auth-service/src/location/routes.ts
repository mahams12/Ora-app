import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { LocationUpdateService } from './location_update_service';
import { sendLocationData, sendLocationDomainError } from './http';
import { LocationDomainError } from './types';

export function createLocationRouter(
  db: Firestore,
  geoProjection?: import('../redis/geo_projection').RedisGeoProjectionService | null,
): Router {
  const router = Router();
  const locations = new LocationUpdateService(db, geoProjection ?? null);

  router.post('/update', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    const requestId = getRequestId(req);
    try {
      const result = await locations.update({
        caller: req.caller,
        body: req.body,
        requestId,
      });
      logSafe('LOCATION_UPDATE', {
        operation: 'LOCATION_UPDATE',
        requestId,
        actorId: req.caller.uid,
        mode: result.body.data.mode,
        locationSeq: result.body.data.locationSeq,
        durationMs: Date.now() - started,
      });
      sendLocationData(req, res, result.httpStatus, result.body.data);
    } catch (err) {
      logSafe('LOCATION_UPDATE', {
        operation: 'LOCATION_UPDATE',
        requestId,
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof LocationDomainError ? err.code : 'INTERNAL',
      });
      sendLocationDomainError(req, res, err);
    }
  });

  return router;
}
