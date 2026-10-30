/**
 * Fail-closed Firebase-target guard for standalone scripts.
 *
 * Mirrors src/config/firebase_target_guards.ts for the script side: a script
 * using `applicationDefault()` (or no explicit credential) must either have
 * the Firebase emulator hosts set, or an explicit ORA_ENV=staging|production
 * declaration. Otherwise a bare `npx tsx scripts/foo.ts` can silently fall
 * back to application-default credentials and touch the real project — the
 * same failure mode as the accidental production-write incident.
 *
 * Scripts that deliberately use cert(serviceAccount) are exempt by intent —
 * an explicit credential IS the declaration.
 */
export function assertScriptFirebaseTarget(env: NodeJS.ProcessEnv): void {
  const oraEnv = (env.ORA_ENV ?? env.NODE_ENV ?? '').toLowerCase();
  if (oraEnv === 'staging' || oraEnv === 'production') {
    return; // explicit remote intent
  }

  const missing: string[] = [];
  for (const name of [
    'FIRESTORE_EMULATOR_HOST',
    'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_DATABASE_EMULATOR_HOST',
  ]) {
    if (!env[name]?.trim()) missing.push(name);
  }
  if (missing.length > 0) {
    throw new Error(
      'REFUSING_START: script run requires Firebase emulators. ' +
        `Missing: ${missing.join(', ')}. ` +
        'Set ORA_ENV=staging|production only for real remote backends.',
    );
  }
}
