/**
 * MAP-1 live proof: Google Routes returns optional encodedPolyline (display-only).
 * Does not print coordinates or API keys.
 */
import { createGoogleRoutesProviderFromEnv } from '../src/routing/google_routes_provider';

async function main(): Promise<void> {
  if (!process.env.GOOGLE_MAPS_SERVER_KEY?.trim()) {
    console.error('GOOGLE_MAPS_SERVER_KEY missing');
    process.exit(2);
  }
  const provider = createGoogleRoutesProviderFromEnv(process.env);
  const route = await provider.computeDriveRoute({
    origin: { lat: 31.5204, lng: 74.3587 },
    destination: { lat: 31.51058, lng: 74.34445 },
  });
  const poly = route.encodedPolyline;
  console.log(
    JSON.stringify({
      ok: true,
      distanceKm: route.distanceKm,
      durationMin: route.durationMin,
      hasEncodedPolyline: typeof poly === 'string' && poly.trim().length > 0,
      polylineCharLen: typeof poly === 'string' ? poly.length : 0,
      provider: route.provider,
    }),
  );
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
