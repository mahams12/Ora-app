import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb, throwingDb } from './helpers/memory_db';

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001234567',
    displayName: null,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  });
}

function authedApp(opts: {
  uid?: string;
  db?: ReturnType<typeof memoryDb> | ReturnType<typeof throwingDb>;
  tokenBehavior?: 'ok' | 'invalid' | 'revoked';
}) {
  const uid = opts.uid ?? 'uid-1';
  const auth = {
    verifyIdToken: vi.fn(async (token: string, checkRevoked?: boolean) => {
      expect(checkRevoked).toBe(true);
      if (opts.tokenBehavior === 'invalid') {
        throw new Error('invalid');
      }
      if (opts.tokenBehavior === 'revoked' || token === 'revoked') {
        throw new Error('auth/id-token-revoked');
      }
      return { uid, phone_number: '+923001234567' };
    }),
  };
  return createApp({
    auth: auth as never,
    db: (opts.db ?? memoryDb()) as never,
    requireAppCheck: false,
  });
}

describe('PATCH /v1/auth/profile', () => {
  it('sets a valid displayName and marks profileComplete', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });

    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada Lovelace' });

    expect(res.status).toBe(200);
    expect(res.body.displayName).toBe('Ada Lovelace');
    expect(res.body.profileComplete).toBe(true);
    expect(res.body.uid).toBe('uid-1');
    expect(res.headers['x-request-id']).toBeTruthy();
    expect(db.getDoc('users', 'uid-1')?.displayName).toBe('Ada Lovelace');
    expect(db.getDoc('users', 'uid-1')?.role).toBe('passenger');
  });

  it('trims and collapses whitespace', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });

    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: '  Ada   Khan  ' });

    expect(res.status).toBe(200);
    expect(res.body.displayName).toBe('Ada Khan');
  });

  it('GET /me returns the updated name', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });

    await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Fatima' });

    const me = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good');

    expect(me.status).toBe(200);
    expect(me.body.displayName).toBe('Fatima');
    expect(me.body.profileComplete).toBe(true);
  });

  it('repeating the same valid update is safe', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });

    const a = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });
    const b = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });

    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(b.body.displayName).toBe('Ada');
  });

  it('rejects missing Authorization', async () => {
    const app = authedApp({});
    const res = await request(app)
      .patch('/v1/auth/profile')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHENTICATED');
    expect(res.body.requestId).toBeTruthy();
  });

  it('rejects invalid tokens', async () => {
    const app = authedApp({ tokenBehavior: 'invalid' });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer bad')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(401);
  });

  it('rejects revoked tokens', async () => {
    const app = authedApp({ tokenBehavior: 'revoked' });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer revoked')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(401);
    expect(res.body.error.message).not.toMatch(/stack|firestore/i);
  });

  it('rejects banned users', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1', { banned: true, displayName: 'Ada' });
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('ACCOUNT_DISABLED');
  });

  it('rejects inactive users', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1', { isActive: false, displayName: 'Ada' });
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('ACCOUNT_DISABLED');
  });

  it('rejects empty name', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: '' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects whitespace-only name', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: '   ' });
    expect(res.status).toBe(400);
  });

  it('rejects too-short name', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'A' });
    expect(res.status).toBe(400);
  });

  it('rejects too-long name', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'A'.repeat(51) });
    expect(res.status).toBe(400);
    expect(db.getDoc('users', 'uid-1')?.displayName).toBeNull();
  });

  it('rejects control characters', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada\u0007Khan' });
    expect(res.status).toBe(400);
  });

  it('rejects unknown fields including uid and security fields', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });

    const payloads = [
      { displayName: 'Ada', uid: 'other-uid' },
      { displayName: 'Ada', role: 'admin' },
      { displayName: 'Ada', driverStatus: 'approved' },
      { displayName: 'Ada', isActive: false },
      { displayName: 'Ada', banned: false },
      { displayName: 'Ada', profileComplete: true },
    ];

    for (const body of payloads) {
      const res = await request(app)
        .patch('/v1/auth/profile')
        .set('Authorization', 'Bearer good')
        .send(body);
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    }

    expect(db.getDoc('users', 'uid-1')?.role).toBe('passenger');
    expect(db.getDoc('users', 'uid-1')?.displayName).toBeNull();
    expect(db.getDoc('users', 'uid-1')?.isActive).toBe(true);
  });

  it('IDOR: token uid is the only write target', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    seedUser(db, 'victim', {
      displayName: 'Victim',
      phoneNumber: '+923009999999',
    });
    const app = authedApp({ uid: 'uid-1', db });

    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Attacker' });

    expect(res.status).toBe(200);
    expect(res.body.uid).toBe('uid-1');
    expect(db.getDoc('users', 'uid-1')?.displayName).toBe('Attacker');
    expect(db.getDoc('users', 'victim')?.displayName).toBe('Victim');
  });

  it('returns 404 when the user document does not exist', async () => {
    const app = authedApp({ db: memoryDb() });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('USER_NOT_FOUND');
  });

  it('does not leak Firestore internals on update failure', async () => {
    const app = authedApp({ db: throwingDb() });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: 'Ada' });
    expect(res.status).toBe(500);
    expect(res.body.error.code).toBe('INTERNAL');
    expect(JSON.stringify(res.body)).not.toMatch(/FIRESTORE_UNAVAILABLE|stack/i);
  });

  it('rejects digit-only names that lack letters', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ displayName: '12' });
    expect(res.status).toBe(400);
  });

  it('ignores a body uid that tries to target another user', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    seedUser(db, 'victim', { displayName: 'Victim' });
    const app = authedApp({ uid: 'uid-1', db });
    const res = await request(app)
      .patch('/v1/auth/profile')
      .set('Authorization', 'Bearer good')
      .send({ uid: 'victim' });
    expect(res.status).toBe(400);
    expect(db.getDoc('users', 'victim')?.displayName).toBe('Victim');
    expect(db.getDoc('users', 'uid-1')?.displayName).toBeNull();
  });

  it('concurrent valid updates remain consistent', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1');
    const app = authedApp({ db });
    const [a, b] = await Promise.all([
      request(app)
        .patch('/v1/auth/profile')
        .set('Authorization', 'Bearer good')
        .send({ displayName: 'Ada' }),
      request(app)
        .patch('/v1/auth/profile')
        .set('Authorization', 'Bearer good')
        .send({ displayName: 'Ada' }),
    ]);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(db.getDoc('users', 'uid-1')?.displayName).toBe('Ada');
    expect(db.getDoc('users', 'uid-1')?.role).toBe('passenger');
  });
});

