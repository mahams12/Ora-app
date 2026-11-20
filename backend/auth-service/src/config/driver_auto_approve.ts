/**
 * DRIVER_AUTO_APPROVE — defaults OFF. Driver applications require admin
 * approval (POST /v1/internal/drivers/:uid/status) unless this env var is
 * explicitly set to 'true'/'1'. Local emulator scripts set it explicitly
 * as an approved development exception; production deploys must not.
 */
export function driverAutoApproveFromEnv(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.DRIVER_AUTO_APPROVE?.trim().toLowerCase();
  return value === 'true' || value === '1';
}
