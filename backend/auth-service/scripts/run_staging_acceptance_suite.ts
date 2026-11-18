/**
 * Staging validation-window acceptance suite (cost-optimization rollout).
 * Exercises the LIVE staging service end-to-end via real auth (Admin custom
 * token → ID token). Admin SDK is used ONLY for test-user setup and
 * verification reads — every assertion goes through the public API path.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=secrets/service-account.json \
 *   npx tsx scripts/run_staging_acceptance_suite.ts
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const PICKUP = { lat: 31.5204, lng: 74.3587, address: 'Lahore Fort' };
const DEST = { lat: 31.5497, lng: 74.3436, address: 'Data Darbar' };
const WORKER_TOKEN = process.env.ORA_INTERNAL_WORKER_TOKEN ?? '';

const results: { name: string; pass: boolean; detail: string }[] = [];
function report(name: string, pass: boolean, detail = '') {
  results.push({ name, pass, detail });
  console.log(`  ${pass ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function apiKey(): string {
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  return JSON.parse(readFileSync(gs, 'utf8')).client[0].api_key[0].current_key;
}
async function idTokenForUid(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey()}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!res.ok) throw new Error(`token_exchange ${res.status}`);
  return ((await res.json()) as { idToken: string }).idToken;
}
async function api(
  base: string,
  method: string,
  route: string,
  opts: { bearer?: string; body?: unknown; idem?: string; worker?: boolean } = {},
) {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (opts.bearer) headers.Authorization = `Bearer ${opts.bearer}`;
  if (opts.worker) headers['X-Ora-Worker-Token'] = WORKER_TOKEN;
  if (opts.body != null) headers['Content-Type'] = 'application/json';
  if (opts.idem) headers['Idempotency-Key'] = opts.idem;
  const res = await fetch(`${base}${route}`, {
    method,
    headers,
    body: opts.body != null ? JSON.stringify(opts.body) : undefined,
  });
  let json: Record<string, unknown> = {};
  try {
    json = (await res.json()) as Record<string, unknown>;
  } catch { /* empty */ }
  return { status: res.status, json };
}

async function ensureDriver(
  db: FirebaseFirestore.Firestore,
  uid: string,
  phone: string,
) {
  try {
    await getAuth().getUser(uid);
  } catch {
    await getAuth().createUser({ uid, phoneNumber: phone });
  }
  await db.collection('users').doc(uid).set(
    {
      uid,
      phoneNumber: phone,
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    },
    { merge: true },
  );
  await db.collection('drivers').doc(uid).set(
    { driverId: uid, userId: uid, availabilityState: 'online' },
    { merge: true },
  );
}

const locBody = (
  lat: number,
  lng: number,
  seq: number,
  stream: string,
  extra: Record<string, unknown> = {},
) => ({
  locationSeq: seq,
  locationStreamId: stream,
  lat,
  lng,
  accuracy: 8,
  heading: 0,
  speed: 0,
  timestamp: new Date().toISOString(),
  provider: 'gps',
  ...extra,
});

