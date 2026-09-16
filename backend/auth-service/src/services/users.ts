import type { Firestore } from 'firebase-admin/firestore';
import { toPublicProfile } from './profile';
import { normalizeDisplayName } from './display_name';
import type { AuthenticatedCaller, UserProfile } from '../types';

const USERS = 'users';

export class UserNotFoundError extends Error {
  constructor() {
    super('USER_NOT_FOUND');
    this.name = 'UserNotFoundError';
  }
}

/**
 * Idempotent first-sign-in bootstrap.
 *
 * Identity ALWAYS comes from the verified Firebase token — never from the
 * request body. Concurrent calls for the same uid create at most one document.
 */
export async function registerUser(
  db: Firestore,
  caller: AuthenticatedCaller,
  now: Date,
): Promise<UserProfile> {
  const ref = db.collection(USERS).doc(caller.uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      return;
    }

    tx.set(ref, {
      uid: caller.uid,
      phoneNumber: caller.phoneNumber ?? '',
      displayName: null,
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    });
  });

  const after = await ref.get();
  if (!after.exists) {
    throw new Error('REGISTER_PERSIST_FAILED');
  }
  return toPublicProfile(after.data() ?? {}, caller.uid);
}

export async function getMe(
  db: Firestore,
  caller: AuthenticatedCaller,
): Promise<UserProfile | null> {
  const snap = await db.collection(USERS).doc(caller.uid).get();
  if (!snap.exists) {
    return null;
  }
  return toPublicProfile(snap.data() ?? {}, caller.uid);
}

/**
 * Updates only displayName + updatedAt for the authenticated caller.
 * Security fields are never written from this path.
 */
export async function updateProfile(
  db: Firestore,
  caller: AuthenticatedCaller,
  displayNameRaw: unknown,
  now: Date,
): Promise<UserProfile> {
  const displayName = normalizeDisplayName(displayNameRaw);
  const ref = db.collection(USERS).doc(caller.uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new UserNotFoundError();
    }
    tx.update(ref, {
      displayName,
      updatedAt: now.toISOString(),
    });
  });

  const after = await ref.get();
  if (!after.exists) {
    throw new UserNotFoundError();
  }
  return toPublicProfile(after.data() ?? {}, caller.uid);
}
