/**
 * In-memory sliding-window rate limiter for auth API routes.
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
     * Returns true if the request is allowed, false if rate-limited.
     */
    check(req: { caller?: { uid: string }; ip?: string }): boolean {
      const key = options.keyFn(req);
      const now = Date.now();
      const bucket = buckets.get(key) ?? { timestamps: [] };
      bucket.timestamps = prune(now, bucket.timestamps);
      if (bucket.timestamps.length >= options.max) {
        buckets.set(key, bucket);
        return false;
      }
      bucket.timestamps.push(now);
      buckets.set(key, bucket);
      return true;
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
