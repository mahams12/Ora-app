import express from 'express';
import type { Auth } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';
import { createAuthMiddleware } from './middleware/auth';
import { createRateLimiter } from './middleware/rate_limit';
import { createRateLimitMiddleware } from './middleware/rate_limit_middleware';
import { createAuthRouter } from './routes/auth';
import { createInternalRouter } from './routes/internal';
import { createRidesRouter } from './rides/routes';
import { createDriversRouter } from './drivers/routes';
import { createLocationRouter } from './location/routes';
import { createInternalWorkerMiddleware } from './middleware/internal_worker';
import { sendApiError } from './http/errors';
import { createRequestIdMiddleware } from './http/request_id';
import type { RedisGeoProjectionService } from './redis/geo_projection';
import type { RedisGeoClient } from './redis/types';
import type { FcmSender } from './delivery/fcm_sender';
import type { RoutingProvider } from './routing/types';
import { createPricingRouter } from './pricing/routes';
import type { TripLocationRtdb } from './rtdb/types';

export interface CreateAppOptions {
  auth: Auth;
  db: Firestore;
  requireAppCheck: boolean;
  verifyAppCheck?: (token: string) => Promise<void>;
  /**
   * Optional override for tests. Defaults: 60 requests / 60s per verified uid+ip.
   */
  rateLimit?: {
    windowMs: number;
    max: number;
  };
  /** Exposed for tests. */
  rateLimiter?: ReturnType<typeof createRateLimiter>;
  /**
   * Phase 5B estimate-specific limiter. Defaults: 10 req / 60s per uid+ip.
   * In-memory only (same local caveat as the global auth limiter).
   */
  pricingEstimateRateLimit?: {
    windowMs: number;
    max: number;
  };
  pricingEstimateRateLimiter?: ReturnType<typeof createRateLimiter>;
  /** Phase 2J internal worker token override (tests). */
  internalWorkerToken?: string;
  /** N2C Redis GEO projection (optional; null = skip projection). */
  geoProjection?: RedisGeoProjectionService | null;
  /** L2 Step 2/3 — RTDB trip location projection (optional; Null when unset). */
  tripLocationRtdb?: TripLocationRtdb | null;
  /** N3 nearby GEORADIUS client (optional; null = DEPENDENCY_ERROR). */
  redis?: RedisGeoClient | null;
  /** D1 FCM sender (optional; null = null sender / no real FCM). */
  fcmSender?: FcmSender | null;
  /**
   * Phase 4B/5B Google Routes (or test double).
   * When omitted, POST /v1/pricing/estimate returns 503 PRICING_UNAVAILABLE.
   */
  routingProvider?: RoutingProvider | null;
}

export function createApp(options: CreateAppOptions) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(createRequestIdMiddleware());
  app.use(express.json({ limit: '32kb' }));

  app.get('/healthz', (_req, res) => {
    res.status(200).json({ ok: true, service: 'ora-auth-service' });
  });

  const requireAuth = createAuthMiddleware(options.auth, {
    requireAppCheck: options.requireAppCheck,
    verifyAppCheck: options.verifyAppCheck,
  });

  const limiter =
    options.rateLimiter ??
    createRateLimiter({
      windowMs: options.rateLimit?.windowMs ?? 60_000,
      max: options.rateLimit?.max ?? 60,
      keyFn: (req) => {
        const uid = req.caller?.uid ?? 'anonymous';
        const ip = req.ip ?? 'unknown';
        return `auth:${uid}:${ip}`;
      },
    });

  const rateLimit = createRateLimitMiddleware(limiter);
  const geo = options.geoProjection ?? null;
  const tripLocationRtdb = options.tripLocationRtdb ?? null;

  app.use('/v1/auth', requireAuth, rateLimit, createAuthRouter(options.db));

  // Phase 2E: ride core vertical slice — modular monolith on auth-service.
  app.use(
    '/v1/rides',
    requireAuth,
    rateLimit,
    createRidesRouter(options.db, tripLocationRtdb),
  );

  // N1 + N2C offline GEO cleanup.
  app.use(
    '/v1/drivers',
    requireAuth,
    rateLimit,
    createDriversRouter(options.db, geo),
  );

  // N2A location cursor + L2 Step 3 RTDB projection + N2C Redis GEO.
  app.use(
    '/v1/location',
    requireAuth,
    rateLimit,
    createLocationRouter(options.db, geo, tripLocationRtdb),
  );

  // Phase 4B/5B — pricing estimate (stricter per-uid limit than global auth).
  const estimateLimiter =
    options.pricingEstimateRateLimiter ??
    createRateLimiter({
      windowMs: options.pricingEstimateRateLimit?.windowMs ?? 60_000,
      max: options.pricingEstimateRateLimit?.max ?? 10,
      keyFn: (req) => {
        const uid = req.caller?.uid ?? 'anonymous';
        const ip = req.ip ?? 'unknown';
        return `pricing-estimate:${uid}:${ip}`;
      },
    });
  const estimateRateLimit = createRateLimitMiddleware(estimateLimiter);
  const routing = options.routingProvider;
  if (routing) {
    app.use(
      '/v1/pricing',
      requireAuth,
      estimateRateLimit,
      createPricingRouter(options.db, routing),
    );
  } else {
    app.use('/v1/pricing', requireAuth, estimateRateLimit, (req, res) => {
      sendApiError(
        req,
        res,
        503,
        'PRICING_UNAVAILABLE',
        'Pricing isn\'t available right now.',
      );
    });
  }

  const workerToken =
    options.internalWorkerToken ?? process.env.ORA_INTERNAL_WORKER_TOKEN;
  app.use(
    '/v1/internal',
    createInternalWorkerMiddleware(workerToken),
    createInternalRouter(
      options.db,
      options.redis ?? null,
      options.fcmSender ?? null,
      tripLocationRtdb,
    ),
  );

  app.use((req, res) => {
    sendApiError(req, res, 404, 'NOT_FOUND', 'Route not found.');
  });

  (app as express.Express & { __rateLimiter?: typeof limiter }).__rateLimiter =
    limiter;

  return app;
}
