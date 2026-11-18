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
import { createDeviceTokensRouter } from './routes/device_tokens';
import {
  createMarketplaceRouter,
  createVendorListingsRouter,
} from './marketplace/routes';
import {
  createInternalWalletRouter,
  createWalletRouter,
} from './wallet/routes';
import { createLocationRouter } from './location/routes';
import { DriverEligibilityCache } from './location/location_update_service';
import { DriverAvailabilityService } from './drivers/driver_availability_service';
import { createInternalWorkerMiddleware } from './middleware/internal_worker';
import { createDispatchTaskSchedulerFromEnv } from './tasks/dispatch_tasks';
import { sendApiError } from './http/errors';
import { createRequestIdMiddleware } from './http/request_id';
import type { GeoProjectionService } from './geo/geo_projection';
import type { GeoStoreClient } from './geo/types';
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
  /** N2C geo-store projection (optional; null = skip projection). */
  geoProjection?: GeoProjectionService | null;
  /** L2 Step 2/3 — RTDB trip location projection (optional; Null when unset). */
  tripLocationRtdb?: TripLocationRtdb | null;
  /** N3 nearby GEORADIUS client (optional; null = DEPENDENCY_ERROR). */
  geoStore?: GeoStoreClient | null;
  /** locationStreams cursor store (Firestore default / RTDB when configured). */
  streamStore?: import('./location/stream_store').LocationStreamStore | null;
  /** D1 FCM sender (optional; null = null sender / no real FCM). */
  fcmSender?: FcmSender | null;
  /**
   * Phase 4B/5B Google Routes (or test double).
   * When omitted, POST /v1/pricing/estimate returns 503 PRICING_UNAVAILABLE.
   */
  routingProvider?: RoutingProvider | null;
  /**
   * Shared driver eligibility cache (location updates + availability
   * invalidation). Injectable for tests that need controlled staleness —
   * e.g. `new DriverEligibilityCache(0)` disables caching.
   */
  eligibilityCache?: DriverEligibilityCache;
  /** Defaults to auto-approving driver applications until admin review exists. */
  driverAutoApprove?: boolean;
  /**
   * LOCATION_ADAPTIVE_FRESHNESS — N3 matching filters on the per-driver
   * freshUntilMs twin instead of a fixed 15s window (Phase A).
   */
  adaptiveFreshness?: boolean;
  /**
   * LOCATION_IDLE_MERGED_CURSOR — idle presence packets validate the stream
   * cursor inside the geoDrivers marker write (Phase B; one tx per packet).
   */
  idleMergedCursor?: boolean;
  /**
   * PRICING_RULES_CACHE_TTL_MS — in-process TTL for pricing rule docs
   * (0/undefined = uncached; rules are admin-seeded and rarely change).
   */
  pricingRulesCacheTtlMs?: number;
  /**
   * Event-driven dispatch (inDrive-style matching): Cloud Tasks deadline
   * scheduler. Defaults to env-built config; NoopScheduler keeps wave
   * progression on the sweep only.
   */
  dispatchTaskScheduler?: import('./tasks/dispatch_tasks').DispatchTaskScheduler;
  /**
   * Cloud Tasks OIDC authentication for /v1/internal — allowed invoker
   * service-account emails + expected audience (service base URL).
   * Injectable verifier for tests.
   */
  internalOidc?: import('./middleware/internal_worker').InternalOidcConfig;
}

