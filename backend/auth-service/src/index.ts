import { applicationDefault, initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { createApp } from './app';
import { assertFirebaseTargetConfig } from './config/firebase_target_guards';
import { assertProductionSecurityConfig } from './config/production_guards';
import { createFirestoreGeoClient } from './redis/firestore_geo_client';
import { createRtdbGeoClient } from './rtdb/rtdb_geo_client';
import { createRtdbLocationStreamStore } from './rtdb/rtdb_stream_store';
import type { LocationStreamStore } from './location/stream_store';
import { RedisGeoProjectionService } from './redis/geo_projection';
import type { RedisGeoClient } from './redis/types';
import {
  createFirebaseFcmSender,
  createNullFcmSender,
} from './delivery/fcm_sender';
import { logSafe } from './http/errors';
import { createGoogleRoutesProviderFromEnv } from './routing/google_routes_provider';
import { HaversineRoutingProvider } from './routing/haversine_provider';
import type { RoutingProvider } from './routing/types';
import {
  createTripLocationRtdbFromEnv,
  resolveFirebaseAdminAppOptions,
} from './rtdb/client';

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
  assertFirebaseTargetConfig(process.env);
  const projectId = requireEnv('FIREBASE_PROJECT_ID');
  const requireAppCheck = (process.env.REQUIRE_APP_CHECK ?? 'false') === 'true';
  const port = Number(process.env.PORT ?? '8080');

  if (getApps().length === 0) {
    // eslint-disable-next-line no-console
    console.error('[auth-service] initializeApp…');
    const adminOpts = resolveFirebaseAdminAppOptions(process.env);
    initializeApp({
      credential: applicationDefault(),
      projectId: adminOpts.projectId,
      ...(adminOpts.databaseURL
        ? { databaseURL: adminOpts.databaseURL }
        : {}),
    });
  }

  // eslint-disable-next-line no-console
  console.error('[auth-service] getAuth/getFirestore…');
  const auth = getAuth();
  const db = getFirestore();

  // L2 Step 2/3 — RTDB foundation + projection (optional until FIREBASE_DATABASE_URL).
  const tripLocationRtdb = createTripLocationRtdbFromEnv(process.env);
  logSafe('rtdb_init', {
    configured: process.env.FIREBASE_DATABASE_URL?.trim() ? true : false,
  });

  // GEO store: Firestore-native index (default) or RTDB geohash index behind
  // GEO_BACKEND flag. Firestore remains the rollback-safe default.
  const geoBackend = (process.env.GEO_BACKEND ?? 'firestore').trim().toLowerCase();
  let redisClient: RedisGeoClient;
  if (geoBackend === 'rtdb') {
    if (!process.env.FIREBASE_DATABASE_URL?.trim()) {
      throw new Error(
        'REFUSING_START: GEO_BACKEND=rtdb requires FIREBASE_DATABASE_URL.',
      );
    }
    const { getDatabase } = await import('firebase-admin/database');
    redisClient = createRtdbGeoClient(getDatabase().ref('/'));
  } else if (geoBackend === 'firestore') {
    redisClient = createFirestoreGeoClient(db);
  } else {
    throw new Error(
      `REFUSING_START: unknown GEO_BACKEND '${geoBackend}' (expected firestore|rtdb).`,
    );
  }
  // Cost-optimization flags (default off — preserve existing behavior).
  // LOCATION_ADAPTIVE_FRESHNESS: per-driver marker expiry from declared
  // publish cadence. LOCATION_IDLE_MERGED_CURSOR: idle stream cursor folds
  // into the geoDrivers marker write (Firestore geo only).
  const adaptiveFreshness =
    (process.env.LOCATION_ADAPTIVE_FRESHNESS ?? '').trim() === 'true';
  const idleMergedCursor =
    (process.env.LOCATION_IDLE_MERGED_CURSOR ?? '').trim() === 'true';
  const pricingRulesCacheTtlMs = Math.max(
    0,
    Number(process.env.PRICING_RULES_CACHE_TTL_MS ?? '0') || 0,
  );

  const geoProjection = new RedisGeoProjectionService(redisClient, {
    adaptiveFreshness,
  });
  logSafe('geo_init', {
    configured: true,
    store: geoBackend,
    adaptiveFreshness,
    idleMergedCursor,
  });

  // locationStreams cursor store: defaults to the GEO_BACKEND pairing
  // (firestore cursors ↔ firestore geo, rtdb cursors ↔ rtdb geo) but can be
  // overridden independently. RTDB cursors remove the per-packet billed
  // 1R+1W Firestore transaction; semantics are byte-identical.
  const streamBackend = (
    process.env.LOCATION_STREAMS_BACKEND ?? geoBackend
  )
    .trim()
    .toLowerCase();
  let streamStore: LocationStreamStore | undefined;
  if (streamBackend === 'rtdb') {
    if (!process.env.FIREBASE_DATABASE_URL?.trim()) {
      throw new Error(
        'REFUSING_START: LOCATION_STREAMS_BACKEND=rtdb requires FIREBASE_DATABASE_URL.',
      );
    }
    const { getDatabase } = await import('firebase-admin/database');
    streamStore = createRtdbLocationStreamStore(getDatabase().ref('/'));
  } else if (streamBackend !== 'firestore') {
    throw new Error(
      `REFUSING_START: unknown LOCATION_STREAMS_BACKEND '${streamBackend}' (expected firestore|rtdb).`,
    );
  }
  logSafe('locstreams_init', { store: streamBackend });

  // D1 — FCM Admin Messaging (data-only). Always construct; send fails gracefully if misconfigured.
  // ORA_FCM_SENDER=none guarantees zero outbound FCM calls (local emulator dev).
  const fcmSender =
    (process.env.ORA_FCM_SENDER ?? '').trim() === 'none'
      ? createNullFcmSender()
      : createFirebaseFcmSender();
  logSafe('fcm_sender_init', {
    sender: (process.env.ORA_FCM_SENDER ?? '').trim() === 'none' ? 'null' : 'firebase',
  });

  let routingProvider: RoutingProvider | null = null;
  if ((process.env.ORA_ROUTING_PROVIDER ?? '').trim() === 'haversine') {
    // Local-dev only (zero-cost): straight-line distance, no external calls.
    routingProvider = new HaversineRoutingProvider();
    logSafe('routing_provider_init', { provider: 'haversine', configured: true });
  } else if (process.env.GOOGLE_MAPS_SERVER_KEY?.trim()) {
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
    tripLocationRtdb,
    redis: redisClient,
    streamStore,
    fcmSender,
    routingProvider,
    adaptiveFreshness,
    idleMergedCursor,
    pricingRulesCacheTtlMs,
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
      `ora-auth-service listening on :${port} project=${projectId} appCheck=${requireAppCheck} geo=${geoBackend} routing=${routingProvider != null} rtdb=${Boolean(process.env.FIREBASE_DATABASE_URL?.trim())}`,
    );
  });
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('Fatal startup error', err);
  process.exit(1);
});
