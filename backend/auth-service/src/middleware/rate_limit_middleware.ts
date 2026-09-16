import type { NextFunction, Response } from 'express';
import type { AuthedRequest } from './auth';
import type { RateLimiter } from './rate_limit';
import { sendApiError } from '../http/errors';

/**
 * Express middleware: reject with 429 RATE_LIMITED when the limiter denies.
 * Must run AFTER auth middleware so `req.caller.uid` is the verified Firebase uid.
 */
export function createRateLimitMiddleware(limiter: RateLimiter) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.caller?.uid) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Authentication required.');
      return;
    }

    const decision = limiter.evaluate({
      caller: req.caller,
      ip: req.ip,
    });

    if (!decision.allowed) {
      const retryAfter = decision.retryAfterSeconds ?? 60;
      res.setHeader('Retry-After', String(retryAfter));
      sendApiError(
        req,
        res,
        429,
        'RATE_LIMITED',
        'Too many requests. Please try again later.',
      );
      return;
    }

    next();
  };
}
