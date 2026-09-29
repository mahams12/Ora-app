import { applicationDefault, initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { createApp } from './app';
import { assertProductionSecurityConfig } from './config/production_guards';
import { createRedisGeoClientFromEnv } from './redis/client';
import { RedisGeoProjectionService } from './redis/geo_projection';
import { createFirebaseFcmSender } from './delivery/fcm_sender';
import { logSafe } from './http/errors';
import { createGoogleRoutesProviderFromEnv } from './routing/google_routes_provider';
import type { RoutingProvider } from './routing/types';

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

async function main() {
  // eslint-disable-next-line no-console
  console.error('[auth-service] main() enter');
  assertProductionSecurityConfig(process.env);
  const projectId = requireEnv('FIREBASE_PROJECT_ID');
  const requireAppCheck = (process.env.REQUIRE_APP_CHECK ?? 'false') === 'true';
  const port = Number(process.env.PORT ?? '8080');

  if (getApps().length === 0) {
    // eslint-disable-next-line no-console
    console.error('[auth-service] initializeApp…');
    initializeApp({
      credential: applicationDefault(),
      projectId,
    });
  }

  // eslint-disable-next-line no-console
  console.error('[auth-service] getAuth/getFirestore…');
  const auth = getAuth();
  const db = getFirestore();

  const redisClient = await createRedisGeoClientFromEnv(process.env);
  const geoProjection = new RedisGeoProjectionService(redisClient);
  logSafe('redis_geo_init', {
    configured: redisClient != null,
  });

  // D1 — FCM Admin Messaging (data-only). Always construct; send fails gracefully if misconfigured.
  const fcmSender = createFirebaseFcmSender();

  let routingProvider: RoutingProvider | null = null;
  if (process.env.GOOGLE_MAPS_SERVER_KEY?.trim()) {
    routingProvider = createGoogleRoutesProviderFromEnv(process.env);
    logSafe('routing_provider_init', { provider: 'google_routes', configured: true });
  } else {
    logSafe('routing_provider_init', { provider: 'google_routes', configured: false });
  }

  // eslint-disable-next-line no-console
  console.error('[auth-service] createApp…');
  const app = createApp({
    auth,
    db,
    requireAppCheck,
    geoProjection,
    redis: redisClient,
    fcmSender,
    routingProvider,
    verifyAppCheck: requireAppCheck
      ? async (token) => {
          // Lazy import keeps App Check optional until production.
          const { getAppCheck } = await import('firebase-admin/app-check');
          await getAppCheck().verifyToken(token);
        }
      : undefined,
  });

  app.listen(port, () => {
    // eslint-disable-next-line no-console
    console.log(
      `ora-auth-service listening on :${port} project=${projectId} appCheck=${requireAppCheck} redisGeo=${redisClient != null} routing=${routingProvider != null}`,
    );
  });
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('Fatal startup error', err);
  process.exit(1);
});
