import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getRequestId } from '../http/request_id';
import { sendApiError, logSafe } from '../http/errors';
import { RideService } from './ride_service';
import { InviteService } from './invite_service';
import { DispatchWaveService } from './dispatch_wave_service';
import { NearbyDriversService } from '../drivers/nearby_service';
import { DispatchFcmProjector } from '../delivery/dispatch_fcm_projector';
import { createNullFcmSender } from '../delivery/fcm_sender';
import type { FcmSender } from '../delivery/fcm_sender';
import type { GeoStoreClient } from '../geo/types';
import type { DispatchTaskScheduler } from '../tasks/dispatch_tasks';
import { sendRideData, sendRideDomainError } from './http';
import { RideDomainError } from './types';
import type { TripLocationRtdb } from '../rtdb/types';
import type { LocationStreamStore } from '../location/stream_store';

export interface RidesDispatchDeps {
  geoStore?: GeoStoreClient | null;
  fcmSender?: FcmSender | null;
  adaptiveFreshness?: boolean;
  scheduler?: DispatchTaskScheduler;
}

export function createRidesRouter(
  db: Firestore,
  tripLocationRtdb: TripLocationRtdb | null = null,
  streamStore: LocationStreamStore | null = null,
  dispatchDeps?: RidesDispatchDeps,
): Router {
  const router = Router();
  const rides = new RideService(db, tripLocationRtdb, streamStore);

  // Event-driven dispatch (Phase: inDrive-style matching). When wired, wave 1
  // fires inline on booking, FCM projects right after each wave commit, and a
  // fully-responded wave pulls the next wave forward — the Cloud Tasks wake-
  // ups and the low-frequency sweep stay as recovery, not the mechanism.
  let kickDispatch: ((rideId: string, correlationId: string) => Promise<void>) | null =
    null;
  const dispatchTaskSchedulerRef = dispatchDeps?.scheduler ?? null;
  let dispatch: DispatchWaveService | null = null;
  let dispatchFcm: DispatchFcmProjector | null = null;
  if (dispatchDeps) {
    const nearby = new NearbyDriversService(
      db,
      dispatchDeps.geoStore ?? null,
      dispatchDeps.adaptiveFreshness === true,
    );
    dispatch = new DispatchWaveService(
      db,
      nearby,
      dispatchDeps.scheduler,
    );
    dispatchFcm = new DispatchFcmProjector(
      db,
      dispatchDeps.fcmSender ?? createNullFcmSender(),
    );
    kickDispatch = async (rideId: string, correlationId: string) => {
      await dispatch!.tickRide({ rideId, correlationId });
      await dispatchFcm!.sweep({ correlationId });
    };
  }
  const invites = new InviteService(
    db,
    rides,
    dispatch
      ? {
          onWaveResponded: async (rideId, correlationId) => {
            const accel = await dispatch!.accelerateIfWaveResolved({
              rideId,
              correlationId,
            });
            if (accel.accelerated) {
              await dispatchFcm!.sweep({ correlationId });
            }
          },
        }
      : undefined,
  );

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

      // Durable dispatch wake-ups armed BEFORE the response: if this instance
      // is killed or CPU-throttled afterwards, Cloud Tasks still guarantees
      // wave-1 dispatch (+~1s) and ride expiry at the server deadline. Both
      // land on idempotent ticks — a successful inline kick just makes them
      // no-ops. Arming failure is logged, never fails the booking.
      const dataRecord = data as
        | { rideId?: string; expiresAt?: string }
        | undefined;
      const rideId =
        result.httpStatus === 201 ? dataRecord?.rideId : undefined;
      if (kickDispatch && rideId) {
        try {
          await dispatchTaskSchedulerRef?.scheduleDispatchTick({
            rideId,
            waveNumber: 1,
            runAtMs: Date.now() + 1000,
            correlationId: getRequestId(req),
          });
        } catch (err) {
          logSafe('RIDE_CREATE_KICK_TASK_FAILED', {
            operation: 'RIDE_CREATE_KICK_TASK_FAILED',
            requestId: getRequestId(req),
            rideId,
            error: err instanceof Error ? err.message : String(err),
          });
        }
        const expiresAtMs = Date.parse(dataRecord?.expiresAt ?? '');
        if (Number.isFinite(expiresAtMs)) {
          try {
            await dispatchTaskSchedulerRef?.scheduleRideExpire({
              rideId,
              runAtMs: expiresAtMs,
              correlationId: getRequestId(req),
            });
          } catch (err) {
            logSafe('RIDE_CREATE_EXPIRE_TASK_FAILED', {
              operation: 'RIDE_CREATE_EXPIRE_TASK_FAILED',
              requestId: getRequestId(req),
              rideId,
              error: err instanceof Error ? err.message : String(err),
            });
          }
        }
      }
      sendRideData(req, res, result.httpStatus, data);

      // Fast path: inline wave-1 tick + FCM projection so drivers are invited
      // in-request rather than waiting for the armed task. Fully guarded —
      // booking succeeded before this point regardless of outcome.
      if (kickDispatch && rideId) {
        try {
          await kickDispatch(rideId, getRequestId(req));
        } catch (err) {
          logSafe('RIDE_CREATE_DISPATCH_KICK_FAILED', {
            operation: 'RIDE_CREATE_DISPATCH_KICK_FAILED',
            requestId: getRequestId(req),
            rideId,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }
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

  // Driver invitations — registered before GET /:rideId so "invited" is not
  // captured as a rideId.
  router.get('/invited', async (req: AuthedRequest, res) => {
    if (!req.caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const started = Date.now();
    try {
      const result = await invites.listInvited({ caller: req.caller });
      logSafe('RIDE_INVITED_LIST', {
        operation: 'RIDE_INVITED_LIST',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
      });
      sendRideData(req, res, result.httpStatus, (result.body as { data: unknown }).data);
    } catch (err) {
      logSafe('RIDE_INVITED_LIST', {
        operation: 'RIDE_INVITED_LIST',
        requestId: getRequestId(req),
        actorId: req.caller.uid,
        durationMs: Date.now() - started,
        errorCode: err instanceof RideDomainError ? err.code : 'INTERNAL',
      });
      sendRideDomainError(req, res, err);
    }
  });

  router.post(
    '/:rideId/invites/:waveId/accept',
    async (req: AuthedRequest, res) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      try {
        const result = await invites.acceptInvite({
          caller: req.caller,
          rideId: req.params.rideId,
          waveId: req.params.waveId,
          correlationId: getRequestId(req),
        });
        sendRideData(
          req,
          res,
          result.httpStatus,
          (result.body as { data: unknown }).data,
        );
      } catch (err) {
        logSafe('invite_accept_failed', {
          requestId: getRequestId(req),
          errorType: err instanceof Error ? err.name : 'unknown',
          code: err instanceof RideDomainError ? err.code : undefined,
        });
        sendRideDomainError(req, res, err);
      }
    },
  );

  router.post(
    '/:rideId/invites/:waveId/decline',
    async (req: AuthedRequest, res) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      try {
        const result = await invites.declineInvite({
          caller: req.caller,
          rideId: req.params.rideId,
          waveId: req.params.waveId,
          correlationId: getRequestId(req),
        });
        sendRideData(
          req,
          res,
          result.httpStatus,
          (result.body as { data: unknown }).data,
        );
      } catch (err) {
        logSafe('invite_decline_failed', {
          requestId: getRequestId(req),
          errorType: err instanceof Error ? err.name : 'unknown',
          code: err instanceof RideDomainError ? err.code : undefined,
        });
        sendRideDomainError(req, res, err);
      }
    },
  );

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

  // ── Ora Courier — delivery exceptions + return-to-sender ─────────────
  const courierProgression = (
    method: (input: {
      caller: NonNullable<AuthedRequest['caller']>;
      rideId: string;
      body: unknown;
      idempotencyKeyHeader: string | undefined;
      correlationId: string;
    }) => Promise<{ httpStatus: number; body: unknown }>,
    logName: string,
  ) =>
    async (req: AuthedRequest, res: Parameters<typeof sendApiError>[1]) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      try {
        const result = await method({
          caller: req.caller,
          rideId: req.params.rideId,
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
        logSafe(logName, {
          requestId: getRequestId(req),
          errorType: err instanceof Error ? err.name : 'unknown',
          code: err instanceof RideDomainError ? err.code : undefined,
        });
        sendRideDomainError(req, res, err);
      }
    };

  router.post(
    '/:rideId/delivery-failed',
    courierProgression(
      (input) => rides.failDelivery(input),
      'delivery_fail_failed',
    ),
  );
  router.post(
    '/:rideId/retry-delivery',
    courierProgression(
      (input) => rides.retryDelivery(input),
      'delivery_retry_failed',
    ),
  );
  router.post(
    '/:rideId/return-start',
    courierProgression(
      (input) => rides.startReturn(input),
      'return_start_failed',
    ),
  );
  router.post(
    '/:rideId/return-complete',
    courierProgression(
      (input) => rides.completeReturn(input),
      'return_complete_failed',
    ),
  );

  // ── Ora Courier v2 — code-free multi-stop progression ────────────────
  const stopAction = (
    method: (input: {
      caller: NonNullable<AuthedRequest['caller']>;
      rideId: string;
      seq: number;
      body: unknown;
      idempotencyKeyHeader: string | undefined;
      correlationId: string;
    }) => Promise<{ httpStatus: number; body: unknown }>,
    logName: string,
  ) =>
    async (req: AuthedRequest, res: Parameters<typeof sendApiError>[1]) => {
      if (!req.caller) {
        sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
        return;
      }
      const seq = Number(req.params.seq);
      if (!Number.isInteger(seq) || seq < 0) {
        sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Invalid stop seq.');
        return;
      }
      try {
        const result = await method({
          caller: req.caller,
          rideId: req.params.rideId,
          seq,
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
        logSafe(logName, {
          requestId: getRequestId(req),
          errorType: err instanceof Error ? err.name : 'unknown',
          code: err instanceof RideDomainError ? err.code : undefined,
        });
        sendRideDomainError(req, res, err);
      }
    };

  router.post(
    '/:rideId/stops/:seq/arrive',
    stopAction((input) => rides.arriveAtStop(input), 'stop_arrive_failed'),
  );
  router.post(
    '/:rideId/stops/:seq/confirm',
    stopAction((input) => rides.confirmStop(input), 'stop_confirm_failed'),
  );
  router.post(
    '/:rideId/stops/:seq/fail',
    stopAction((input) => rides.failStop(input), 'stop_fail_failed'),
  );
  router.post(
    '/:rideId/stops/:seq/quote',
    stopAction((input) => rides.submitStopQuote(input), 'stop_quote_failed'),
  );
  router.post(
    '/:rideId/stops/:seq/quote-response',
    stopAction(
      (input) => rides.respondToStopQuote(input),
      'stop_quote_respond_failed',
    ),
  );
  router.post(
    '/:rideId/settlement',
    courierProgression(
      (input) => rides.reportSettlement(input),
      'settlement_report_failed',
    ),
  );
  router.post(
    '/:rideId/acknowledge',
    courierProgression(
      (input) => rides.acknowledgeDelivery(input),
      'delivery_ack_failed',
    ),
  );
  router.post(
    '/:rideId/disputes',
    courierProgression(
      (input) => rides.createDispute(input),
      'dispute_open_failed',
    ),
  );

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
