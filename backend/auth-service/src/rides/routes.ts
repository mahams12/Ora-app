import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { RideService } from './ride_service';
import { sendRideData, sendRideDomainError } from './http';
import { RideDomainError } from './types';

export function createRidesRouter(db: Firestore): Router {
  const router = Router();
  const rides = new RideService(db);

  router.post('/', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.createRide({
        caller: req.caller,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      // Envelope already includes data; attach requestId/timestamp via helper.
      const data = (result.body as { data: unknown }).data;
      sendRideData(req, res, result.httpStatus, data);
    } catch (err) {
      logSafe('ride_create_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  // Phase 2I — must register before GET /:rideId so list is not captured as rideId.
  router.get('/', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await rides.listRides({
        caller: req.caller,
        query: req.query as Record<string, unknown>,
      });
      logSafe('RIDE_LIST', {
        operation: 'RIDE_LIST',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        actorRole: result.meta.actorRole,
        statusFilter: result.meta.statusFilter,
        serviceType: result.meta.serviceType,
        limit: result.meta.limit,
        hasCursor: result.meta.hasCursor,
        resultCount: result.meta.resultCount,
        hasNextPage: result.meta.hasNextPage,
        durationMs: Date.now() - started,
      });
      sendRideData(
        req,
        res,
        result.httpStatus,
        (result.body as { data: unknown }).data,
      );
    } catch (err) {
      logSafe('RIDE_LIST', {
        operation: 'RIDE_LIST',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  // Slice M0 — must register before GET /:rideId so "open" is not captured as rideId.
  router.get('/open', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await rides.listOpenRides({
        caller: req.caller,
        query: req.query as Record<string, unknown>,
      });
      logSafe('RIDE_OPEN_DISCOVERY', {
        operation: 'RIDE_OPEN_DISCOVERY',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        limit: result.meta.limit,
        hasCursor: result.meta.hasCursor,
        resultCount: result.meta.resultCount,
        hasNextPage: result.meta.hasNextPage,
        durationMs: Date.now() - started,
      });
      sendRideData(
        req,
        res,
        result.httpStatus,
        (result.body as { data: unknown }).data,
      );
    } catch (err) {
      logSafe('RIDE_OPEN_DISCOVERY', {
        operation: 'RIDE_OPEN_DISCOVERY',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.get('/:rideId', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.getRide({
        caller: req.caller,
        rideId: req.params.rideId,
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      sendRideDomainError(req, res, err);
    }
  });

  router.get('/:rideId/offers', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const limit = req.query.limit ? Number(req.query.limit) : undefined;
      const result = await rides.listOffers({
        caller: req.caller,
        rideId: req.params.rideId,
        limit,
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/offers', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.createOffer({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_offer_create_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post(
    '/:rideId/offers/:offerId/select',
    async (req: AuthedRequest, res) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      try {
        const result = await rides.selectOffer({
          caller: req.caller,
          rideId: req.params.rideId,
          offerId: req.params.offerId,
          body: req.body,
          idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
          correlationId: getRequestId(req),
        });
        sendRideData(
          req,
          res,
          result.httpStatus,
          (result.body as { data: unknown }).data,
        );
      } catch (err) {
        logSafe('ride_select_failed', {
          requestId: getRequestId(req),
          errorType: err instanceof Error ? err.name : 'unknown',
          code: err instanceof RideDomainError ? err.code : undefined,
        });
        sendRideDomainError(req, res, err);
      }
    },
  );

  router.post(
    '/:rideId/offers/:offerId/withdraw',
    async (req: AuthedRequest, res) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      try {
        const result = await rides.withdrawOffer({
          caller: req.caller,
          rideId: req.params.rideId,
          offerId: req.params.offerId,
          idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
          correlationId: getRequestId(req),
        });
        sendRideData(
          req,
          res,
          result.httpStatus,
          (result.body as { data: unknown }).data,
        );
      } catch (err) {
        sendRideDomainError(req, res, err);
      }
    },
  );

  router.post('/:rideId/cancel', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.cancelRide({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/en-route', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.markEnRoute({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_en_route_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/arrive', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.markArrived({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_arrive_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/start', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.startRide({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_start_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/complete', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.completeRide({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_complete_failed', {
        requestId: getRequestId(req),
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post('/:rideId/close', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.closeRide({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_close_failed', {
        requestId: getRequestId(req),
        operation: 'RIDE_CLOSE',
        rideId: req.params.rideId,
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  // Phase 2N — ratings (more specific path; registered after /:rideId is fine).
  router.post('/:rideId/ratings', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.submitRating({
        caller: req.caller,
        rideId: req.params.rideId,
        body: req.body,
        idempotencyKeyHeader: req.header('Idempotency-Key') ?? undefined,
        correlationId: getRequestId(req),
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('ride_rating_submit_failed', {
        requestId: getRequestId(req),
        operation: 'RIDE_RATING_SUBMIT',
        rideId: req.params.rideId,
        errorType: err instanceof Error ? err.name : 'unknown',
        code: err instanceof RideDomainError ? err.code : undefined,
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.get('/:rideId/ratings', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    try {
      const result = await rides.getMyRating({
        caller: req.caller,
        rideId: req.params.rideId,
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      sendRideDomainError(req, res, err);
    }
  });

  return router;
}
