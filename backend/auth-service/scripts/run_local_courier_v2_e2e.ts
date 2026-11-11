/**
 * Zero-cost local E2E — Courier v2 (multi-stop Send Parcel + Buy & Deliver)
 * over HTTP against the emulator-backed auth-service. No cloud calls.
 *
 * Prereqs:
 *   1. firebase emulators running (auth:9099, firestore:8181, database:9000)
 *   2. ./scripts/run_local_device_backend.sh  (auth-service on :8080)
 *
 * Run:  ./node_modules/.bin/tsx scripts/run_local_courier_v2_e2e.ts
 * Exit 0 = all checks passed.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_PROJECT_ID ??= 'ora-app-d8112';
process.env.FIREBASE_DATABASE_URL ??=
  'https://ora-app-d8112-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';

const API = process.env.ORA_API ?? 'http://127.0.0.1:8080';
const AUTH_EMU =
  process.env.ORA_AUTH_BASE ??
  `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com`;
const AUTH_KEY = process.env.ORA_AUTH_KEY ?? 'emulator';
const WORKER = process.env.ORA_INTERNAL_WORKER_TOKEN ?? 'local-dev-worker-token-xx';

let passed = 0;
let failed = 0;
function check(name: string, cond: boolean, detail = '') {
  if (cond) {
    passed++;
    console.log(`  PASS ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name} ${detail}`);
  }
}

async function api(
  path: string,
  opts: {
    method?: string;
    token?: string;
    body?: unknown;
    worker?: boolean;
    idempotencyKey?: string;
  } = {},
): Promise<{ status: number; json: any }> {
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  if (opts.worker) headers['x-ora-worker-token'] = WORKER;
  if (opts.idempotencyKey) headers['idempotency-key'] = opts.idempotencyKey;
  const res = await fetch(`${API}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body == null ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function signUp(email: string): Promise<{ uid: string; idToken: string }> {
  const call = async (endpoint: string) => {
    const res = await fetch(`${AUTH_EMU}/v1/${endpoint}?key=${AUTH_KEY}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        email,
        password: 'localdev-pass-1',
        returnSecureToken: true,
      }),
    });
    return res.json();
  };
  let j = await call('accounts:signUp');
  if (j.error?.message === 'EMAIL_EXISTS') {
    j = await call('accounts:signInWithPassword');
  }
  if (!j.idToken) throw new Error(`signUp failed: ${JSON.stringify(j)}`);
  return { uid: j.localId, idToken: j.idToken };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function pollInvited(
  token: string,
  rideId: string,
  timeoutMs: number,
  keepAlive?: () => Promise<unknown>,
): Promise<any | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const r = await api('/v1/rides/invited', { token });
    const item = (r.json?.data?.items ?? []).find(
      (i: any) => i.rideId === rideId,
    );
    if (item) return item;
    if (keepAlive) await keepAlive().catch(() => undefined);
    await sleep(700);
  }
  return null;
}

const LHE = { lat: 31.5204, lng: 74.3587 };
const RUN = Date.now();
const INVITE_WAIT_MS = 20_000;

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const db = getFirestore();
  const rtdb = getDatabase();

  console.log('== setup: users, pricing rules, delivery config ==');
  const passenger = await signUp(`v2pax_${RUN}@local.dev`);
  const driver = await signUp(`v2drv_${RUN}@local.dev`);
  await api('/v1/auth/register', {
    method: 'POST',
    token: passenger.idToken,
    body: {},
    idempotencyKey: `register_${passenger.uid}`,
  });
  await db.collection('users').doc(driver.uid).set({
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  for (const cat of ['courier', 'buy_deliver']) {
    await db
      .collection('pricingRules')
      .doc(`lahore_${cat}`)
      .set(
        buildPricingRuleSeed({
          city: 'lahore',
          category: cat,
          version: 'v2-e2e-1',
          baseFare: 150,
          ratePerKm: 70,
          ratePerMin: 5,
          minFare: 150,
          maxFare: 8000,
          perStopFeeMinor: 5000,
          shoppingServiceFeeMinor: 10000,
        }),
      );
  }
  await db.collection('deliveryConfig').doc('global').set(
    {
      enableBuyDeliver: true,
      maxStops: 5,
      maxShoppingBudgetMinor: 300000,
      disputeWindowHours: 48,
      stopProximityMeters: 500,
      prohibitedItems: ['alcohol', 'tobacco', 'prescription'],
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
  const cfgRes = await api('/v1/delivery-config', { token: passenger.idToken });
  check('GET /v1/delivery-config', cfgRes.status === 200, JSON.stringify(cfgRes.json));

  const goOnline = await api('/v1/drivers/go-online', {
    method: 'POST',
    token: driver.idToken,
    body: {},
  });
  check('driver go-online', goOnline.status === 200, JSON.stringify(goOnline.json));

  let drvSeq = 1;
  const drvKeepAlive = () =>
    api('/v1/location/update', {
      method: 'POST',
      token: driver.idToken,
      body: {
        locationSeq: drvSeq++,
        locationStreamId: `v2-${driver.uid}-${RUN}`,
        lat: LHE.lat,
        lng: LHE.lng,
        accuracy: 10,
        heading: 0,
        speed: 0,
        provider: 'gps',
        timestamp: Date.now(),
      },
    });
  const loc = await drvKeepAlive();
  check('driver location update', loc.status === 200, JSON.stringify(loc.json));

  /** Shared dispatch → accept → select flow; returns assigned ride snapshot. */
  async function bookAndAssign(
    label: string,
    createBody: Record<string, unknown>,
  ): Promise<string | null> {
    const create = await api('/v1/rides', {
      method: 'POST',
      token: passenger.idToken,
      body: createBody,
      idempotencyKey: `${label}_create_${RUN}`,
    });
    check(
      `${label} booking created`,
      create.status === 201 || create.status === 200,
      JSON.stringify(create.json),
    );
    const rideId = create.json?.data?.rideId ?? create.json?.data?.id;
    if (!rideId) return null;
    const inv = await pollInvited(
      driver.idToken,
      rideId,
      INVITE_WAIT_MS,
      drvKeepAlive,
    );
    check(`${label} invite delivered`, !!inv);
    if (!inv) return null;
    const accept = await api(
      `/v1/rides/${rideId}/invites/${inv.waveId}/accept`,
      { method: 'POST', token: driver.idToken, body: {} },
    );
    check(
      `${label} accept → offer`,
      accept.status === 200 || accept.status === 201,
      JSON.stringify(accept.json),
    );
    const offers = await api(`/v1/rides/${rideId}/offers`, {
      token: passenger.idToken,
    });
    const offerId =
      offers.json?.data?.items?.[0]?.offerId ??
      offers.json?.data?.offers?.[0]?.offerId;
    const sel = await api(`/v1/rides/${rideId}/offers/${offerId}/select`, {
      method: 'POST',
      token: passenger.idToken,
      body: {},
      idempotencyKey: `${label}_sel_${rideId}`,
    });
    check(`${label} select → assigned`, sel.status === 200, JSON.stringify(sel.json));
    return rideId;
  }

  const getRide = async (rideId: string, token = passenger.idToken) =>
    (await api(`/v1/rides/${rideId}`, { token })).json?.data;

  const stopPost = async (
    rideId: string,
    seq: number,
    action: string,
    token: string,
    body: unknown = {},
    key?: string,
  ) => {
    // Mutation rate limiter is per-uid — pace stop actions like a real app
    // (network latency + human taps) instead of bursting them.
    await sleep(400);
    return api(`/v1/rides/${rideId}/stops/${seq}/${action}`, {
      method: 'POST',
      token,
      body,
      idempotencyKey: key ?? `${action}_${rideId}_${seq}_${RUN}`,
    });
  };

  const tripFix = (rideId: string, lat: number, lng: number) =>
    api('/v1/location/update', {
      method: 'POST',
      token: driver.idToken,
      body: {
        rideId,
        locationSeq: drvSeq++,
        locationStreamId: `v2-${driver.uid}-${RUN}`,
        lat,
        lng,
        accuracy: 8,
        heading: 45,
        speed: 5,
        provider: 'gps',
        timestamp: Date.now(),
      },
    });

  // ════════════════════════════════════════════════════════════════════
  // LEG A — Send Parcel v2: 3-stop code-free itinerary
  // ════════════════════════════════════════════════════════════════════
  console.log('== LEG A: Send Parcel v2 (PICKUP → PICKUP → DROPOFF, no OTP) ==');
  const p0 = LHE;
  const p1 = { lat: LHE.lat + 0.01, lng: LHE.lng + 0.01 };
  const d0 = { lat: LHE.lat + 0.03, lng: LHE.lng - 0.02 };

  const aEst = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: p0,
      destination: d0,
      city: 'lahore',
      category: 'courier',
      serviceType: 'courier',
      stops: [p0, p1, d0],
    },
  });
  check(
    'v2 multi-leg estimate 200 + legs',
    aEst.status === 200 &&
      Array.isArray(aEst.json?.data?.legs) &&
      aEst.json.data.legs.length === 2,
    JSON.stringify(aEst.json),
  );
  check(
    'v2 estimate carries stop surcharge',
    typeof aEst.json?.data?.stopFeesMinor === 'number',
    JSON.stringify(aEst.json?.data),
  );

  const rideA = await bookAndAssign('parcelv2', {
    pickup: p0,
    destination: d0,
    city: 'lahore',
    category: 'courier',
    serviceType: 'courier',
    paymentMethod: 'CASH',
    passengerCount: 1,
    pricingSnapshotId: aEst.json?.data?.pricingSnapshotId,
    passengerOfferMinor: aEst.json?.data?.recommendedFareMinor,
    parcel: {
      senderName: 'V2 Sender',
      senderPhone: '+923001112233',
      receiverName: 'V2 Receiver',
      receiverPhone: '+923004445566',
      parcelCategory: 'documents',
      size: 'SMALL',
      weightKg: 1,
      quantity: 1,
      description: 'V2 e2e documents',
    },
    stops: [
      { type: 'PICKUP', location: p0, label: 'Home', instructions: 'gate 2' },
      { type: 'PICKUP', location: p1, label: 'Office', instructions: 'reception' },
      { type: 'DROPOFF', location: d0, label: 'Recipient', instructions: 'call on arrival' },
    ],
  });

  if (rideA) {
    const a0 = await getRide(rideA);
    check(
      'v2 doc: protocol stamped + no OTP codes',
      a0?.courierProtocolVersion === 2 && a0?.otpCodes == null,
      JSON.stringify({ v: a0?.courierProtocolVersion, otp: a0?.otpCodes }),
    );
    check(
      'v2 doc: 3 stops projected, currentStopIndex=0',
      Array.isArray(a0?.stops) && a0.stops.length === 3 && a0.currentStopIndex === 0,
      JSON.stringify(a0?.stops?.length),
    );

    // GPS fix at stop 0 → evidence should record proximity.
    await tripFix(rideA, p0.lat, p0.lng);
    await sleep(400);

    const aArrive0 = await stopPost(rideA, 0, 'arrive', driver.idToken);
    check('stop0 arrive', aArrive0.status === 200, JSON.stringify(aArrive0.json));
    const aConf0 = await stopPost(rideA, 0, 'confirm', driver.idToken);
    check('stop0 confirm (collected)', aConf0.status === 200, JSON.stringify(aConf0.json));

    // Custody begins at first collected stop → instant cancel refused.
    const cancelCustody = await api(`/v1/rides/${rideA}/cancel`, {
      method: 'POST',
      token: passenger.idToken,
      body: { reason: 'changed mind' },
      idempotencyKey: `a_cancel_${rideA}`,
    });
    check(
      'cancel after custody refused',
      cancelCustody.status === 409 || cancelCustody.status === 400,
      JSON.stringify(cancelCustody.json),
    );

    const aMid = await getRide(rideA);
    check(
      'custody → RIDE_STARTED, evidence recorded',
      aMid?.state === 'RIDE_STARTED' &&
        Array.isArray(aMid?.evidence?.confirms) &&
        aMid.evidence.confirms.length >= 1,
      JSON.stringify({ state: aMid?.state, ev: aMid?.evidence }),
    );
    check(
      'GPS proximity recorded on confirm',
      typeof aMid?.evidence?.confirms?.[0]?.nearMeters === 'number',
      JSON.stringify(aMid?.evidence?.confirms?.[0]),
    );

    // Skip out-of-order confirm → conflict.
    const ooo = await stopPost(rideA, 2, 'confirm', driver.idToken);
    check(
      'out-of-order stop confirm rejected',
      ooo.status === 409,
      JSON.stringify(ooo.json),
    );

    await tripFix(rideA, p1.lat, p1.lng);
    await stopPost(rideA, 1, 'arrive', driver.idToken);
    const aConf1 = await stopPost(rideA, 1, 'confirm', driver.idToken);
    check('stop1 confirm', aConf1.status === 200, JSON.stringify(aConf1.json));

    await tripFix(rideA, d0.lat, d0.lng);
    await stopPost(rideA, 2, 'arrive', driver.idToken);
    const aConf2 = await stopPost(rideA, 2, 'confirm', driver.idToken);
    check(
      'final DROPOFF confirm → completed',
      aConf2.status === 200,
      JSON.stringify(aConf2.json),
    );
    const aDone = await getRide(rideA);
    check(
      'itinerary exhausted → RIDE_COMPLETED',
      aDone?.state === 'RIDE_COMPLETED',
      aDone?.state,
    );
    check(
      'settlement breakdown present (fare only, no shopping)',
      aDone?.settlement?.totalDueMinor != null &&
        aDone?.settlement?.deliveryFareMinor != null &&
        (aDone?.settlement?.shoppingTotalMinor ?? 0) === 0,
      JSON.stringify(aDone?.settlement),
    );

    // Driver reports cash collected; passenger acknowledges receipt.
    const aSettle = await api(`/v1/rides/${rideA}/settlement`, {
      method: 'POST',
      token: driver.idToken,
      body: { status: 'PAID' },
      idempotencyKey: `a_settle_${rideA}`,
    });
    check('driver settlement PAID → SETTLED', aSettle.status === 200, JSON.stringify(aSettle.json));
    const aAck = await api(`/v1/rides/${rideA}/acknowledge`, {
      method: 'POST',
      token: passenger.idToken,
      body: {},
      idempotencyKey: `a_ack_${rideA}`,
    });
    check('passenger acknowledge', aAck.status === 200, JSON.stringify(aAck.json));
    // Ack idempotent replay.
    const aAck2 = await api(`/v1/rides/${rideA}/acknowledge`, {
      method: 'POST',
      token: passenger.idToken,
      body: {},
      idempotencyKey: `a_ack_${rideA}`,
    });
    check('acknowledge idempotent', aAck2.status === 200, JSON.stringify(aAck2.json));
  }

  // ════════════════════════════════════════════════════════════════════
  // LEG B — Buy & Deliver: PICKUP → SHOP(quote→approve→purchase) → DROPOFF
  // ════════════════════════════════════════════════════════════════════
  console.log('== LEG B: Buy & Deliver (shop quote + approval + purchase) ==');
  const shop = { lat: LHE.lat - 0.015, lng: LHE.lng + 0.015 };
  const home = { lat: LHE.lat + 0.02, lng: LHE.lng + 0.005 };
  await drvKeepAlive();

  const bEst = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: p0,
      destination: home,
      city: 'lahore',
      category: 'buy_deliver',
      serviceType: 'buy_deliver',
      stops: [p0, shop, home],
    },
  });
  check('B&D estimate 200', bEst.status === 200, JSON.stringify(bEst.json));

  // Prohibited item rejected at booking.
  const banned = await api('/v1/rides', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: p0,
      destination: home,
      city: 'lahore',
      category: 'buy_deliver',
      serviceType: 'buy_deliver',
      paymentMethod: 'CASH',
      passengerCount: 1,
      stops: [
        { type: 'PICKUP', location: p0 },
        {
          type: 'SHOP',
          location: shop,
          items: [{ name: 'alcohol', qty: 1 }],
        },
        { type: 'DROPOFF', location: home },
      ],
      shopping: { totalBudgetMinor: 100000, attestationAccepted: true },
    },
    idempotencyKey: `bd_banned_${RUN}`,
  });
  check(
    'prohibited item rejected at booking',
    banned.status === 400,
    JSON.stringify(banned.json),
  );

  // Budget cap enforced.
  const overCap = await api('/v1/rides', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: p0,
      destination: home,
      city: 'lahore',
      category: 'buy_deliver',
      serviceType: 'buy_deliver',
      paymentMethod: 'CASH',
      passengerCount: 1,
      stops: [
        { type: 'PICKUP', location: p0 },
        { type: 'SHOP', location: shop, items: [{ name: 'Rice', qty: 1 }] },
        { type: 'DROPOFF', location: home },
      ],
      shopping: { totalBudgetMinor: 999999999, attestationAccepted: true },
    },
    idempotencyKey: `bd_overcap_${RUN}`,
  });
  check('budget cap enforced (Rs 3,000)', overCap.status === 400, JSON.stringify(overCap.json));

  const rideB = await bookAndAssign('buydeliver', {
    pickup: p0,
    destination: home,
    city: 'lahore',
    category: 'buy_deliver',
    serviceType: 'buy_deliver',
    paymentMethod: 'CASH',
    passengerCount: 1,
    pricingSnapshotId: bEst.json?.data?.pricingSnapshotId,
    passengerOfferMinor: bEst.json?.data?.recommendedFareMinor,
    stops: [
      { type: 'PICKUP', location: p0, label: 'Meet point' },
      {
        type: 'SHOP',
        location: shop,
        label: 'Al-Fatah',
        instructions: 'ask for fresh stock',
        items: [
          { name: 'Milk 1L', qty: 2 },
          { name: 'Bread', qty: 1 },
        ],
        shopBudgetMinor: 150000,
      },
      { type: 'DROPOFF', location: home, label: 'Home' },
    ],
    shopping: {
      totalBudgetMinor: 200000,
      attestationAccepted: true,
      paymentArrangement: 'RIDER_CASH',
    },
  });

  if (rideB) {
    const b0 = await getRide(rideB);
    check(
      'B&D doc: v2 + shopping block + no OTP',
      b0?.courierProtocolVersion === 2 &&
        b0?.otpCodes == null &&
        b0?.shopping?.totalBudgetMinor === 200000 &&
        b0?.shopping?.paymentArrangement === 'RIDER_CASH',
      JSON.stringify({ v: b0?.courierProtocolVersion, s: b0?.shopping }),
    );

    // Stop 0: pickup meet point.
    await tripFix(rideB, p0.lat, p0.lng);
    await stopPost(rideB, 0, 'arrive', driver.idToken);
    const bConf0 = await stopPost(rideB, 0, 'confirm', driver.idToken);
    check('B&D stop0 confirm', bConf0.status === 200, JSON.stringify(bConf0.json));

    // Stop 1: shop — arrive, quote, WAITING_APPROVAL, approve, purchase.
    await tripFix(rideB, shop.lat, shop.lng);
    const bArr1 = await stopPost(rideB, 1, 'arrive', driver.idToken);
    check('shop arrive', bArr1.status === 200, JSON.stringify(bArr1.json));

    const quote = await stopPost(
      rideB,
      1,
      'quote',
      driver.idToken,
      {
        items: [
          { name: 'Milk 1L', qty: 2, priceMinor: 30000 },
          { name: 'Bread', qty: 1, priceMinor: 12000 },
        ],
      },
    );
    check('driver quote submitted', quote.status === 200, JSON.stringify(quote.json));
    const bWait = await getRide(rideB);
    check(
      'stop → WAITING_APPROVAL + quote total',
      bWait?.stops?.[1]?.status === 'WAITING_APPROVAL' &&
        bWait?.stops?.[1]?.quote?.totalMinor === 72000,
      JSON.stringify(bWait?.stops?.[1]),
    );

    // Driver cannot confirm while waiting; passenger approves.
    const earlyConfirm = await stopPost(rideB, 1, 'confirm', driver.idToken);
    check(
      'purchase blocked while WAITING_APPROVAL',
      earlyConfirm.status === 409,
      JSON.stringify(earlyConfirm.json),
    );
    const approve = await stopPost(
      rideB,
      1,
      'quote-response',
      passenger.idToken,
      { decision: 'APPROVE' },
      `bd_approve_${rideB}`,
    );
    check('customer approves quote', approve.status === 200, JSON.stringify(approve.json));

    // Over-approved purchase rejected; exact-amount purchase accepted.
    const over = await stopPost(
      rideB,
      1,
      'confirm',
      driver.idToken,
      { purchaseTotalMinor: 80000 },
      `bd_over_${rideB}`,
    );
    check('purchase above approved rejected', over.status === 409 || over.status === 400, JSON.stringify(over.json));
    const buy = await stopPost(
      rideB,
      1,
      'confirm',
      driver.idToken,
      { purchaseTotalMinor: 72000 },
      `bd_buy_${rideB}`,
    );
    check('purchase confirmed at approved total', buy.status === 200, JSON.stringify(buy.json));
    const bSpent = await getRide(rideB);
    check(
      'shopping.spentMinor updated + settlement includes shopping',
      bSpent?.shopping?.spentMinor === 72000 &&
        bSpent?.settlement?.shoppingTotalMinor === 72000,
      JSON.stringify({ s: bSpent?.shopping, set: bSpent?.settlement }),
    );

    // Stop 2: dropoff → complete.
    await tripFix(rideB, home.lat, home.lng);
    await stopPost(rideB, 2, 'arrive', driver.idToken);
    const bConf2 = await stopPost(rideB, 2, 'confirm', driver.idToken);
    check('B&D delivered → completed', bConf2.status === 200, JSON.stringify(bConf2.json));
    const bDone = await getRide(rideB);
    // totalDue = agreed fare (already incl. serviceFee+stopFees) + shopping.
    check(
      'B&D COMPLETED + total = fare + shopping (fees inside fare)',
      bDone?.state === 'RIDE_COMPLETED' &&
        bDone?.settlement?.totalDueMinor ===
          (bDone?.settlement?.deliveryFareMinor ?? 0) +
            (bDone?.settlement?.shoppingTotalMinor ?? 0),
      JSON.stringify(bDone?.settlement),
    );

    // UNPAID report keeps settlement PENDING (driver-reported, not verified).
    const unpaid = await api(`/v1/rides/${rideB}/settlement`, {
      method: 'POST',
      token: driver.idToken,
      body: { status: 'UNPAID' },
      idempotencyKey: `bd_unpaid_${rideB}`,
    });
    check('driver reports UNPAID', unpaid.status === 200, JSON.stringify(unpaid.json));
    const bPend = await getRide(rideB);
    check(
      'settlement PENDING + driverReportedStatus=UNPAID (not verified)',
      bPend?.settlement?.status === 'PENDING' &&
        bPend?.settlement?.driverReportedStatus === 'UNPAID',
      JSON.stringify(bPend?.settlement),
    );

    // Dispute within the window.
    const dispute = await api(`/v1/rides/${rideB}/disputes`, {
      method: 'POST',
      token: passenger.idToken,
      body: { category: 'OVERCHARGE', message: 'charged more than agreed' },
      idempotencyKey: `bd_dispute_${rideB}`,
    });
    check('dispute created', dispute.status === 200 || dispute.status === 201, JSON.stringify(dispute.json));
    const bDisp = await getRide(rideB);
    check(
      'ride flagged DISPUTED + dispute doc written',
      bDisp?.settlement?.status === 'DISPUTED' || bDisp?.disputeStatus === 'OPEN',
      JSON.stringify({ set: bDisp?.settlement?.status, d: bDisp?.disputeStatus }),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // LEG C — Failure → retry reopens the failed stop
  // ════════════════════════════════════════════════════════════════════
  console.log('== LEG C: failed stop + retry-delivery reopens ==');
  const p2 = { lat: LHE.lat - 0.01, lng: LHE.lng - 0.01 };
  const d2 = { lat: LHE.lat + 0.04, lng: LHE.lng + 0.03 };
  await drvKeepAlive();
  const cEst = await api('/v1/pricing/estimate', {
    method: 'POST',
    token: passenger.idToken,
    body: {
      pickup: p2,
      destination: d2,
      city: 'lahore',
      category: 'courier',
      serviceType: 'courier',
      stops: [p2, d2],
    },
  });
  const rideC = await bookAndAssign('parcelv2fail', {
    pickup: p2,
    destination: d2,
    city: 'lahore',
    category: 'courier',
    serviceType: 'courier',
    paymentMethod: 'CASH',
    passengerCount: 1,
    pricingSnapshotId: cEst.json?.data?.pricingSnapshotId,
    passengerOfferMinor: cEst.json?.data?.recommendedFareMinor,
    parcel: {
      senderName: 'V2 Sender',
      senderPhone: '+923001112233',
      receiverName: 'V2 Receiver',
      receiverPhone: '+923004445566',
      parcelCategory: 'other',
      size: 'MEDIUM',
      weightKg: 3,
      quantity: 1,
      description: 'V2 e2e retry parcel',
    },
    stops: [
      { type: 'PICKUP', location: p2 },
      { type: 'DROPOFF', location: d2 },
    ],
  });
  if (rideC) {
    await tripFix(rideC, p2.lat, p2.lng);
    await stopPost(rideC, 0, 'arrive', driver.idToken);
    await stopPost(rideC, 0, 'confirm', driver.idToken);
    await tripFix(rideC, d2.lat, d2.lng);
    await stopPost(rideC, 1, 'arrive', driver.idToken);
    const fail = await stopPost(
      rideC,
      1,
      'fail',
      driver.idToken,
      { reason: 'RECEIVER_UNREACHABLE' },
      `c_fail_${rideC}`,
    );
    check('dropoff fail recorded', fail.status === 200, JSON.stringify(fail.json));
    const cFailed = await getRide(rideC);
    check(
      'itinerary exhausted via failure → failed state',
      /FAILED|DELIVERY_FAILED/i.test(cFailed?.state ?? ''),
      cFailed?.state,
    );
    const retry = await api(`/v1/rides/${rideC}/retry-delivery`, {
      method: 'POST',
      token: driver.idToken,
      body: {},
      idempotencyKey: `c_retry_${rideC}`,
    });
    check('driver retry-delivery', retry.status === 200, JSON.stringify(retry.json));
    const cRetried = await getRide(rideC);
    check(
      'failed stop reopened → PENDING + state reverted',
      cRetried?.stops?.[1]?.status === 'PENDING' &&
        /STARTED|ARRIVED|EN_ROUTE/i.test(cRetried?.state ?? ''),
      JSON.stringify({ s: cRetried?.stops?.[1]?.status, state: cRetried?.state }),
    );
    await tripFix(rideC, d2.lat, d2.lng);
    const rearrive = await stopPost(
      rideC,
      1,
      'arrive',
      driver.idToken,
      {},
      `c_rearrive_${rideC}`,
    );
    check('re-arrive reopened stop', rearrive.status === 200, JSON.stringify(rearrive.json));
    const redo = await stopPost(
      rideC,
      1,
      'confirm',
      driver.idToken,
      {},
      `c_redo_${rideC}`,
    );
    check('retried dropoff completes ride', redo.status === 200, JSON.stringify(redo.json));
  }

  console.log(`\n==== RESULT: ${passed} passed, ${failed} failed ====`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('E2E crashed:', e);
  process.exit(1);
});
