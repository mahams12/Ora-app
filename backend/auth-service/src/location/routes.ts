import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import {
  LogSampler,
  shouldEmitSteadyStateLog,
} from '../http/log_sampling';
import { LocationUpdateService } from './location_update_service';
import { sendLocationData, sendLocationDomainError } from './http';
import { LocationDomainError } from './types';

export function createLocationRouter(
  db: Firestore,
  geoProjection?: import('../geo/geo_projection').GeoProjectionService | null,
  tripLocationRtdb?: import('../rtdb/types').TripLocationRtdb | null,
  eligibilityCache?: import('./location_update_service').DriverEligibilityCache,
  streamStore?: import('./stream_store').LocationStreamStore | null,
  locationOptions?: {
    idleMergedCursor?: boolean;
    /** Steady-state log sampler; injectable for deterministic tests. */
    logSampler?: LogSampler;
  },
): Router {
  const router = Router();
  const logSampler = locationOptions?.logSampler ?? new LogSampler();
  const locations = new LocationUpdateService(
    db,
    geoProjection ?? null,
    tripLocationRtdb ?? null,
    {
      eligibilityCache,
      streamStore: streamStore ?? undefined,
      idleMergedCursor: locationOptions?.idleMergedCursor,
    },
  );

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
      const durationMs = Date.now() - started;
      // Steady-state success log is sampled; error path below always logs.
      if (shouldEmitSteadyStateLog(logSampler, 'LOCATION_UPDATE', durationMs)) {
        logSafe('LOCATION_UPDATE', {
          operation: 'LOCATION_UPDATE',
          requestId,
          actorId: req.caller.uid,
          mode: result.body.data.mode,
          locationSeq: result.body.data.locationSeq,
          durationMs,
        });
      }
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
