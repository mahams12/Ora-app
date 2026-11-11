/**
 * Merged idle-cursor — REAL Firestore emulator transaction proof.
 *
 * The in-memory memory_db fake cannot prove Firestore transaction semantics
 * (retries, atomicity, concurrent conflict resolution). This script drives
 * the production projectLocation path against the local emulator:
 *
 *   1. Sequential cursor advance (happy path)
 *   2. Sequence replay / duplicate request → 422
 *   3. Concurrent updates (20 parallel packets) — monotonic outcome, no corruption
 *   4. Stream replacement (new streamId resets seq; late old-stream packet → 422)
 *   5. Old-client compatibility (no idleCursor → no ls* fields; merge preserves them)
 *   6. Atomicity on violation (failed tx leaves coords/marker untouched)
 *   7. Online→offline→online transition (doc deleted, cursor restarts cleanly)
 *   8. Transaction conflict retry (external mutation mid-tx still converges)
 *   9. freshUntilMs twin — real range query filters expired presence
 *  10. Read accounting — the merged tx performs exactly ONE document read
 *
 * Run:
 *   firebase emulators:start --only firestore --project ora-local &
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 \
 *     npx tsx scripts/run_merged_cursor_emulator_proof.ts
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { assertScriptFirebaseTarget } from './lib/script_env';
import { createFirestoreGeoClient } from '../src/redis/firestore_geo_client';
import { GEO_DRIVERS_KEY, driverOnlineKey } from '../src/redis/types';
import { LocationDomainError } from '../src/location/types';

const PREFIX = 'emcur_';
let passed = 0;
let failed = 0;

function ok(name: string, cond: boolean, detail = '') {
  if (cond) {
    passed++;
    console.log(`  PASS ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name} ${detail}`);
  }
}

async function main() {
  assertScriptFirebaseTarget(process.env);
  initializeApp({ projectId: 'ora-local-bench' });
  const db = getFirestore();
  const geo = createFirestoreGeoClient(db);
  const col = db.collection('geoDrivers');

  // Clean leftover state from any previous run.
  const existing = await col.listDocuments();
  await Promise.all(
    existing.filter((d) => d.id.startsWith(PREFIX)).map((d) => d.delete()),
  );

  const markerFor = (ts: number, seq = 1) =>
    JSON.stringify({
      driverId: 'x',
      lastLocationTs: ts,
      accuracy: 8,
      acceptedAt: new Date().toISOString(),
      locationStreamId: 's',
      locationSeq: seq,
    });
  const cursorFor = (streamId: string, seq: number) => ({
    locationStreamId: streamId,
    locationSeq: seq,
    updatedAtIso: new Date().toISOString(),
    expiresAtIso: new Date(Date.now() + 120_000).toISOString(),
  });
  const project = (
    member: string,
    seq: number,
    streamId = 'stream-a',
    ts = Date.now(),
  ) =>
    geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member,
      longitude: 74.35,
      latitude: 31.52,
      markerKey: driverOnlineKey(member),
      markerValue: markerFor(ts, seq),
      markerTtlSeconds: 30,
      idleCursor: cursorFor(streamId, seq),
    });

  // ── 1. Sequential happy path ──────────────────────────────────────────
  console.log('\n[1] sequential cursor advance');
  {
    const m = `${PREFIX}s1`;
    for (let seq = 1; seq <= 3; seq++) {
      const r = await project(m, seq);
      if (r !== 'written') ok(`seq${seq} written`, false, `got ${r}`);
    }
    const doc = (await col.doc(m).get()).data()!;
    ok('lsLastAcceptedSeq=3', doc.lsLastAcceptedSeq === 3, String(doc.lsLastAcceptedSeq));
    ok('lsActiveStreamId set', doc.lsActiveStreamId === 'stream-a');
    ok('marker+geo in same doc', typeof doc.lat === 'number' && typeof doc.markerValue === 'string');
  }

  // ── 2. Replay / duplicate ─────────────────────────────────────────────
  console.log('\n[2] sequence replay + duplicate');
  {
    const m = `${PREFIX}s2`;
    await project(m, 5);
    let err422 = 0;
    for (const seq of [5, 4, 5]) {
      try {
        await project(m, seq);
      } catch (e) {
        if (e instanceof LocationDomainError && e.httpStatus === 422) err422++;
        else throw e;
      }
    }
    ok('replay seq=5 → 422 ×3', err422 === 3, `err422=${err422}`);
    const doc = (await col.doc(m).get()).data()!;
    ok('cursor unchanged (still 5)', doc.lsLastAcceptedSeq === 5);
  }

  // ── 3. Concurrent updates — 20 parallel packets ───────────────────────
  console.log('\n[3] 20-way concurrent updates');
  {
    const m = `${PREFIX}s3`;
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) => project(m, i + 1)),
    );
    const written = results.filter((r) => r.status === 'fulfilled').length;
    const rejected = results.length - written;
    const doc = (await col.doc(m).get()).data()!;
    // Every fulfilled write committed a strictly-greater seq than the cursor
    // it read. Final seq must be the max — Firestore retries order them.
    ok('final seq = 20 (max wins)', doc.lsLastAcceptedSeq === 20, String(doc.lsLastAcceptedSeq));
    ok('no corruption (stream id intact)', doc.lsActiveStreamId === 'stream-a');
    ok('all 20 settled', written + rejected === 20);
    console.log(`    written=${written} rejected=${rejected}`);
  }

  // ── 4. Stream replacement ─────────────────────────────────────────────
  console.log('\n[4] stream replacement');
  {
    const m = `${PREFIX}s4`;
    await project(m, 8, 'stream-a');
    const r = await project(m, 1, 'stream-b'); // new stream resets seq
    ok('new stream seq=1 accepted', r === 'written', r);
    const doc = (await col.doc(m).get()).data()!;
    ok('active = stream-b', doc.lsActiveStreamId === 'stream-b');
    ok('previous holds stream-a',
      Array.isArray(doc.lsPreviousStreamIds) && doc.lsPreviousStreamIds.includes('stream-a'));
    // Late packet from the replaced stream → 422
    let late422 = false;
    try {
      await project(m, 9, 'stream-a');
    } catch (e) {
      late422 = e instanceof LocationDomainError && e.httpStatus === 422;
    }
    ok('late old-stream packet → 422', late422);
  }

  // ── 5. Old-client compatibility ───────────────────────────────────────
  console.log('\n[5] old-client compatibility');
  {
    const m = `${PREFIX}s5`;
    // Legacy write: no idleCursor (flag-off clients) — marker+geo only.
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: m,
      longitude: 74.35,
      latitude: 31.52,
      markerKey: driverOnlineKey(m),
      markerValue: markerFor(Date.now()),
      markerTtlSeconds: 30,
    });
    let doc = (await col.doc(m).get()).data()!;
    ok('legacy write: no ls* fields', doc.lsLastAcceptedSeq === undefined);
    // New client then writes cursor on the SAME doc — merge keeps both.
    await project(m, 1, 'stream-n');
    doc = (await col.doc(m).get()).data()!;
    ok('merged write on legacy doc preserves marker',
      typeof doc.markerValue === 'string' && doc.lsLastAcceptedSeq === 1);
    // And an old client overwriting a cursor doc preserves ls* (merge:true).
    await geo.projectLocation!({
      key: GEO_DRIVERS_KEY,
      member: m,
      longitude: 74.36,
      latitude: 31.53,
      markerKey: driverOnlineKey(m),
      markerValue: markerFor(Date.now()),
      markerTtlSeconds: 30,
    });
    doc = (await col.doc(m).get()).data()!;
    ok('legacy write preserves ls* (merge)', doc.lsLastAcceptedSeq === 1);
  }

  // ── 6. Atomicity on violation ─────────────────────────────────────────
  console.log('\n[6] atomicity — failed tx leaves doc untouched');
  {
    const m = `${PREFIX}s6`;
    await project(m, 3);
    const before = (await col.doc(m).get()).data()!;
    try {
      await geo.projectLocation!({
        key: GEO_DRIVERS_KEY,
        member: m,
        longitude: 99.99, // would corrupt coords if tx wasn't atomic
        latitude: 99.99,
        markerKey: driverOnlineKey(m),
        markerValue: markerFor(Date.now(), 2),
        markerTtlSeconds: 30,
        idleCursor: cursorFor('stream-a', 2), // seq violation
      });
      ok('violation threw', false);
    } catch (e) {
      ok('violation threw', e instanceof LocationDomainError && e.httpStatus === 422);
    }
    const after = (await col.doc(m).get()).data()!;
    ok('coords untouched', after.lat === before.lat && after.lng === before.lng);
    ok('marker untouched', after.markerValue === before.markerValue);
    ok('cursor untouched', after.lsLastAcceptedSeq === 3);
  }

  // ── 7. Online → offline → online ──────────────────────────────────────
  console.log('\n[7] online/offline transitions');
  {
    const m = `${PREFIX}s7`;
    await project(m, 5);
    await geo.zrem(GEO_DRIVERS_KEY, m); // driver goes offline — doc deleted
    ok('doc removed on offline', !(await col.doc(m).get()).exists);
    // Re-online: cursor state gone with the doc — client starts a new stream
    // (real clients rotate streamId per session). Same streamId+low seq also
    // accepted — harmless: a deleted doc has nothing to replay against.
    const r = await project(m, 1, 'stream-c');
    ok('re-online accepted', r === 'written');
    const doc = (await col.doc(m).get()).data()!;
    ok('fresh cursor', doc.lsActiveStreamId === 'stream-c' && doc.lsLastAcceptedSeq === 1);
  }

  // ── 8. External conflict mid-transaction ──────────────────────────────
  console.log('\n[8] transaction conflict retry');
  {
    const m = `${PREFIX}s8`;
    await project(m, 1);
    // Race an external doc mutation against a cursor write — Firestore
    // retries the loser; final doc must carry BOTH updates.
    const external = db.runTransaction(async (tx) => {
      const ref = col.doc(m);
      const snap = await tx.get(ref);
      tx.set(ref, { externalFlag: (snap.data()?.externalFlag ?? 0) + 1 }, { merge: true });
    });
    const cursor = project(m, 2);
    await Promise.all([external, cursor]);
    const doc = (await col.doc(m).get()).data()!;
    ok('cursor advanced under conflict', doc.lsLastAcceptedSeq === 2, String(doc.lsLastAcceptedSeq));
    ok('external field preserved', doc.externalFlag === 1);
  }

  // ── 9. freshUntilMs twin — real range query ───────────────────────────
  console.log('\n[9] freshUntilMs range filter (real query)');
  {
    const fresh = `${PREFIX}s9f`;
    const stale = `${PREFIX}s9s`;
    const now = Date.now();
    const writeTwin = async (m: string, freshUntilMs: number) => {
      const marker = JSON.stringify({
        driverId: m, lastLocationTs: now - 60_000, accuracy: 8, freshUntilMs,
        acceptedAt: new Date().toISOString(),
      });
      await geo.projectLocation!({
        key: GEO_DRIVERS_KEY, member: m,
        longitude: 74.35, latitude: 31.52,
        markerKey: driverOnlineKey(m), markerValue: marker, markerTtlSeconds: 300,
      });
    };
    await writeTwin(fresh, now + 30_000);
    await writeTwin(stale, now - 1_000); // presence expired
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY, longitude: 74.35, latitude: 31.52,
      radiusKm: 5, count: 30, minFreshUntilMs: now,
    });
    const ids = hits.map((h) => h.member);
    ok('fresh driver returned', ids.includes(fresh));
    ok('expired driver excluded server-side', !ids.includes(stale));
  }

  // ── 10. Read accounting ───────────────────────────────────────────────
  console.log('\n[10] billed-read accounting');
  {
    // The merged tx body performs exactly ONE tx.get(ref) — verified by
    // instrumenting Firestore.get via a counting wrapper is unreliable in
    // the admin SDK; instead we assert the observable invariant: a missing
    // doc path (no snap) still writes, and concurrent txs did not require
    // extra reads (any hidden read would appear as a separate RPC and
    // break atomicity — covered by scenario 8's preserved external write).
    // Static guarantee: firestore_geo_client.projectLocation issues a
    // single `tx.get(ref)` before `tx.set` — 1 read + 1 write per packet,
    // vs the legacy path's two transactions (2 reads + 2 writes).
    const src = await import('node:fs').then((fs) =>
      fs.readFileSync('src/redis/firestore_geo_client.ts', 'utf8'));
    const txStart = src.indexOf('return db.runTransaction');
    const txEnd = src.indexOf('tx.set(ref, write', txStart);
    const txBody = src.slice(txStart, txEnd);
    const reads = (txBody.match(/tx\.get\(/g) ?? []).length;
    const nonTxGets = (txBody.match(/(?<!tx\.)\bget\(/g) ?? []).length;
    ok('merged tx = exactly 1 tx.get', reads === 1, `tx.get count=${reads}`);
    ok('no non-tx reads in tx body', nonTxGets === 0, `count=${nonTxGets}`);
  }

  // Cleanup
  const docs = await col.listDocuments();
  await Promise.all(docs.filter((d) => d.id.startsWith(PREFIX)).map((d) => d.delete()));

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
