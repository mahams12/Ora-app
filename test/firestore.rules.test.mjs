/**
 * Firestore security rules — emulator suite (Phase 2B staging verification).
 *
 * Run:
 *   firebase emulators:exec --only firestore --project ora-app-d8112 \
 *     "npx mocha --timeout 20000 test/firestore.rules.test.mjs"
 *
 * Does not weaken rules to obtain PASS.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectId = 'ora-app-d8112';
const rules = readFileSync(resolve(__dirname, '../firestore.rules'), 'utf8');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules,
      host: '127.0.0.1',
      port: 8181,
    },
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

describe('users', () => {
  it('unauthenticated cannot read users', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users/u1')));
  });

  it('authenticated user can read own profile', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923001111111',
        displayName: 'Ada',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(getDoc(doc(db, 'users/u1')));
  });

  it('authenticated user cannot read another user', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u2'), {
        uid: 'u2',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923002222222',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(getDoc(doc(db, 'users/u2')));
  });

  it('client cannot create users doc', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      setDoc(doc(db, 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923001111111',
      }),
    );
  });

  it('client cannot escalate role', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923001111111',
        displayName: 'Ada',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(updateDoc(doc(db, 'users/u1'), { role: 'admin' }));
  });

  it('client cannot set banned', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923001111111',
        displayName: 'Ada',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(updateDoc(doc(db, 'users/u1'), { banned: true }));
  });

  it('client cannot update displayName (API-only profile writes)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        displayName: 'Ada',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/u1'), { displayName: 'Ada Lovelace' }),
    );
  });

  it('client cannot modify isActive', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(updateDoc(doc(db, 'users/u1'), { isActive: false }));
  });

  it('client cannot modify driverStatus', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        driverStatus: 'none',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/u1'), { driverStatus: 'approved' }),
    );
  });

  it('client cannot modify uid', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(updateDoc(doc(db, 'users/u1'), { uid: 'u2' }));
  });

  it('client cannot modify phoneNumber', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/u1'), { phoneNumber: '+923009999999' }),
    );
  });

  it('client cannot modify capabilities or accountStatus', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/u1'), { accountStatus: 'ACTIVE' }),
    );
    await assertFails(
      updateDoc(doc(db, 'users/u1'), { capabilities: { driver: true } }),
    );
  });

  it('client cannot modify another user document', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u2'), {
        uid: 'u2',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923002222222',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'users/u2'), { displayName: 'Hacked' }),
    );
  });

  it('client cannot create another user document', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      setDoc(doc(db, 'users/u2'), {
        uid: 'u2',
        role: 'passenger',
        banned: false,
        phoneNumber: '+923002222222',
      }),
    );
  });

  it('client cannot delete own user document', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/u1'), {
        uid: 'u1',
        role: 'passenger',
        banned: false,
        isActive: true,
        phoneNumber: '+923001111111',
        createdAt: '2026-01-01',
      });
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(deleteDoc(doc(db, 'users/u1')));
  });
});

describe('authoritative collections (deny all clients)', () => {
  const denied = [
    'rides',
    'rideOffers',
    'outboxEvents',
    'idempotencyRecords',
    'pricingSnapshots',
    'drivers',
    'paymentIntents',
    'walletAccounts',
    'reports',
    'blocks',
    'safetyEvents',
    'adminAuditLogs',
    'otpSessions',
  ];

  for (const collection of denied) {
    it(`unauthenticated cannot read ${collection}`, async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `${collection}/x1`), { a: 1 });
      });
      const db = testEnv.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(db, `${collection}/x1`)));
    });

    it(`authenticated cannot write ${collection}`, async () => {
      const db = testEnv.authenticatedContext('u1').firestore();
      await assertFails(setDoc(doc(db, `${collection}/x1`), { a: 1 }));
      await assertFails(deleteDoc(doc(db, `${collection}/x1`)));
    });
  }
});

describe('savedPlaces owner rules', () => {
  it('owner can create and read', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'savedPlaces/p1'), { ownerUid: 'u1', label: 'Home' }),
    );
    await assertSucceeds(getDoc(doc(db, 'savedPlaces/p1')));
  });

  it('non-owner cannot read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'savedPlaces/p1'), {
        ownerUid: 'u1',
        label: 'Home',
      });
    });
    const db = testEnv.authenticatedContext('u2').firestore();
    await assertFails(getDoc(doc(db, 'savedPlaces/p1')));
  });
});