describe('request correlation', () => {
  it('echoes a valid client X-Request-Id', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1', { displayName: 'Ada' });
    const app = authedApp({ db });
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good')
      .set('X-Request-Id', 'client-req-12345');
    expect(res.headers['x-request-id']).toBe('client-req-12345');
  });

  it('generates a request id when the client omits one', async () => {
    const db = memoryDb();
    seedUser(db, 'uid-1', { displayName: 'Ada' });
    const app = authedApp({ db });
    const res = await request(app)
      .get('/v1/auth/me')
      .set('Authorization', 'Bearer good');
    expect(res.headers['x-request-id']).toMatch(
      /^[0-9a-f-]{36}$|^[A-Za-z0-9._-]{8,128}$/,
    );
  });
});

describe('register failure surface', () => {
  it('returns 500 without internals when Firestore is down', async () => {
    const app = authedApp({ db: throwingDb() });
    const res = await request(app)
      .post('/v1/auth/register')
      .set('Authorization', 'Bearer good')
      .set('Idempotency-Key', 'register_uid-1')
      .send({});
    expect(res.status).toBe(500);
    expect(res.body.error.code).toBe('INTERNAL');
    expect(res.body.requestId).toBeTruthy();
    expect(JSON.stringify(res.body)).not.toMatch(/FIRESTORE_UNAVAILABLE/);
  });
});
