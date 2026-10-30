/**
 * Controlled geo-store + N3 matching benchmark — local emulator only.
 *
 * Seeds geoDrivers/{driverId} docs + users/drivers eligibility docs at fleet
 * sizes [10, 100, 1000], then measures:
 *   - GPS projection write latency (RedisGeoProjectionService.projectAcceptedLocation)
 *   - findNearby match latency per size (bounding-box + filters)
 *   - N3 diagnostics: geoHits, user/driver reads, busy queries
 * Read/write counts feed the zero-cost cost model in the audit report.
 *
 * Requires FIRESTORE_EMULATOR_HOST — refuses otherwise (fail-closed).
 */
import { performance } from 'node:perf_hooks';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { createFirestoreGeoClient } from '../src/redis/firestore_geo_client';
import { createRtdbGeoClient } from '../src/rtdb/rtdb_geo_client';
import type { RedisGeoClient } from '../src/redis/types';
import { RedisGeoProjectionService } from '../src/redis/geo_projection';
import {
  NearbyDriversService,
  type N3NearbyDiagnostics,
} from '../src/drivers/nearby_service';
import {
  DriverEligibilityCache,
  LocationUpdateService,
  type LocationUpdateServiceOptions,
} from '../src/location/location_update_service';
import { createRtdbLocationStreamStore } from '../src/rtdb/rtdb_stream_store';

const PREFIX = 'geobench_';
const FLEET_SIZES = process.env.BENCH_FLEETS
  ? process.env.BENCH_FLEETS.split(',').map((s) => parseInt(s, 10))
  : [10, 100, 1000, 5000];

