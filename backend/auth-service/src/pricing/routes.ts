import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import type { RoutingProvider } from '../routing/types';
import { PricingError } from './types';
import { PricingEstimateService } from './estimate_service';

function sendPricingData(
  req: AuthedRequest,
  res: import('express').Response,
  httpStatus: number,
  data: unknown,
): void {
  res.status(httpStatus).json({
    data,
    requestId: getRequestId(req),
    timestamp: new Date().toISOString(),
  });
}

function sendPricingError(
  req: AuthedRequest,
  res: import('express').Response,
  err: unknown,
): void {
  if (err instanceof PricingError) {
    sendApiError(req, res, err.httpStatus, err.code, err.message);
    return;
  }
  sendApiError(req, res, 500, 'INTERNAL', 'Unexpected server error.');
}

export function createPricingRouter(
  db: Firestore,
  routing: RoutingProvider,
): Router {
  const router = Router();
  const estimates = new PricingEstimateService(db, routing);

  router.post('/estimate', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    logSafe('pricing_estimate_begin', {
      requestId: getRequestId(req),
      uid: req.caller.uid,
    });
    try {
      const data = await estimates.estimate({ body: req.body });
      logSafe('pricing_estimate_ok', {
        requestId: getRequestId(req),
        category:
          typeof data === 'object' &&
          data !== null &&
          'category' in data &&
          typeof (data as { category?: unknown }).category === 'string'
            ? (data as { category: string }).category
            : undefined,
      });
      sendPricingData(req, res, 200, data);
    } catch (err) {
      logSafe('pricing_estimate_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof PricingError ? err.code : undefined,
      });
      sendPricingError(req, res, err);
    }
  });

  return router;
}
