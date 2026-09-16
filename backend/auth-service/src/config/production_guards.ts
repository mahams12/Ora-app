/**
 * Fail-closed production startup guards for auth-service.
 *
 * PRODUCTION + REQUIRE_APP_CHECK=false must refuse to start.
 */
export function assertProductionSecurityConfig(env: NodeJS.ProcessEnv): void {
  const oraEnv = (env.ORA_ENV ?? env.NODE_ENV ?? '').toLowerCase();
  const isProduction =
    oraEnv === 'production' || env.ORA_FORCE_PRODUCTION_GUARDS === 'true';
  const requireAppCheck = (env.REQUIRE_APP_CHECK ?? 'false') === 'true';

  if (isProduction && !requireAppCheck) {
    throw new Error(
      'REFUSING_START: production requires REQUIRE_APP_CHECK=true (fail-closed).',
    );
  }
}
