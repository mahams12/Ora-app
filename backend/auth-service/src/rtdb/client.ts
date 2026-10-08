import type { App } from 'firebase-admin/app';
import { getApps } from 'firebase-admin/app';
import type { TripLocationRtdb } from './types';
import {
  AdminTripLocationRtdb,
  NullTripLocationRtdb,
} from './admin_trip_location_rtdb';

/**
 * Options for the single Firebase Admin app used by auth-service.
 * Reuses existing initializeApp pattern — never creates a second named app.
 */
export function resolveFirebaseAdminAppOptions(env: NodeJS.ProcessEnv): {
  projectId: string;
  databaseURL?: string;
} {
  const projectId = env.FIREBASE_PROJECT_ID?.trim();
  if (!projectId) {
    throw new Error('Missing required environment variable: FIREBASE_PROJECT_ID');
  }
  const databaseURL = env.FIREBASE_DATABASE_URL?.trim();
  if (databaseURL) {
    return { projectId, databaseURL };
  }
  return { projectId };
}

export function isRtdbConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(env.FIREBASE_DATABASE_URL?.trim());
}

/**
 * Build TripLocationRtdb from the default Admin app when FIREBASE_DATABASE_URL is set.
 * Returns NullTripLocationRtdb otherwise (same optional pattern as Redis).
 *
 * Call only after initializeApp (with databaseURL when configured).
 */
export function createTripLocationRtdbFromEnv(
  env: NodeJS.ProcessEnv = process.env,
  apps: App[] = getApps(),
): TripLocationRtdb {
  if (!isRtdbConfigured(env)) {
    return new NullTripLocationRtdb();
  }
  if (apps.length === 0) {
    throw new Error(
      'FIREBASE_DATABASE_URL is set but Firebase Admin app is not initialized.',
    );
  }
  // Lazy require keeps unit tests without databaseURL free of getDatabase side effects.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { getDatabase } = require('firebase-admin/database') as typeof import('firebase-admin/database');
  return new AdminTripLocationRtdb(getDatabase(apps[0]));
}
