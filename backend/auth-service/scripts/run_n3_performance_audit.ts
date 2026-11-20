/**
 * N3 Nearby Driver — read-only performance baseline (local MemoryDb + MemoryRedis).
 * Does NOT change production code. Counts Redis/Firestore ops via thin wrappers.
 *
 * Usage: npm run audit:n3-performance
 */
import { performance } from 'node:perf_hooks';
import { NearbyDriversService } from '../src/drivers/nearby_service';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { createMemoryRedis } from '../src/redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  N3_REDIS_GEO_COUNT,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../src/redis/types';

type FirestoreMetrics = {
  usersDocGet: number;
  driversDocGet: number;
  ridesQueryGet: number;
  ridesDocsScanned: number;
};

type RedisMetrics = {
  georadius: number;
  get: number;
  geoCandidatesReturned: number;
};

function instrumentRedis(base: RedisGeoClient): {
  client: RedisGeoClient;
  metrics: RedisMetrics;
} {
  const metrics: RedisMetrics = {
    georadius: 0,
    get: 0,
    geoCandidatesReturned: 0,
  };
  return {
    metrics,
    client: {
      ...base,
      async georadius(input) {
        metrics.georadius += 1;
        const hits = await base.georadius(input);
        metrics.geoCandidatesReturned = hits.length;
        return hits;
      },
      async get(key) {
        metrics.get += 1;
        return base.get(key);
      },
      async mget(keys) {
        metrics.get += 1;
        return base.mget(keys);
      },
    },
  };
}

type MemDb = ReturnType<typeof memoryDb>;

function instrumentMemoryDb(base: MemDb): { db: MemDb; metrics: FirestoreMetrics } {
  const metrics: FirestoreMetrics = {
    usersDocGet: 0,
    driversDocGet: 0,
    ridesQueryGet: 0,
    ridesDocsScanned: 0,
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function wrapQuery(q: any, collection: string): any {
    const origGet = q.get.bind(q);
    return new Proxy(q, {
      get(target, prop) {
        if (prop === 'get') {
          return async () => {
            if (collection === 'rides') metrics.ridesQueryGet += 1;
            const snap = await origGet();
            if (collection === 'rides') {
              metrics.ridesDocsScanned += snap.docs.length;
            }
            return snap;
          };
        }
        const val = target[prop];
        if (typeof val === 'function' && prop !== 'get') {
          return (...args: unknown[]) =>
            wrapQuery(val.apply(target, args), collection);
        }
        return val;
      },
    });
  }

  const db: MemDb = {
    ...base,
    collection(name: string) {
      const col = base.collection(name);
      return {
        ...col,
        doc(id: string) {
          const ref = col.doc(id);
          return {
            ...ref,
            async get() {
              if (name === 'users') metrics.usersDocGet += 1;
              if (name === 'drivers') metrics.driversDocGet += 1;
              return ref.get();
            },
          };
        },
        where(field: string, op: string, value: unknown) {
          return wrapQuery(col.where(field, op, value), name);
        },
        orderBy(field: string, direction?: 'asc' | 'desc') {
          return wrapQuery(col.orderBy(field, direction), name);
        },
        limit(n: number) {
          return wrapQuery(col.limit(n), name);
        },
      };
    },
  };

  return { db, metrics };
}

const pickup = { lat: 31.52, lng: 74.35 };
const now = 1_700_000_000_000;

function seedApprovedOnline(
  db: MemDb,
  uid: string,
  availability: 'online' | 'offline' = 'online',
) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    availabilityState: availability,
  });
}

