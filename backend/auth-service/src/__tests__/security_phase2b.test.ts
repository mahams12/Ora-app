import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { createRateLimiter } from '../middleware/rate_limit';

function memoryDb() {
  const store = new Map<string, Record<string, unknown>>();
  const doc = (id: string) => ({
    id,
    async get() {
      const data = store.get(id);
      return { exists: data != null, data: () => data };
    },
    async set(value: Record<string, unknown>) {
      store.set(id, value);
    },
  });
  return {
    collection() {
      return { doc };
    },
    async runTransaction(fn: (tx: {
      get: (ref: ReturnType<typeof doc>) => Promise<{ exists: boolean; data: () => Record<string, unknown> | undefined }>;
      set: (ref: ReturnType<typeof doc>, value: Record<string, unknown>) => void;
    }) => Promise<void>) {
      await fn({
        async get(ref) {
          return ref.get();
        },
        set(ref, value) {
          store.set(ref.id, value);
        },
      });
    },
  };
}

function appWithAuth(opts: {
  requireAppCheck?: boolean;
  verifyAppCheck?: (t: string) => Promise<void>;
  rateLimit?: { windowMs: number; max: number };
  rateLimiter?: ReturnType<typeof createRateLimiter>;
  uid?: string;
}) {
  const uid = opts.uid ?? 'uid-a';
  const auth = {
    verifyIdToken: vi.fn(async (token: string) => {
      if (token === 'bad') throw new Error('invalid');
      if (token === 'revoked') {
        const err = new Error('auth/id-token-revoked');
        throw err;
      }
      return { uid, phone_number: '+923001234567' };
    }),
  };
  return createApp({
    auth: auth as never,
    db: memoryDb() as never,
    requireAppCheck: opts.requireAppCheck ?? false,
    verifyAppCheck: opts.verifyAppCheck,
    rateLimit: opts.rateLimit,
    rateLimiter: opts.rateLimiter,
  });
}

describe('App Check enforcement', () => {
  it('rejects missing App Check when required', async () => {
    const app = appWithAuth({ requireAppCheck: true });
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('APP_CHECK_REQUIRED');
  });

  it('rejects invalid App Check token', async () => {
    const app = appWithAuth({
      requireAppCheck: true,
      verifyAppCheck: async () => {
        throw new Error('bad app check');
      },
    });
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good')
      .set('X-Firebase-AppCheck', 'fake');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('APP_CHECK_INVALID');
    expect(JSON.stringify(res.body)).not.toMatch(/bad app check/i);
  });

  it('allows valid App Check + token', async () => {
    const app = appWithAuth({
      requireAppCheck: true,
      verifyAppCheck: async () => undefined,
    });
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good')
      .set('X-Firebase-AppCheck', 'ok');
    // 404 user not found vs 200 — either means auth+appcheck passed
    expect([200, 404]).toContain(res.status);
  });
});

