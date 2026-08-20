import type { NextFunction, Response } from 'express';
import type { AuthedRequest } from './auth';
import type { RateLimiter } from './rate_limit';

/**
 * Express middleware: reject with 429 RATE_LIMITED when the limiter denies.
 * Must run AFTER auth middleware so `req.caller.uid` is the verified Firebase uid.
 */
export function createRateLimitMiddleware(limiter: RateLimiter) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.caller?.uid) {
      // Should not happen if mounted after auth; fail closed.
      res.status(401).json({
        error: {
          code: 'UNAUTHENTICATED',
          message: 'Authentication required.',
        },
      });
      return;
    }

    const allowed = limiter.check({
      caller: req.caller,
      ip: req.ip,
    });

    if (!allowed) {
      res.status(429).json({
        error: {
          code: 'RATE_LIMITED',
          message: 'Too many requests. Please try again later.',
        },
      });
      return;
    }

    next();
  };
}
