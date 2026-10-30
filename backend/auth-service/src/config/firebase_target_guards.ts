/**
 * Fail-closed Firebase-target guard for auth-service startup.
 *
 * Local/development runs must talk to Firebase emulators and zero-cost
 * providers only. Unless ORA_ENV explicitly names a remote environment
 * (staging/production), the process refuses to start without the emulator
 * hosts — a bare `tsx src/index.ts` can never silently fall back to the
 * real Firebase project, real FCM, or paid Google Routes.
 */
export function assertFirebaseTargetConfig(env: NodeJS.ProcessEnv): void {
  const oraEnv = (env.ORA_ENV ?? env.NODE_ENV ?? '').toLowerCase();
  const remoteTarget = oraEnv === 'staging' || oraEnv === 'production';

  if (remoteTarget) {
    if (env.ORA_REQUIRE_FIREBASE_EMULATOR === 'true') {
      throw new Error(
        `REFUSING_START: ORA_ENV=${oraEnv} conflicts with ` +
          'ORA_REQUIRE_FIREBASE_EMULATOR=true.',
      );
    }
    return;
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
      'REFUSING_START: local/development run requires Firebase emulators. ' +
        `Missing: ${missing.join(', ')}. ` +
        'Set ORA_ENV=staging|production only for real remote backends.',
    );
  }

  const fcmSender = (env.ORA_FCM_SENDER ?? '').trim();
  if (fcmSender !== 'none') {
    throw new Error(
      'REFUSING_START: emulator mode requires ORA_FCM_SENDER=none ' +
        `(got "${fcmSender || 'unset'}") — real FCM sends are forbidden locally.`,
    );
  }

  const routingProvider = (env.ORA_ROUTING_PROVIDER ?? '').trim();
  if (routingProvider !== 'haversine') {
    throw new Error(
      'REFUSING_START: emulator mode requires ORA_ROUTING_PROVIDER=haversine ' +
        `(got "${routingProvider || 'unset'}") — paid routing is forbidden locally.`,
    );
  }
}