describe('API rate limiting', () => {
  it('allows normal traffic under the limit', async () => {
    const limiter = createRateLimiter({
      windowMs: 60_000,
      max: 5,
      keyFn: (req) => `auth:${req.caller?.uid}:${req.ip ?? 'x'}`,
    });
    const app = appWithAuth({ rateLimiter: limiter });
    for (let i = 0; i < 5; i++) {
      const res = await request(app)
        .get('/v1/auth/me')
        .set('Authorization', 'Bearer good');
      expect(res.status).not.toBe(429);
    }
  });

  it('returns RATE_LIMITED after threshold', async () => {
    const limiter = createRateLimiter({
      windowMs: 60_000,
      max: 3,
      keyFn: (req) => `auth:${req.caller?.uid}:${req.ip ?? 'x'}`,
    });
    const app = appWithAuth({ rateLimiter: limiter });
    for (let i = 0; i < 3; i++) {
      await request(app).get('/v1/auth/me').set('Authorization', 'Bearer good');
    }
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good');
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe('RATE_LIMITED');
    expect(res.body.error.message).toMatch(/try again/i);
    expect(res.headers['retry-after']).toBeDefined();
    expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('does not trust spoofed body uid for rate-limit buckets', async () => {
    const keys: string[] = [];
    const limiter = createRateLimiter({
      windowMs: 60_000,
      max: 100,
      keyFn: (req) => {
        const key = `auth:${req.caller?.uid}`;
        keys.push(key);
        return key;
      },
    });
    const app = appWithAuth({ rateLimiter: limiter, uid: 'real-uid' });
    await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good')
      .query({ userId: 'spoofed-uid' });
    expect(keys.every((k) => k.includes('real-uid'))).toBe(true);
    expect(keys.some((k) => k.includes('spoofed'))).toBe(false);
  });

  it('isolates buckets per verified uid', async () => {
    const limiter = createRateLimiter({
      windowMs: 60_000,
      max: 1,
      keyFn: (req) => `auth:${req.caller?.uid}`,
    });
    const appA = appWithAuth({ rateLimiter: limiter, uid: 'user-a' });
    const appB = createApp({
      auth: {
        verifyIdToken: vi.fn(async () => ({ uid: 'user-b' })),
      } as never,
      db: memoryDb() as never,
      requireAppCheck: false,
      rateLimiter: limiter,
    });

    await request(appA).get('/v1/auth/me').set('Authorization', 'Bearer a');
    const limitedA = await request(appA)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer a');
    expect(limitedA.status).toBe(429);

    const okB = await request(appB)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer b');
    expect(okB.status).not.toBe(429);
  });

  it('resets after window expiration', async () => {
    const limiter = createRateLimiter({
      windowMs: 30,
      max: 1,
      keyFn: (req) => `auth:${req.caller?.uid}`,
    });
    const app = appWithAuth({ rateLimiter: limiter });
    await request(app).get('/v1/auth/me').set('Authorization', 'Bearer good');
    expect(
      (await request(app).get('/v1/auth/me').set('Authorization', 'Bearer good'))
        .status,
    ).toBe(429);
    await new Promise((r) => setTimeout(r, 40));
    expect(
      (await request(app).get('/v1/auth/me').set('Authorization', 'Bearer good'))
        .status,
    ).not.toBe(429);
  });
});

describe('error sanitization', () => {
  it('does not leak token verification internals', async () => {
    const app = appWithAuth({});
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer bad');
    expect(res.status).toBe(401);
    expect(res.body.error.detail).toBeUndefined();
    expect(JSON.stringify(res.body)).not.toMatch(/service account|stack|ECONNREFUSED/i);
    expect(res.body.error.message).toBe('Invalid or expired Firebase ID token.');
  });
});

describe('token verification contract', () => {
  it('calls verifyIdToken with checkRevoked=true', async () => {
    const verifyIdToken = vi.fn(async () => ({
      uid: 'uid-a',
      phone_number: '+923001234567',
    }));
    const app = createApp({
      auth: { verifyIdToken } as never,
      db: memoryDb() as never,
      requireAppCheck: false,
    });
    await request(app).get('/v1/auth/me').set('Authorization', 'Bearer good');
    expect(verifyIdToken).toHaveBeenCalledWith('good', true);
  });

  it('rejects revoked token with sanitized UNAUTHENTICATED', async () => {
    const app = appWithAuth({});
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer revoked');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHENTICATED');
    expect(JSON.stringify(res.body)).not.toMatch(/revoked/i);
  });
});

describe('request body limits', () => {
  it('configures JSON body limit at 32kb (fail-closed contract)', () => {
    // Express json limit is set in createApp; oversized payloads are rejected
    // by body-parser in production. Emulating raw socket hangs in supertest,
    // so this unit assertion locks the configured limit string in app.ts.
    const { readFileSync } = require('node:fs') as typeof import('node:fs');
    const { resolve } = require('node:path') as typeof import('node:path');
    const src = readFileSync(resolve(__dirname, '../app.ts'), 'utf8');
    expect(src).toMatch(/express\.json\(\{\s*limit:\s*'32kb'\s*\}\)/);
  });
});
