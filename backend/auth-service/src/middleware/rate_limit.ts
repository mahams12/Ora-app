/**
 * In-memory sliding-window rate limiter for auth API routes.
 *
 * LOCAL ONLY — NOT PRODUCTION READY for multi-instance Cloud Run.
 * Future production mechanism (do not implement in Phase 2B):
 * Redis / Memorystore token-bucket or Cloud Armor edge limits keyed by
 * verified Firebase uid (+ IP where appropriate).
 *
 * Keys MUST be derived from verified Firebase identity (and optionally IP),
 * never from a client-supplied uid body/query field.
 *
 * Extension point for future ride/payment limits: create additional middleware
 * instances with different window/max and mount on those routers.
 */

export interface RateLimitOptions {
  /** Window length in milliseconds. */
  windowMs: number;
  /** Max requests per key per window. */
  max: number;
  /** Build bucket key from request (caller must already be authenticated). */
  keyFn: (req: { caller?: { uid: string }; ip?: string }) => string;
}

export interface RateLimitDecision {
  allowed: boolean;
  /** Seconds until the oldest request in the window expires (when denied). */
  retryAfterSeconds?: number;
}

interface Bucket {
  timestamps: number[];
}

export function createRateLimiter(options: RateLimitOptions) {
  const buckets = new Map<string, Bucket>();

  function prune(now: number, timestamps: number[]): number[] {
    const cutoff = now - options.windowMs;
    return timestamps.filter((t) => t > cutoff);
  }

  return {
    /**
     * Evaluate whether the request is allowed.
     */
    evaluate(req: { caller?: { uid: string }; ip?: string }): RateLimitDecision {
      const key = options.keyFn(req);
      const now = Date.now();
      const bucket = buckets.get(key) ?? { timestamps: [] };
      bucket.timestamps = prune(now, bucket.timestamps);
      if (bucket.timestamps.length >= options.max) {
        buckets.set(key, bucket);
        const oldest = bucket.timestamps[0] ?? now;
        const retryAfterMs = Math.max(1000, oldest + options.windowMs - now);
        return {
          allowed: false,
          retryAfterSeconds: Math.ceil(retryAfterMs / 1000),
        };
      }
      bucket.timestamps.push(now);
      buckets.set(key, bucket);
      return { allowed: true };
    },
    /**
     * Returns true if the request is allowed, false if rate-limited.
     * @deprecated Prefer evaluate() for Retry-After support.
     */
    check(req: { caller?: { uid: string }; ip?: string }): boolean {
      return this.evaluate(req).allowed;
    },
    /** Test helper: clear all buckets. */
    reset() {
      buckets.clear();
    },
    /** Test helper: current count for a key after prune. */
    count(req: { caller?: { uid: string }; ip?: string }): number {
      const key = options.keyFn(req);
      const now = Date.now();
      const bucket = buckets.get(key);
      if (!bucket) return 0;
      return prune(now, bucket.timestamps).length;
    },
  };
}

export type RateLimiter = ReturnType<typeof createRateLimiter>;