export function createApp(options: CreateAppOptions) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
  app.use(createRequestIdMiddleware());
  // Marketplace listing bodies carry base64 photo data URLs (bounded to
  // ≤6 photos / ≤600KB total inside the service layer), so these mounts get
  // a larger parser ahead of the global 32KB one.
  app.use('/v1/vendor', express.json({ limit: '1mb' }));
  app.use('/v1/marketplace', express.json({ limit: '256kb' }));
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
  // Shared across routers: availability transitions invalidate the location
  // eligibility cache immediately (bounded-TTL fallback otherwise).
  const eligibilityCache =
    options.eligibilityCache ?? new DriverEligibilityCache();

  // Shared availability service: /v1/auth/mode uses it to durably take a
  // driver offline when switching to passenger mode (ghost-driver guard).
  const availability = new DriverAvailabilityService(
    options.db,
    geo,
    (driverId) => eligibilityCache.invalidate(driverId),
  );

  app.use(
    '/v1/auth',
    requireAuth,
    rateLimit,
    createAuthRouter(options.db, availability),
  );

  // Event-driven dispatch wiring — shared scheduler across the rides router
  // (inline wave-1 + task arming) and the internal router (tick/expire targets).
  const dispatchTaskScheduler =
    options.dispatchTaskScheduler ??
    createDispatchTaskSchedulerFromEnv().scheduler;

  // Phase 2E: ride core vertical slice — modular monolith on auth-service.
  app.use(
    '/v1/rides',
    requireAuth,
    rateLimit,
    createRidesRouter(
      options.db,
      tripLocationRtdb,
      options.streamStore ?? null,
      {
        geoStore: options.geoStore ?? null,
        fcmSender: options.fcmSender ?? null,
        adaptiveFreshness: options.adaptiveFreshness,
        scheduler: dispatchTaskScheduler,
      },
    ),
  );

  // N1 + N2C offline GEO cleanup.
  app.use(
    '/v1/drivers',
    requireAuth,
    rateLimit,
    createDriversRouter(
      options.db,
      geo,
      (driverId) => eligibilityCache.invalidate(driverId),
      availability,
      options.driverAutoApprove ?? false,
    ),
  );

  // NOTIF-RS-PUSH — passenger FCM device-token registration (role-gated).
  app.use(
    '/v1/device-tokens',
    requireAuth,
    rateLimit,
    createDeviceTokensRouter(options.db),
  );

  // Vendor marketplace: listing CRUD is per-role gated inside the service
  // layer (vendorApplications.{type} must be approved); customer discovery +
  // booking workflow live under /v1/marketplace.
  app.use(
    '/v1/vendor',
    requireAuth,
    rateLimit,
    createVendorListingsRouter(options.db),
  );
  app.use(
    '/v1/marketplace',
    requireAuth,
    rateLimit,
    createMarketplaceRouter(options.db),
  );

  // Shared partner wallet — one account per UID across driver/cargo/rental/
  // service roles. Reads + pending top-up requests only; balance changes are
  // settlement-side or via the internal resolver.
  app.use(
    '/v1/wallet',
    requireAuth,
    rateLimit,
    createWalletRouter(options.db),
  );

  // N2A location cursor + L2 Step 3 RTDB projection + N2C geo-store.
  app.use(
    '/v1/location',
    requireAuth,
    rateLimit,
    createLocationRouter(
      options.db,
      geo,
      tripLocationRtdb,
      eligibilityCache,
      options.streamStore ?? null,
      { idleMergedCursor: options.idleMergedCursor },
    ),
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
      createPricingRouter(options.db, routing, {
        rulesCacheTtlMs: options.pricingRulesCacheTtlMs,
      }),
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

  // Ora Courier v2 — client-visible delivery config (limits only; no secrets).
  app.get('/v1/delivery-config', requireAuth, async (req, res) => {
    const { loadDeliveryConfig } = await import(
      './delivery/delivery_config.js'
    );
    const cfg = await loadDeliveryConfig(options.db);
    res.json({
      data: {
        maxStops: cfg.maxStops,
        maxShoppingBudgetMinor: cfg.maxShoppingBudgetMinor,
        disputeWindowHours: cfg.disputeWindowHours,
        enableBuyDeliver: cfg.enableBuyDeliver,
        enableCourierV2: cfg.enableCourierV2,
        prohibitedList: cfg.prohibitedList,
      },
    });
  });

  const workerToken =
    options.internalWorkerToken ?? process.env.ORA_INTERNAL_WORKER_TOKEN;
  // Cloud Tasks OIDC: invoker SA allowlist + audience (service base URL).
  const oidcAllowedSa = (process.env.ORA_INTERNAL_OIDC_ALLOWED_SA ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const oidcAudience =
    process.env.ORA_INTERNAL_OIDC_AUDIENCE ??
    process.env.TASKS_TARGET_BASE_URL ??
    '';
  const internalOidc =
    options.internalOidc ??
    (oidcAllowedSa.length > 0 && oidcAudience
      ? {
          audience: oidcAudience,
          allowedEmails: new Set(oidcAllowedSa),
        }
      : undefined);
  app.use(
    '/v1/internal',
    createInternalWorkerMiddleware(workerToken, internalOidc),
    createInternalWalletRouter(options.db),
    createInternalRouter(
      options.db,
      options.geoStore ?? null,
      options.fcmSender ?? null,
      tripLocationRtdb,
      options.streamStore ?? null,
      {
        adaptiveFreshness: options.adaptiveFreshness,
        scheduler: dispatchTaskScheduler,
      },
    ),
  );

  app.use((req, res) => {
    sendApiError(req, res, 404, 'NOT_FOUND', 'Route not found.');
  });

  (app as express.Express & { __rateLimiter?: typeof limiter }).__rateLimiter =
    limiter;

  return app;
}
