import express from 'express';
import type { Auth } from 'firebase-admin/auth';
import type { Firestore } from 'firebase-admin/firestore';
import { createAuthMiddleware } from './middleware/auth';
import { createRateLimiter } from './middleware/rate_limit';
import { createRateLimitMiddleware } from './middleware/rate_limit_middleware';
import { createAuthRouter } from './routes/auth';

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
}

export function createApp(options: CreateAppOptions) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);
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
      // Verified Firebase uid + IP — never trust body/query uid.
      keyFn: (req) => {
        const uid = req.caller?.uid ?? 'anonymous';
        const ip = req.ip ?? 'unknown';
        return `auth:${uid}:${ip}`;
      },
    });

  const rateLimit = createRateLimitMiddleware(limiter);

  app.use('/v1/auth', requireAuth, rateLimit, createAuthRouter(options.db));

  app.use((_req, res) => {
    res.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Route not found.' },
    });
  });

  // Attach for tests without exporting internals via module.
  (app as express.Express & { __rateLimiter?: typeof limiter }).__rateLimiter =
    limiter;

  return app;
}
