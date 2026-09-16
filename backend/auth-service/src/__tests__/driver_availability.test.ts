import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedApprovedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  seedUser(db, uid, {
    role: 'driver',
    driverStatus: 'approved',
    ...overrides,
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid,
      phone_number: '+923001111111',
    }),
  } as never;
}

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

describe('N1 driver availability — authorization', () => {
  it('rejects unauthenticated go-online', async () => {
    const db = memoryDb();
    const app = createApp({
      auth: {
        verifyIdToken: vi.fn().mockRejectedValue(new Error('bad')),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
    const res = await request(app).post('/v1/drivers/go-online').send({});
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHENTICATED');
  });

  it('rejects passenger go-online', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', { role: 'passenger', driverStatus: 'none' });
    const res = await request(appFor(db, 'p1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_APPROVED');
    expect(db.getDoc('drivers', 'p1')).toBeUndefined();
  });

  it('rejects unapproved (pending) driver go-online', async () => {
    const db = memoryDb();
    seedUser(db, 'd-pending', {
      role: 'driver',
      driverStatus: 'pending',
    });
    const res = await request(appFor(db, 'd-pending'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_APPROVED');
  });

  it('rejects suspended driver go-online', async () => {
    const db = memoryDb();
    seedUser(db, 'd-susp', {
      role: 'driver',
      driverStatus: 'suspended',
    });
    const res = await request(appFor(db, 'd-susp'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_APPROVED');
  });

  it('approved driver go-online succeeds', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      driverId: 'd1',
      availabilityState: 'online',
    });
  });

  it('approved driver go-offline succeeds', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      userId: 'd1',
      availabilityState: 'online',
    });
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      driverId: 'd1',
      availabilityState: 'offline',
    });
  });
});

describe('N1 driver availability — state', () => {
  it('offline → online', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(200);
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('online');
  });

  it('online → offline', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(res.status).toBe(200);
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('offline');
  });

  it('repeated go-online is idempotent', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    const a = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const firstUpdatedAt = db.getDoc('drivers', 'd1')?.updatedAt;
    const b = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(b.body.data.availabilityState).toBe('online');
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('online');
    expect(db.getDoc('drivers', 'd1')?.updatedAt).toBe(firstUpdatedAt);
  });

  it('repeated go-offline is idempotent', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const off1 = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    const firstUpdatedAt = db.getDoc('drivers', 'd1')?.updatedAt;
    const off2 = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    expect(off1.status).toBe(200);
    expect(off2.status).toBe(200);
    expect(off2.body.data.availabilityState).toBe('offline');
    expect(db.getDoc('drivers', 'd1')?.updatedAt).toBe(firstUpdatedAt);
  });
});

describe('N1 driver availability — security', () => {
  it('client cannot select another driver via body', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedApprovedDriver(db, 'd2');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({ driverId: 'd2' });
    expect(res.status).toBe(200);
    expect(res.body.data.driverId).toBe('d1');
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('online');
    expect(db.getDoc('drivers', 'd2')).toBeUndefined();
  });

  it('authoritative availability is not client-writable path (server-only field)', async () => {
    // Contract: clients never write drivers/* (firestore.rules deny).
    // This test proves the API ignores client-supplied availabilityState.
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({ availabilityState: 'online' });
    expect(res.status).toBe(200);
    expect(res.body.data.availabilityState).toBe('offline');
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('offline');
  });
});

describe('N1 driver availability — concurrency', () => {
  it('concurrent go-online requests converge to online', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    const results = await Promise.all([
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
    ]);
    for (const res of results) {
      expect(res.status).toBe(200);
      expect(res.body.data.availabilityState).toBe('online');
    }
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('online');
  });

  it('concurrent go-offline requests converge to offline', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const results = await Promise.all([
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
    ]);
    for (const res of results) {
      expect(res.status).toBe(200);
      expect(res.body.data.availabilityState).toBe('offline');
    }
    expect(db.getDoc('drivers', 'd1')?.availabilityState).toBe('offline');
  });
});

describe('N1 driver availability — persistence', () => {
  it('Firestore contains authoritative state after mutations', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');

    expect(db.getDoc('drivers', 'd1')).toBeUndefined();

    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const online = db.getDoc('drivers', 'd1');
    expect(online?.availabilityState).toBe('online');
    expect(online?.driverId).toBe('d1');
    expect(online?.userId).toBe('d1');
    expect(typeof online?.lastOnlineAt).toBe('string');
    expect(typeof online?.updatedAt).toBe('string');

    await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    const offline = db.getDoc('drivers', 'd1');
    expect(offline?.availabilityState).toBe('offline');
    expect(offline?.driverId).toBe('d1');
  });
});