async function main(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) {
    throw new Error(
      'REFUSING_START: FIRESTORE_EMULATOR_HOST required (local benchmark only).',
    );
  }
  const geoBackend = (process.env.GEO_BACKEND ?? 'firestore').trim().toLowerCase();
  if (geoBackend === 'rtdb' && !process.env.FIREBASE_DATABASE_URL?.trim()) {
    throw new Error(
      'REFUSING_START: GEO_BACKEND=rtdb requires FIREBASE_DATABASE_URL (RTDB emulator).',
    );
  }
  if (geoBackend === 'rtdb' && !process.env.FIREBASE_DATABASE_EMULATOR_HOST?.trim()) {
    throw new Error(
      'REFUSING_START: GEO_BACKEND=rtdb benchmark requires FIREBASE_DATABASE_EMULATOR_HOST.',
    );
  }
  initializeApp({
    projectId: 'ora-local-bench',
    ...(process.env.FIREBASE_DATABASE_URL?.trim()
      ? { databaseURL: process.env.FIREBASE_DATABASE_URL.trim() }
      : {}),
  });
  const db = getFirestore();
  const geo: RedisGeoClient =
    geoBackend === 'rtdb'
      ? createRtdbGeoClient(getDatabase().ref('/'))
      : createFirestoreGeoClient(db);
  console.log(`geo_backend=${geoBackend}`);
  const proj = new RedisGeoProjectionService(geo);
  const nearby = new NearbyDriversService(db, geo);
  const nowMs = Date.now();

  // --- write-path benchmark: one accepted GPS packet ---
  // projectLocation with markerGuard = 1 tx read + 1 tx write (guard 'write')
  // or 1 tx read + 0 writes (guard 'skip' — stale packets rejected).
  {
    const uid = `${PREFIX}w0`;
    await db.collection('users').doc(uid).set({
      role: 'driver', driverStatus: 'approved', isActive: true, banned: false,
    });
    await db.collection('drivers').doc(uid).set({ availabilityState: 'online' });
    const lat: number[] = [];
    for (let i = 0; i < 30; i += 1) {
      const t0 = performance.now();
      await proj.projectAcceptedLocation({
        driverId: uid, lat: 31.5 + i * 1e-5, lng: 74.3 + i * 1e-5,
        accuracy: 8, locationStreamId: 'bench', locationSeq: i + 1,
        lastLocationTs: nowMs + i, acceptedAt: new Date(nowMs + i).toISOString(),
        homeCity: 'lahore', requestId: 'bench',
      });
      lat.push(performance.now() - t0);
    }
    lat.sort((a, b) => a - b);
    console.log(JSON.stringify({
      op: 'projection_write_tx_guard', n: lat.length,
      p50: lat[Math.floor(lat.length / 2)].toFixed(2),
      p95: lat[Math.floor(lat.length * 0.95)].toFixed(2),
      opsPerPacket: '1R+1W (skip=1R+0W)',
    }));
  }

  // --- full per-packet ops: LocationUpdateService.update end-to-end ---
  // Before optimization: users get + drivers get + locStream tx(1R+1W)
  //   + geo get + geo write = 4R+2W per idle packet.
  // After: eligibility cache folds users+drivers into a bounded-TTL hit;
  //   geo guard+write folded into one tx. = ~2R+2W steady-state.
  {
    const uid = `${PREFIX}w1`;
    await db.collection('users').doc(uid).set({
      role: 'driver', driverStatus: 'approved', isActive: true, banned: false,
    });
    await db.collection('drivers').doc(uid).set({ availabilityState: 'online' });
    const cache = new DriverEligibilityCache(15_000);
    const updateOpts: LocationUpdateServiceOptions = {
      eligibilityCache: cache,
    };
    if (geoBackend === 'rtdb') {
      updateOpts.streamStore = createRtdbLocationStreamStore(
        getDatabase().ref('/'),
      );
    }
    const service = new LocationUpdateService(db, proj, null, updateOpts);
    const caller = {
      uid, phoneNumber: '+92300', email: null, disabled: false,
    };
    const lat: number[] = [];
    for (let i = 0; i < 30; i += 1) {
      const t0 = performance.now();
      await service.update({
        caller: caller as never,
        body: {
          locationSeq: i + 1,
          locationStreamId: 'bench-stream',
          lat: 31.5 + i * 1e-5,
          lng: 74.3 + i * 1e-5,
          accuracy: 8,
          heading: 90,
          speed: 10,
          timestamp: new Date().toISOString(),
          provider: 'gps',
        },
        requestId: 'bench',
      });
      lat.push(performance.now() - t0);
    }
    lat.sort((a, b) => a - b);
    const stats = cache.stats();
    const implied =
      geoBackend === 'rtdb'
        ? `${(2 * stats.misses / lat.length).toFixed(2)}R+0W billed (cursor+geo on RTDB)`
        : `${(2 * stats.misses / lat.length + 2).toFixed(2)}R+2W (vs 4R+2W before)`;
    console.log(JSON.stringify({
      op: 'full_update_per_packet', n: lat.length,
      p50: lat[Math.floor(lat.length / 2)].toFixed(2),
      p95: lat[Math.floor(lat.length * 0.95)].toFixed(2),
      eligibilityCache: stats,
      impliedOpsPerPacket: implied,
    }));
  }

  // --- match-path benchmark per fleet size ---
  for (const n of FLEET_SIZES) {
    // Drivers spread uniformly in the 10 km box around pickup, fresh markers.
    const batch = Math.min(n, 400); // getAll/commit chunks
    for (let i = 0; i < n; i += 1) {
      const uid = `${PREFIX}d${i}`;
      await db.collection('users').doc(uid).set({
        role: 'driver', driverStatus: 'approved', isActive: true, banned: false,
      });
      await db.collection('drivers').doc(uid).set({
        availabilityState: 'online',
      });
      // Guard-free seed write (setup only — measured path uses the guard).
      await geo.projectLocation!({
        key: 'geo:drivers',
        member: uid,
        longitude: 74.3 + Math.floor(i / 40) * 0.02,
        latitude: 31.5 + (i % 40) * 0.02,
        markerKey: `driver:online:${uid}`,
        markerValue: JSON.stringify({
          driverId: uid,
          lastLocationTs: nowMs,
          accuracy: 8,
          city: 'lahore',
          locationStreamId: 'bench',
          locationSeq: 1,
          acceptedAt: new Date(nowMs).toISOString(),
        }),
        markerTtlSeconds: 300,
      });
      if (i % batch === batch - 1) process.stdout.write(`  seeded ${i + 1}/${n}\r`);
    }
    if (n >= 100) console.log();

    const runs = 3;
    const samples: number[] = [];
    let diagOut: { candidates: number; diagnostics: N3NearbyDiagnostics | null } | null =
      null;
    for (let r = 0; r < runs; r += 1) {
      const t0 = performance.now();
      let diag: N3NearbyDiagnostics | null = null;
      const res = await nearby.findNearby({
        query: { lat: 31.55, lng: 74.35, radiusKm: 10, limit: 100 },
        requestId: `bench-${n}-${r}`,
        nowMs,
        collectDiagnostics: (d) => {
          diag = d;
        },
      });
      samples.push(performance.now() - t0);
      diagOut = { candidates: res.candidates.length, diagnostics: diag };
    }
    samples.sort((a, b) => a - b);
    console.log(JSON.stringify({
      op: 'findNearby', fleet: n, runs,
      p50: samples[Math.floor(runs / 2)].toFixed(1),
      max: samples[runs - 1].toFixed(1),
      ...diagOut,
    }));
  }

  // Cleanup: delete bench docs (emulator-local only).
  const collections = ['users', 'drivers', 'geoDrivers', 'locationStreams'];
  for (const col of collections) {
    const snap = await db.collection(col).get();
    let deleted = 0;
    for (const d of snap.docs) {
      if (d.id.startsWith(PREFIX)) { await d.ref.delete(); deleted += 1; }
    }
    if (deleted) console.log(`cleaned ${col}: ${deleted}`);
  }
  if (geoBackend === 'rtdb') {
    for (const coll of ['geoPresence', 'locationStreams']) {
      const snap = await getDatabase().ref(coll).get();
      let removed = 0;
      for (const id of Object.keys(snap.val() ?? {})) {
        if (id.startsWith(PREFIX) || id.endsWith(`_${PREFIX}w1`) || id === `${PREFIX}w1`) {
          await getDatabase().ref(`${coll}/${id}`).remove();
          removed += 1;
        }
      }
      if (removed) console.log(`cleaned ${coll}: ${removed}`);
    }
  }
}

main().catch((e) => { console.error(String(e)); process.exit(1); });
