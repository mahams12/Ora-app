export function driverAutoApproveFromEnv(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const value = env.DRIVER_AUTO_APPROVE?.trim().toLowerCase();
  return value !== 'false' && value !== '0';
}
