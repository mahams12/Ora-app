import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import type { AuthenticatedCaller } from '../types';
import { deriveProfileComplete, toPublicProfile } from '../services/profile';

function memoryDb() {
  const store = new Map<string, Record<string, unknown>>();

  const doc = (id: string) => ({
    id,
    async get() {
      const data = store.get(id);
      return {
        exists: data != null,
        data: () => data,
      };
    },
    async set(value: Record<string, unknown>) {
      store.set(id, value);
    },
  });

  return {
    store,
    collection(_name: string) {
      return {
        doc,
      };
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

describe('deriveProfileComplete', () => {
  it('fails closed for banned or inactive accounts', () => {
    expect(
      deriveProfileComplete({
        role: 'passenger',
        isActive: false,
        banned: false,
        displayName: 'Ada',
      }),
    ).toBe(false);
    expect(
      deriveProfileComplete({
        role: 'passenger',
        isActive: true,
        banned: true,
        displayName: 'Ada',
      }),
    ).toBe(false);
  });

  it('requires a non-empty displayName for Phase 2A completeness', () => {
    expect(
      deriveProfileComplete({
        role: 'passenger',
        isActive: true,
        banned: false,
        displayName: null,
      }),
    ).toBe(false);
    expect(
      deriveProfileComplete({
        role: 'passenger',
        isActive: true,
        banned: false,
        displayName: 'Ada',
      }),
    ).toBe(true);
  });
});

describe('toPublicProfile', () => {
  it('never trusts a client role string without defaults', () => {
    const profile = toPublicProfile({}, 'uid-1');
    expect(profile.uid).toBe('uid-1');
    expect(profile.role).toBe('passenger');
    expect(profile.profileComplete).toBe(false);
  });
});

describe('auth HTTP security', () => {
  it('rejects missing Authorization', async () => {
    const db = memoryDb() as never;
    const auth = {
      verifyIdToken: vi.fn(),
    } as never;

    const app = createApp({
      auth,
      db,
      requireAppCheck: false,
    });

    const res = await request(app).get('/v1/auth/me');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHENTICATED');
  });

  it('rejects invalid tokens', async () => {
    const db = memoryDb() as never;
    const auth = {
      verifyIdToken: vi.fn().mockRejectedValue(new Error('bad token')),
    } as never;

    const app = createApp({
      auth,
      db,
      requireAppCheck: false,
    });

    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer bad');
    expect(res.status).toBe(401);
  });

  it('ignores forged body uid and uses token uid for register', async () => {
    const db = memoryDb();
    const caller: AuthenticatedCaller = {
      uid: 'real-uid',
      phoneNumber: '+923001234567',
      email: null,
      disabled: false,
    };
    const auth = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: caller.uid,
        phone_number: caller.phoneNumber,
      }),
    } as never;

    const app = createApp({
      auth,
      db: db as never,
      requireAppCheck: false,
    });

    const res = await request(app)
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer good')
      .set('Idempotency-Key', 'register_real-uid')
      .send({ uid: 'forged-attacker-uid', role: 'admin' });

    expect(res.status).toBe(200);
    expect(res.body.uid).toBe('real-uid');
    expect(res.body.role).toBe('passenger');
    expect(db.store.has('real-uid')).toBe(true);
    expect(db.store.has('forged-attacker-uid')).toBe(false);
  });

  it('rejects register when Idempotency-Key is for another uid', async () => {
    const db = memoryDb() as never;
    const auth = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: 'real-uid',
        phone_number: '+923001234567',
      }),
    } as never;

    const app = createApp({
      auth,
      db,
      requireAppCheck: false,
    });

    const res = await request(app)
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer good')
      .set('Idempotency-Key', 'register_other-uid')
      .send({});

    expect(res.status).toBe(403);
  });

  it('GET /me never uses ?userId= as identity', async () => {
    const db = memoryDb();
    db.store.set('real-uid', {
      uid: 'real-uid',
      phoneNumber: '+923001234567',
      displayName: 'Ada',
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
    });
    db.store.set('victim-uid', {
      uid: 'victim-uid',
      phoneNumber: '+923009999999',
      displayName: 'Victim',
      role: 'admin',
      driverStatus: 'none',
      isActive: true,
      banned: false,
    });

    const auth = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: 'real-uid',
        phone_number: '+923001234567',
      }),
    } as never;

    const app = createApp({
      auth,
      db: db as never,
      requireAppCheck: false,
    });

    const res = await request(app)
      .get('/v1/auth/me?userId=victim-uid')
      .set('Authorization', 'Bearer good');

    expect(res.status).toBe(200);
    expect(res.body.uid).toBe('real-uid');
    expect(res.body.role).toBe('passenger');
    expect(res.body.profileComplete).toBe(true);
  });

  it('duplicate concurrent-style register is idempotent', async () => {
    const db = memoryDb();
    const auth = {
      verifyIdToken: vi.fn().mockResolvedValue({
        uid: 'uid-1',
        phone_number: '+923001234567',
      }),
    } as never;

    const app = createApp({
      auth,
      db: db as never,
      requireAppCheck: false,
    });

    const a = await request(app)
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer good')
      .set('Idempotency-Key', 'register_uid-1')
      .send({});
    const b = await request(app)
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer good')
      .set('Idempotency-Key', 'register_uid-1')
      .send({});

    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(a.body.uid).toBe('uid-1');
    expect(b.body.uid).toBe('uid-1');
    expect([...db.store.keys()]).toEqual(['uid-1']);
  });
});