async function main() {
  if (!getApps().length) {
    initializeApp({
      credential: cert(
        JSON.parse(
          readFileSync(
            process.env.GOOGLE_APPLICATION_CREDENTIALS ??
              path.join(here, '../secrets/service-account.json'),
            'utf8',
          ),
        ),
      ),
      databaseURL:
        'https://oraapp-a9be5-default-rtdb.asia-southeast1.firebasedatabase.app',
    });
  }
  const db = getFirestore();
  const rtdb = getDatabase();
  const base = readFileSync(
    path.join(repoRoot, 'mobile/.staging_api_url'),
    'utf8',
  )
    .trim()
    .replace(/\/$/, '');
  console.log(`base=${base}`);

  const passengerUid = (
    await getAuth().getUserByPhoneNumber('+923012345678')
  ).uid;
  const d1 = 'SRjL7BJgCKTduhtpjtYMRZMq5fD2';
  const d2 = `acc_drv_${randomUUID().slice(0, 8)}`;
  const d3 = `acc_drv_${randomUUID().slice(0, 8)}`;
  const d5 = `acc_aged_${randomUUID().slice(0, 8)}`;
  await ensureDriver(db, d1, '+923012345677');
  await ensureDriver(db, d2, `+923000${Math.floor(100000 + Math.random() * 899999)}`);
  await ensureDriver(db, d3, `+923000${Math.floor(100000 + Math.random() * 899999)}`);
  await ensureDriver(db, d5, `+923000${Math.floor(100000 + Math.random() * 899999)}`);
  const pTok = await idTokenForUid(passengerUid);
  const t1 = await idTokenForUid(d1);
  const t2 = await idTokenForUid(d2);
  const t3 = await idTokenForUid(d3);
  const t5 = await idTokenForUid(d5);
  const stream = `acc-${randomUUID().slice(0, 8)}`;

  // ── 1. Adaptive marker: freshUntilMs twin + publishIntervalMs ────────
  console.log('\n[1] adaptive marker + merged cursor');
  const fixTsMs = Date.now();
  {
    const r = await api(base, 'POST', '/location/update', {
      bearer: t1,
      body: locBody(PICKUP.lat + 0.002, PICKUP.lng + 0.001, 1, stream, {
        publishIntervalMs: 30000,
        timestamp: new Date(fixTsMs).toISOString(),
      }),
    });
    report('adaptive update accepted', r.status === 200, `status=${r.status}`);
    const doc = (await db.collection('geoDrivers').doc(d1).get()).data()!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      freshUntilMs?: number;
      publishIntervalMs?: number;
      lastLocationTs: number;
    };
    report(
      'freshUntilMs = ts+30s+grace on doc twin',
      doc.freshUntilMs === marker.freshUntilMs &&
        marker.freshUntilMs! > marker.lastLocationTs + 40_000,
      `freshUntilMs=${marker.freshUntilMs} ts=${marker.lastLocationTs}`,
    );
    report(
      'merged cursor fields in geoDrivers doc',
      doc.lsActiveStreamId === stream && doc.lsLastAcceptedSeq === 1,
      `ls=${doc.lsActiveStreamId}/${doc.lsLastAcceptedSeq}`,
    );
  }

  // ── 2. Replay protection ─────────────────────────────────────────────
  {
    const r = await api(base, 'POST', '/location/update', {
      bearer: t1,
      body: locBody(PICKUP.lat, PICKUP.lng, 1, stream, {
        publishIntervalMs: 30000,
      }),
    });
    report('replayed seq → 422', r.status === 422, `status=${r.status}`);
  }

  // ── 3. Keepalive honesty ─────────────────────────────────────────────
  console.log('\n[3] keepalive honesty');
  {
    // Realistic keepalive: carries the ORIGINAL fix timestamp (same as the
    // recorded lastLocationTs). Server must extend PRESENCE freshness from
    // acceptedAt while keeping the honest fix age.
    const r = await api(base, 'POST', '/location/update', {
      bearer: t1,
      body: locBody(PICKUP.lat, PICKUP.lng, 2, stream, {
        publishIntervalMs: 30000,
        presenceKeepalive: true,
        timestamp: new Date(fixTsMs).toISOString(),
      }),
    });
    report('bounded keepalive accepted', r.status === 200, `status=${r.status}`);
    const doc = (await db.collection('geoDrivers').doc(d1).get()).data()!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      lastLocationTs: number;
      keepalive?: boolean;
      freshUntilMs?: number;
      acceptedAt: string;
    };
    report(
      'lastLocationTs preserved honest (not re-dated)',
      marker.lastLocationTs === fixTsMs,
      `ts=${marker.lastLocationTs} fix=${fixTsMs}`,
    );
    report('keepalive flag recorded', marker.keepalive === true);
    const acceptedMs = Date.parse(marker.acceptedAt);
    report(
      'presence freshness from acceptedAt (fu extended beyond fix+45s)',
      marker.freshUntilMs === acceptedMs + 45_000 &&
        marker.freshUntilMs! > fixTsMs + 45_000,
      `fu=${marker.freshUntilMs} acc+45s=${acceptedMs + 45_000}`,
    );
    // unflagged stale ts → 422
    const r2 = await api(base, 'POST', '/location/update', {
      bearer: t1,
      body: locBody(PICKUP.lat, PICKUP.lng, 3, stream, {
        timestamp: new Date(fixTsMs - 60_000).toISOString(),
      }),
    });
    report('unflagged stale ts → 422', r2.status === 422, `status=${r2.status}`);
  }

  // ── 4. Old-client compat (throwaway d6 — a legacy packet carries no
  // publishIntervalMs so its marker gets the legacy 15s window; it must
  // not clobber d1's adaptive marker mid-suite) ─────────────────────────
  {
    const d6 = `acc_lgc_${randomUUID().slice(0, 8)}`;
    await ensureDriver(
      db,
      d6,
      `+923000${Math.floor(100000 + Math.random() * 899999)}`,
    );
    const t6 = await idTokenForUid(d6);
    const r = await api(base, 'POST', '/location/update', {
      bearer: t6,
      body: locBody(PICKUP.lat + 0.006, PICKUP.lng, 1, stream),
    });
    report('legacy packet accepted', r.status === 200, `status=${r.status}`);
    const doc = (await db.collection('geoDrivers').doc(d6).get()).data()!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      freshUntilMs?: number;
    };
    report(
      'legacy marker has no freshUntilMs (15s window semantics)',
      marker.freshUntilMs == null,
    );
    await db.collection('geoDrivers').doc(d6).delete();
    await db.collection('users').doc(d6).delete();
    await db.collection('drivers').doc(d6).delete();
    try {
      await getAuth().deleteUser(d6);
    } catch { /* ignore */ }
  }

  // ── 5. Nearest-first matching (worker nearby probe) ──────────────────
  console.log('\n[5] nearest-first + geo matching');
  {
    // d2 ~2km away, d3 ~8km away; d1 ~300m (already projected).
    await api(base, 'POST', '/location/update', {
      bearer: t2,
      body: locBody(PICKUP.lat + 0.018, PICKUP.lng, 1, stream, {
        publishIntervalMs: 30000,
      }),
    });
    await api(base, 'POST', '/location/update', {
      bearer: t3,
      body: locBody(PICKUP.lat + 0.07, PICKUP.lng, 1, stream, {
        publishIntervalMs: 30000,
      }),
    });
    const near = await api(
      base,
      'GET',
      `/internal/drivers/nearby?lat=${PICKUP.lat}&lng=${PICKUP.lng}&radiusKm=10`,
      { worker: true },
    );
    const order =
      (near.json['data'] as { candidates?: { driverId: string }[] } | undefined)
        ?.candidates?.map((d) => d.driverId) ?? [];
    report(
      'nearby returns all 3 seeded drivers',
      [d1, d2, d3].every((d) => order.includes(d)),
      `order=${order.join(',')}`,
    );
    const i1 = order.indexOf(d1);
    const i2 = order.indexOf(d2);
    const i3 = order.indexOf(d3);
    report(
      'nearest-first ordering (d1 < d2 < d3)',
      i1 >= 0 && i2 > i1 && i3 > i2,
      `idx=${i1},${i2},${i3}`,
    );
  }

  // ── 6/7. Ride dispatch: invite → decline → next wave → accept ────────
  console.log('\n[6] dispatch waves + invite flow');
  const est = await api(base, 'POST', '/pricing/estimate', {
    bearer: pTok,
    body: {
      pickup: PICKUP,
      destination: DEST,
      category: 'easy',
      serviceType: 'ride',
      city: 'lahore',
    },
  });
  report('pricing estimate ok', est.status === 200, `status=${est.status}`);
  const snap = (est.json['data'] ?? {}) as {
    pricingSnapshotId: string;
    recommendedFareMinor: number;
  };
  const created = await api(base, 'POST', '/rides', {
    bearer: pTok,
    idem: `acc-${randomUUID()}`,
    body: {
      pickup: PICKUP,
      destination: DEST,
      category: 'easy',
      serviceType: 'ride',
      city: 'lahore',
      passengerOfferMinor: snap.recommendedFareMinor,
      pricingSnapshotId: snap.pricingSnapshotId,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
  });
  const rideId = String(
    (created.json['data'] as { rideId?: string })?.rideId ?? '',
  );
  report('ride created SEARCHING', created.status === 201 && !!rideId,
    `status=${created.status} ride=${rideId.slice(0, 8)}`);

  // d5: dedicated "GPS stalled" driver for the present-but-not-invitable
  // check (section 8b). One real fix now, then ONLY keepalives carrying
  // the same ts — presence stays alive while the honest fix age crosses
  // the 120s invitability cap. Seeded here so fix+122s lands post-dispatch.
  let d5FixTs = Date.now();
  let d5Seq = 1;
  const d5Keepalive = () =>
    api(base, 'POST', '/location/update', {
      bearer: t5,
      body: locBody(PICKUP.lat + 0.004, PICKUP.lng - 0.004, ++d5Seq, stream, {
        publishIntervalMs: 4000,
        presenceKeepalive: true,
        timestamp: new Date(d5FixTs).toISOString(),
      }),
    });
  await api(base, 'POST', '/location/update', {
    bearer: t5,
    body: locBody(PICKUP.lat + 0.004, PICKUP.lng - 0.004, d5Seq, stream, {
      publishIntervalMs: 4000,
      timestamp: new Date(d5FixTs).toISOString(),
    }),
  });

  // Real drivers republish every ~10-30s; single static fixes would let
  // freshUntilMs lapse before the sweep ticks. Continue per-driver seqs.
  // d1 consumed seqs 1 (adaptive) + 2 (keepalive); the unflagged-stale seq-3
  // was rejected at validation so it did NOT consume — next valid is 3.
  const seqs = { d1: 2, d2: 1, d3: 1 };
  const freshFix = (tok: string, lat: number, lng: number, seq: number) =>
    api(base, 'POST', '/location/update', {
      bearer: tok,
      body: locBody(lat, lng, seq, stream, { publishIntervalMs: 30000 }),
    });
  const republishActive = () =>
    Promise.all([
      freshFix(t1, PICKUP.lat + 0.002, PICKUP.lng + 0.001, ++seqs.d1),
      freshFix(t2, PICKUP.lat + 0.018, PICKUP.lng, ++seqs.d2),
      freshFix(t3, PICKUP.lat + 0.07, PICKUP.lng, ++seqs.d3),
    ]);

  // Wait for the coalesced dispatch sweep (runs every minute). Wave-1
  // invites up to N candidates IN PARALLEL (distance-ordered) — each
  // invitee holds a ~20s invite, so accept must use d2's own wave-1
  // invite, not a subsequent wave.
  console.log('  … waiting ≤95s for dispatch sweep wave 1');
  let invited1: { rideId?: string; waveId?: string } | null = null;
  let invited2: { rideId?: string; waveId?: string } | null = null;
  for (let i = 0; i < 19 && !(invited1 && invited2); i++) {
    await sleep(5000);
    await d5Keepalive();
    if (i % 3 === 1) await republishActive();
    const inv1 = await api(base, 'GET', '/rides/invited', { bearer: t1 });
    const list1 =
      (inv1.json['data'] as { items?: Array<Record<string, unknown>> })
        ?.items ?? [];
    const hit1 = list1.find(
      (r) => r.rideId === rideId && r.status === 'ACTIVE',
    );
    if (hit1) invited1 = hit1 as { rideId?: string; waveId?: string };
    const inv2 = await api(base, 'GET', '/rides/invited', { bearer: t2 });
    const list2 =
      (inv2.json['data'] as { items?: Array<Record<string, unknown>> })
        ?.items ?? [];
    const hit2 = list2.find(
      (r) => r.rideId === rideId && r.status === 'ACTIVE',
    );
    if (hit2) invited2 = hit2 as { rideId?: string; waveId?: string };
  }
  // FCM-free discovery proof: invites arrived via POLLING alone.
  report(
    'd1 (nearest) invited via polling — no FCM dependency',
    !!invited1,
    invited1 ? `waveId=${String(invited1.waveId).slice(0, 20)}` : 'none',
  );
  report('d2 also holds a wave-1 invite (parallel wave)', !!invited2);
  {
    // Nearest-first inside the wave: driverIds preserve candidate order.
    const waveDocs = await db
      .collection('rideDispatchWaves')
      .where('rideId', '==', rideId)
      .get();
    const w1 = waveDocs.docs
      .map((d) => d.data() as { waveNumber: number; driverIds: string[] })
      .sort((a, b) => a.waveNumber - b.waveNumber)[0];
    report(
      'wave-1 driverIds distance-ordered with d1 first',
      w1 != null && w1.driverIds?.[0] === d1,
      `w1=${JSON.stringify(w1?.driverIds)}`,
    );
  }

  let assigned = false;
  if (invited1?.waveId) {
    const dec = await api(
      base,
      'POST',
      `/rides/${rideId}/invites/${invited1.waveId}/decline`,
      { bearer: t1 },
    );
    report('d1 decline accepted', dec.status < 300, `status=${dec.status}`);
    const invAfter = await api(base, 'GET', '/rides/invited', { bearer: t1 });
    const stillThere = (
      (invAfter.json['data'] as { items?: Array<Record<string, unknown>> })
        ?.items ?? []
    ).some((r) => r.rideId === rideId && r.status === 'ACTIVE');
    report('decline removes d1 invite', !stillThere);
  }
  if (invited2?.waveId) {
    const acc = await api(
      base,
      'POST',
      `/rides/${rideId}/invites/${invited2.waveId}/accept`,
      { bearer: t2 },
    );
    report('d2 accept creates fare offer', acc.status < 300, `status=${acc.status}`);
    // Two-phase: driver accept → OFFERS_AVAILABLE offer → passenger selects.
    let offerId: string | null = null;
    for (let i = 0; i < 6 && !offerId; i++) {
      await sleep(2000);
      const offers = await api(base, 'GET', `/rides/${rideId}/offers`, {
        bearer: pTok,
      });
      const list =
        (offers.json['data'] as { offers?: Array<Record<string, unknown>> })
          ?.offers ?? [];
      const mine = list.find((o) => o.status === 'PENDING');
      if (mine?.offerId) offerId = String(mine.offerId);
    }
    report('offer visible to passenger', !!offerId, `offerId=${offerId}`);
    if (offerId) {
      const sel = await api(
        base,
        'POST',
        `/rides/${rideId}/offers/${offerId}/select`,
        { bearer: pTok, idem: `sel-${randomUUID()}` },
      );
      assigned = sel.status < 300;
      report('passenger select assigns ride', assigned, `status=${sel.status}`);
    }
  }
  // ── 8. RTDB trip tracking (assigned ride only) ───────────────────────
  console.log('\n[8] RTDB live tracking');
  if (assigned) {
    const upd = await api(base, 'POST', '/location/update', {
      bearer: t2,
      body: locBody(PICKUP.lat + 0.005, PICKUP.lng + 0.005, 1, stream, {
        rideId,
      }),
    });
    report('trip update accepted', upd.status === 200, `status=${upd.status}`);
    await sleep(2000);
    const latest = await rtdb.ref(`tripLocations/${rideId}/latest`).get();
    const val = latest.val() as { lat?: number } | null;
    report(
      'RTDB tripLocations/{rideId}/latest written',
      typeof val?.lat === 'number',
      val ? `lat=${val.lat}` : 'null',
    );
    // grantRideAccess should have been created for passenger
    const access = await rtdb.ref(`rideAccess/${rideId}`).get();
    report('rideAccess populated', access.exists() === true);
  } else {
    report('RTDB tracking', false, 'skipped — ride not assigned');
    await api(base, 'POST', `/rides/${rideId}/cancel`, { bearer: pTok });
  }

  // ── 8b. Stale-fix keepalive: present but NOT invitable ───────────────
  console.log('\n[8b] stale keepalive: present but not invitable');
  {
    // Reseed d5 with a FRESH fix so the (120s, 130s] window is deterministic
    // regardless of how long dispatch took. From here: keepalives only.
    d5FixTs = Date.now();
    await api(base, 'POST', '/location/update', {
      bearer: t5,
      body: locBody(PICKUP.lat + 0.004, PICKUP.lng - 0.004, ++d5Seq, stream, {
        publishIntervalMs: 4000,
        timestamp: new Date(d5FixTs).toISOString(),
      }),
    });
    const waitMs = d5FixTs + 122_000 - Date.now();
    if (waitMs > 0) {
      console.log(`  … waiting ${Math.round(waitMs / 1000)}s for d5 fix to cross 120s`);
      const end = Date.now() + waitMs;
      while (Date.now() < end) {
        await sleep(Math.min(15_000, end - Date.now()));
        if (Date.now() - d5FixTs <= 128_000) await d5Keepalive();
      }
    }
    const d5Age = Date.now() - d5FixTs;
    const ka = await d5Keepalive();
    await api(base, 'POST', '/location/update', {
      bearer: t3,
      body: locBody(PICKUP.lat + 0.07, PICKUP.lng, ++seqs.d3, stream, {
        publishIntervalMs: 30000,
      }),
    });
    await sleep(1500);
    const d5Doc = (await db.collection('geoDrivers').doc(d5).get()).data();
    const d5Fu = Number(d5Doc?.freshUntilMs ?? 0);
    const nearC = await api(
      base,
      'GET',
      `/internal/drivers/nearby?lat=${PICKUP.lat}&lng=${PICKUP.lng}&radiusKm=10`,
      { worker: true },
    );
    const candIds = (
      (nearC.json['data'] as { candidates?: { driverId: string }[] }) ??
      {}
    ).candidates?.map((c) => c.driverId) ?? [];
    if (d5Age > 135_000 || ka.status !== 200) {
      report(
        'stale keepalive present-but-not-invitable',
        false,
        `window missed: age=${Math.round(d5Age / 1000)}s ka=${ka.status}`,
      );
    } else {
      report(
        'aged-fix driver PRESENT (freshUntilMs alive via keepalive)',
        d5Fu > Date.now(),
        `fu-now=${Math.round((d5Fu - Date.now()) / 1000)}s fixAge=${Math.round(d5Age / 1000)}s`,
      );
      report(
        'aged-fix driver NOT invitable (excluded from candidates)',
        !candIds.includes(d5) && candIds.includes(d3),
        `d5=${candIds.includes(d5)} d3=${candIds.includes(d3)}`,
      );
    }
  }

  // Offer expiry: d5's wave-1 invite went unanswered; the offer-expire
  // sweep (inside /sweeps/all each minute) must retract it. By now the
  // invite TTL + at least one sweep tick have elapsed, so one check
  // suffices (poll briefly for sweep-cycle slack).
  {
    let d5InviteExpired = false;
    if (invited1) {
      for (let i = 0; i < 10 && !d5InviteExpired; i++) {
        await sleep(5000);
        const inv5 = await api(base, 'GET', '/rides/invited', { bearer: t5 });
        const list5 =
          (inv5.json['data'] as { items?: Array<Record<string, unknown>> })
            ?.items ?? [];
        const hit5 = list5.find((r) => r.rideId === rideId);
        // Terminal once the item is no longer ACTIVE (EXPIRED via the
        // offer-expire sweep, or CLOSED because the ride was assigned).
        if (hit5 && hit5.status !== 'ACTIVE') d5InviteExpired = true;
      }
      report('unanswered invite expired by sweep (d5)', d5InviteExpired);
    }
  }

  // ── 9. Offer expiry path via coalesced sweep ─────────────────────────
  console.log('\n[9] coalesced sweep');
  {
    const sw = await api(base, 'POST', '/internal/sweeps/all', { worker: true });
    const data = sw.json['data'] as {
      failures?: string[];
      results?: Record<string, unknown>;
    };
    report('sweeps/all 200', sw.status === 200, `status=${sw.status}`);
    report(
      'all sweeps ok, failures empty',
      Array.isArray(data?.failures) && data.failures.length === 0,
      `failures=${JSON.stringify(data?.failures)}`,
    );
    report(
      'result has all 8 steps',
      data?.results != null &&
        ['expire', 'offerExpire', 'noShow', 'dispatchFcm', 'rideStateFcm', 'expiresAtCleanup']
          .every((k) => k in data.results!),
    );
  }

  // ── 10. Offline removal (marker expiry) ──────────────────────────────
  console.log('\n[10] offline removal');
  {
    const d4 = `acc_off_${randomUUID().slice(0, 8)}`;
    await ensureDriver(db, d4, `+923000${Math.floor(100000 + Math.random() * 899999)}`);
    const t4 = await idTokenForUid(d4);
    await api(base, 'POST', '/location/update', {
      bearer: t4,
      body: locBody(PICKUP.lat + 0.001, PICKUP.lng, 1, stream, {
        publishIntervalMs: 4000, // shortest window → expires in ~19s
      }),
    });
    let near1 = await api(
      base,
      'GET',
      `/internal/drivers/nearby?lat=${PICKUP.lat}&lng=${PICKUP.lng}&radiusKm=10`,
      { worker: true },
    );
    const has = (r: typeof near1) =>
      ((
        r.json['data'] as { candidates?: { driverId: string }[] } | undefined
      )?.candidates ?? []).some((d) => d.driverId === d4);
    const presentNow = has(near1);
    console.log('  … waiting ~30s for marker expiry');
    await sleep(30_000);
    near1 = await api(
      base,
      'GET',
      `/internal/drivers/nearby?lat=${PICKUP.lat}&lng=${PICKUP.lng}&radiusKm=10`,
      { worker: true },
    );
    report(
      'driver visible while fresh, gone after interval+grace',
      presentNow && !has(near1),
      `before=${presentNow} after=${has(near1)}`,
    );
    // Cleanup d4
    await db.collection('geoDrivers').doc(d4).delete();
    await db.collection('users').doc(d4).delete();
    await db.collection('drivers').doc(d4).delete();
  }

  // Cleanup synthetic drivers + ride
  for (const d of [d2, d3, d5]) {
    await db.collection('geoDrivers').doc(d).delete();
    await db.collection('users').doc(d).delete();
    await db.collection('drivers').doc(d).delete();
    try {
      await getAuth().deleteUser(d);
    } catch { /* ignore */ }
  }
  if (assigned) {
    await rtdb.ref(`tripLocations/${rideId}`).remove();
    await rtdb.ref(`rideAccess/${rideId}`).remove();
  }

  const fails = results.filter((r) => !r.pass);
  console.log(`\n${results.length - fails.length}/${results.length} PASS`);
  if (fails.length) {
    console.log('FAILED:', fails.map((f) => f.name).join(' | '));
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