async function seedGeo(
  redis: RedisGeoClient,
  driverId: string,
  offsetIndex: number,
  marker?: Partial<DriverOnlineMarker>,
) {
  const lng = pickup.lng + 0.001 * (offsetIndex + 1);
  await redis.geoadd(GEO_DRIVERS_KEY, lng, pickup.lat, driverId);
  const full: DriverOnlineMarker = {
    driverId,
    lastLocationTs: now - 1000,
    accuracy: 8,
    city: null,
    locationStreamId: 'audit',
    locationSeq: 1,
    acceptedAt: new Date().toISOString(),
    ...marker,
  };
  await redis.set(
    driverOnlineKey(driverId),
    JSON.stringify(full),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

type ScenarioResult = {
  name: string;
  limit: number;
  geoCandidates: number;
  redisGeoradius: number;
  redisGet: number;
  firestoreUsers: number;
  firestoreDrivers: number;
  firestoreRidesQueries: number;
  firestoreRidesDocs: number;
  firestoreTotalReads: number;
  eligible: number;
  latencyMs: number;
  theoreticalWorstCase: {
    redisGet: number;
    firestoreReads: number;
  };
};

async function runScenario(input: {
  name: string;
  driverCount: number;
  limit?: number;
  seed?: (
    db: MemDb,
    redis: RedisGeoClient,
    i: number,
    id: string,
  ) => void | Promise<void>;
}): Promise<ScenarioResult> {
  const baseDb = memoryDb();
  const baseRedis = createMemoryRedis();
  const { db, metrics: fs } = instrumentMemoryDb(baseDb);
  const { client: redis, metrics: rs } = instrumentRedis(baseRedis);
  const limit = input.limit ?? 100;

  for (let i = 0; i < input.driverCount; i++) {
    const id = `d-${input.name}-${i}`;
    if (input.seed) {
      await input.seed(baseDb, baseRedis, i, id);
    } else {
      seedApprovedOnline(baseDb, id);
      await seedGeo(baseRedis, id, i);
    }
  }

  const svc = new NearbyDriversService(db as never, redis);
  const t0 = performance.now();
  const result = await svc.findNearby({
    query: { ...pickup, radiusKm: 25, limit },
    nowMs: now,
  });
  const latencyMs = performance.now() - t0;

  const firestoreTotalReads =
    fs.usersDocGet + fs.driversDocGet + fs.ridesDocsScanned;

  return {
    name: input.name,
    limit,
    geoCandidates: rs.geoCandidatesReturned,
    redisGeoradius: rs.georadius,
    redisGet: rs.get,
    firestoreUsers: fs.usersDocGet,
    firestoreDrivers: fs.driversDocGet,
    firestoreRidesQueries: fs.ridesQueryGet,
    firestoreRidesDocs: fs.ridesDocsScanned,
    firestoreTotalReads,
    eligible: result.candidates.length,
    latencyMs,
    theoreticalWorstCase: {
      redisGet: N3_REDIS_GEO_COUNT,
      firestoreReads: N3_REDIS_GEO_COUNT * 3,
    },
  };
}

async function main(): Promise<void> {
  const scenarios: ScenarioResult[] = [];

  scenarios.push(await runScenario({ name: '0-geo', driverCount: 0 }));
  scenarios.push(
    await runScenario({ name: '1-eligible', driverCount: 1, limit: 100 }),
  );
  scenarios.push(
    await runScenario({ name: '10-eligible', driverCount: 10, limit: 100 }),
  );
  scenarios.push(
    await runScenario({ name: '50-eligible', driverCount: 50, limit: 100 }),
  );
  scenarios.push(
    await runScenario({ name: '100-eligible', driverCount: 100, limit: 100 }),
  );
  scenarios.push(
    await runScenario({
      name: '100-geo-limit-30',
      driverCount: 100,
      limit: 30,
    }),
  );
  scenarios.push(
    await runScenario({
      name: '100-geo-all-offline-fs',
      driverCount: 100,
      limit: 100,
      seed: async (db, redis, i, id) => {
        seedApprovedOnline(db, id, 'offline');
        await seedGeo(redis, id, i);
      },
    }),
  );
  scenarios.push(
    await runScenario({
      name: '100-geo-no-markers',
      driverCount: 100,
      limit: 100,
      seed: async (db, redis, i, id) => {
        seedApprovedOnline(db, id);
        await redis.geoadd(
          GEO_DRIVERS_KEY,
          pickup.lng + 0.001 * (i + 1),
          pickup.lat,
          id,
        );
      },
    }),
  );

  console.log(
    JSON.stringify({ generatedAt: new Date().toISOString(), scenarios }, null, 2),
  );

  const worst = scenarios.find((s) => s.name === '100-geo-all-offline-fs');
  if (worst) {
    const hitWorst =
      worst.redisGet === 100 &&
      worst.firestoreTotalReads === 300 &&
      worst.redisGeoradius === 1;
    console.log(
      `\nWorst-case estimate check (100 offline after Redis pass): ${
        hitWorst ? 'CONFIRMED' : 'MISMATCH'
      }`,
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
