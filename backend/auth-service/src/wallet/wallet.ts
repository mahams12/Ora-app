import { randomUUID } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller, VendorType } from '../types';
import {
  DEFAULT_WALLET_CONFIG,
  PARTNER_ROLES,
  WALLET_ACCOUNTS,
  WALLET_CONFIG,
  WALLET_CONFIG_DOC,
  WALLET_LEDGER,
  WALLET_TOPUPS,
  WalletError,
  type LedgerType,
  type PartnerRole,
  type TopupStatus,
  type WalletAccount,
  type WalletConfig,
  type WalletLedgerEntry,
  type WalletTopup,
} from './types';

const USERS = 'users';
const MAX_TOPUP_POINTS = 500_000;
const MIN_TOPUP_POINTS = 50;
const LIST_LIMIT = 100;
const TOPUP_METHODS = new Set([
  'easypaisa',
  'jazzcash',
  'bank_transfer',
  'other',
]);

function err(code: string, httpStatus: number, message: string): never {
  throw new WalletError(code, httpStatus, message);
}

function isObj(v: unknown): v is Record<string, unknown> {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

// ---------------------------------------------------------------------------
// Config — walletConfig/global overrides defaults key-by-key; a missing or
// malformed doc always resolves to the launch defaults (10% / 1pt = Rs 1).
// ---------------------------------------------------------------------------

function validBps(v: unknown): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 10_000;
}

export function parseWalletConfig(raw: unknown): WalletConfig {
  const cfg = DEFAULT_WALLET_CONFIG;
  if (!isObj(raw)) return cfg;
  const minorPerPoint =
    typeof raw.minorPerPoint === 'number' &&
    Number.isInteger(raw.minorPerPoint) &&
    raw.minorPerPoint >= 1 &&
    raw.minorPerPoint <= 100_000
      ? raw.minorPerPoint
      : cfg.minorPerPoint;
  const bps = { ...cfg.commissionBps };
  if (isObj(raw.commissionBps)) {
    for (const role of PARTNER_ROLES) {
      const v = raw.commissionBps[role];
      if (validBps(v)) bps[role] = v;
    }
  }
  const lowBalanceWarnMinor =
    typeof raw.lowBalanceWarnMinor === 'number' &&
    Number.isInteger(raw.lowBalanceWarnMinor) &&
    raw.lowBalanceWarnMinor >= 0
      ? raw.lowBalanceWarnMinor
      : cfg.lowBalanceWarnMinor;
  return { minorPerPoint, commissionBps: bps, lowBalanceWarnMinor };
}

/**
 * Reads the configured commission bps for `role` inside a transaction.
 * Used by ride assignment to enforce fee-policy/commission mutual
 * exclusion (SUPERSEDED_BY_COMMISSION) — a driver must never be charged by
 * both mechanisms.
 */
export async function walletCommissionBpsInsideTx(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  role: PartnerRole,
): Promise<number> {
  return (await loadConfig(db, tx)).commissionBps[role];
}

async function loadConfig(
  db: Firestore,
  tx?: FirebaseFirestore.Transaction,
): Promise<WalletConfig> {
  const ref = db.collection(WALLET_CONFIG).doc(WALLET_CONFIG_DOC);
  const snap = tx ? await tx.get(ref) : await ref.get();
  return parseWalletConfig(snap.exists ? snap.data() : null);
}

// ---------------------------------------------------------------------------
// Partner gate — one wallet per UID, shared by every approved partner role.
// ---------------------------------------------------------------------------

/** Returns the caller's approved partner roles; 403 when they hold none. */
export async function approvedPartnerRoles(
  db: Firestore,
  caller: AuthenticatedCaller,
): Promise<PartnerRole[]> {
  const snap = await db.collection(USERS).doc(caller.uid).get();
  if (!snap.exists) {
    err('USER_NOT_FOUND', 404, 'User profile does not exist.');
  }
  const data = snap.data() ?? {};
  if (data.isActive === false || data.banned === true) {
    err('ACCOUNT_DISABLED', 403, 'This account is disabled.');
  }
  const roles: PartnerRole[] = [];
  if (data.driverStatus === 'approved') roles.push('driver');
  const apps = (data.vendorApplications ?? {}) as Record<
    string,
    { status?: unknown }
  >;
  for (const type of ['cargo', 'rental', 'service'] as VendorType[]) {
    if (apps[type]?.status === 'approved') roles.push(type);
  }
  if (roles.length === 0) {
    err(
      'NOT_A_PARTNER',
      403,
      'The partner wallet is only available to approved ORA partners.',
    );
  }
  return roles;
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

function toAccount(uid: string, data: Record<string, unknown>): WalletAccount {
  return {
    userId: String(data.userId ?? uid),
    balanceMinor: Number(data.balanceMinor ?? 0),
    currency: String(data.currency ?? 'PKR'),
    createdAt: String(data.createdAt ?? ''),
    updatedAt: String(data.updatedAt ?? ''),
    version: Number(data.version ?? 0),
  };
}

function toLedger(id: string, data: Record<string, unknown>): WalletLedgerEntry {
  return {
    entryId: String(data.entryId ?? id),
    accountId: String(data.accountId ?? ''),
    userId: String(data.userId ?? ''),
    type: data.type as LedgerType,
    pointsDelta: Number(data.pointsDelta ?? 0),
    amountMinor: Number(data.amountMinor ?? 0),
    ...(typeof data.sourceType === 'string'
      ? { sourceType: data.sourceType as WalletLedgerEntry['sourceType'] }
      : {}),
    ...(typeof data.sourceId === 'string' ? { sourceId: data.sourceId } : {}),
    ...(typeof data.role === 'string'
      ? { role: data.role as PartnerRole }
      : {}),
    ...(typeof data.grossMinor === 'number'
      ? { grossMinor: data.grossMinor }
      : {}),
    ...(typeof data.commissionBps === 'number'
      ? { commissionBps: data.commissionBps }
      : {}),
    balanceAfterMinor: Number(data.balanceAfterMinor ?? 0),
    ...(typeof data.paymentMethod === 'string'
      ? { paymentMethod: data.paymentMethod }
      : {}),
    ...(typeof data.reference === 'string' ? { reference: data.reference } : {}),
    description: String(data.description ?? ''),
    status: 'POSTED',
    idempotencyKey: String(data.idempotencyKey ?? ''),
    createdAt: String(data.createdAt ?? ''),
  };
}

function toTopup(id: string, data: Record<string, unknown>): WalletTopup {
  return {
    topupId: String(data.topupId ?? id),
    userId: String(data.userId ?? ''),
    kind: data.kind === 'debit' ? 'debit' : 'credit',
    points: Number(data.points ?? 0),
    amountMinor: Number(data.amountMinor ?? 0),
    method: String(data.method ?? ''),
    ...(typeof data.reference === 'string' ? { reference: data.reference } : {}),
    status: data.status as TopupStatus,
    ...(typeof data.ledgerEntryId === 'string'
      ? { ledgerEntryId: data.ledgerEntryId }
      : {}),
    idempotencyKey: String(data.idempotencyKey ?? ''),
    createdAt: String(data.createdAt ?? ''),
    ...(typeof data.resolvedAt === 'string'
      ? { resolvedAt: data.resolvedAt }
      : {}),
    ...(typeof data.resolvedBy === 'string'
      ? { resolvedBy: data.resolvedBy }
      : {}),
  };
}

export interface WalletSnapshot {
  account: WalletAccount;
  points: number;
  config: WalletConfig;
  roles: PartnerRole[];
  lowBalance: boolean;
  /** True while balance < 0 — partner cannot accept new work until topped up. */
  acceptBlocked: boolean;
}

/** Lazily creates the wallet on first read — balance starts at zero. */
export async function getWallet(
  db: Firestore,
  caller: AuthenticatedCaller,
  now: Date,
): Promise<WalletSnapshot> {
  const roles = await approvedPartnerRoles(db, caller);
  const config = await loadConfig(db);
  const ref = db.collection(WALLET_ACCOUNTS).doc(caller.uid);
  const account = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      const nowIso = now.toISOString();
      const fresh: WalletAccount = {
        userId: caller.uid,
        balanceMinor: 0,
        currency: 'PKR',
        createdAt: nowIso,
        updatedAt: nowIso,
        version: 1,
      };
      tx.set(ref, fresh as unknown as Record<string, unknown>);
      return fresh;
    }
    return toAccount(caller.uid, snap.data() ?? {});
  });
  return {
    account,
    points: Math.floor(account.balanceMinor / config.minorPerPoint),
    config,
    roles,
    lowBalance:
      account.balanceMinor < config.lowBalanceWarnMinor &&
      account.balanceMinor >= 0,
    acceptBlocked: account.balanceMinor < 0,
  };
}

export async function listLedger(
  db: Firestore,
  caller: AuthenticatedCaller,
  opts: { limit?: number },
): Promise<WalletLedgerEntry[]> {
  await approvedPartnerRoles(db, caller);
  const snap = await db
    .collection(WALLET_LEDGER)
    .where('accountId', '==', caller.uid)
    .orderBy('createdAt', 'desc')
    .limit(Math.min(opts.limit ?? 50, LIST_LIMIT))
    .get();
  return snap.docs.map((d) => toLedger(d.id, d.data()));
}

export async function listTopups(
  db: Firestore,
  caller: AuthenticatedCaller,
  opts: { limit?: number },
): Promise<WalletTopup[]> {
  await approvedPartnerRoles(db, caller);
  const snap = await db
    .collection(WALLET_TOPUPS)
    .where('userId', '==', caller.uid)
    .orderBy('createdAt', 'desc')
    .limit(Math.min(opts.limit ?? 50, LIST_LIMIT))
    .get();
  return snap.docs.map((d) => toTopup(d.id, d.data()));
}

// ---------------------------------------------------------------------------
// Top-ups — PENDING only. Points never credit from a client request; an
// internal/admin resolution (standing in for the PSP webhook) posts the
// ledger entry. Idempotent per (uid, idempotencyKey).
// ---------------------------------------------------------------------------

export async function createTopup(
  db: Firestore,
  caller: AuthenticatedCaller,
  payload: unknown,
  idempotencyKey: string,
  now: Date,
): Promise<WalletTopup> {
  await approvedPartnerRoles(db, caller);
  if (!isObj(payload)) {
    err('VALIDATION_ERROR', 400, 'Body must be an object.');
  }
  const points = payload.points;
  if (
    typeof points !== 'number' ||
    !Number.isInteger(points) ||
    points < MIN_TOPUP_POINTS ||
    points > MAX_TOPUP_POINTS
  ) {
    err(
      'VALIDATION_ERROR',
      400,
      `points must be an integer ${MIN_TOPUP_POINTS}–${MAX_TOPUP_POINTS}.`,
    );
  }
  const method = payload.method;
  if (
    typeof method !== 'string' ||
    !TOPUP_METHODS.has(method.trim().toLowerCase())
  ) {
    err(
      'VALIDATION_ERROR',
      400,
      `method must be one of: ${[...TOPUP_METHODS].join(', ')}.`,
    );
  }
  const kind = payload.kind === 'debit' ? 'debit' : 'credit';
  const reference =
    typeof payload.reference === 'string' &&
    payload.reference.trim().length > 0 &&
    payload.reference.trim().length <= 120
      ? payload.reference.trim()
      : undefined;

  const config = await loadConfig(db);
  const amountMinor = points * config.minorPerPoint;
  const nowIso = now.toISOString();

  return await db.runTransaction(async (tx) => {
    // Idempotency: same key returns the original pending/credited request.
    const existing = await tx.get(
      db
        .collection(WALLET_TOPUPS)
        .where('userId', '==', caller.uid)
        .where('idempotencyKey', '==', idempotencyKey)
        .limit(1),
    );
    if (!existing.empty) {
      const doc = existing.docs[0];
      return toTopup(doc.id, doc.data());
    }
    const id = `topup-${randomUUID()}`;
    const topup: WalletTopup = {
      topupId: id,
      userId: caller.uid,
      kind,
      points,
      amountMinor,
      method: method.trim().toLowerCase(),
      ...(reference ? { reference } : {}),
      status: 'PENDING',
      idempotencyKey,
      createdAt: nowIso,
    };
    tx.set(
      db.collection(WALLET_TOPUPS).doc(id),
      topup as unknown as Record<string, unknown>,
    );
    return topup;
  });
}

/** Internal/admin resolution — the only path that moves points for a top-up. */
export async function resolveTopup(
  db: Firestore,
  topupId: string,
  action: 'approve' | 'reject',
  resolvedBy: string,
  now: Date,
): Promise<WalletTopup> {
  const topupRef = db.collection(WALLET_TOPUPS).doc(topupId);
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(topupRef);
    if (!snap.exists) {
      err('TOPUP_NOT_FOUND', 404, 'Top-up request not found.');
    }
    const topup = toTopup(snap.id, snap.data() ?? {});
    if (topup.status !== 'PENDING') {
      // Already resolved — idempotent replay returns the same record.
      return topup;
    }
    const nowIso = now.toISOString();
    if (action === 'reject') {
      const rejected = {
        ...topup,
        status: 'REJECTED' as TopupStatus,
        resolvedAt: nowIso,
        resolvedBy,
      };
      tx.update(topupRef, {
        status: 'REJECTED',
        resolvedAt: nowIso,
        resolvedBy,
      });
      return rejected;
    }
    // Approve — post the ledger entry and move the balance atomically.
    const accountRef = db.collection(WALLET_ACCOUNTS).doc(topup.userId);
    const accountSnap = await tx.get(accountRef);
    const account = accountSnap.exists
      ? toAccount(topup.userId, accountSnap.data() ?? {})
      : ({
          userId: topup.userId,
          balanceMinor: 0,
          currency: 'PKR',
          createdAt: nowIso,
          updatedAt: nowIso,
          version: 0,
        } satisfies WalletAccount);

    const isDebit = topup.kind === 'debit';
    if (isDebit && account.balanceMinor < topup.amountMinor) {
      err(
        'INSUFFICIENT_BALANCE',
        409,
        'Wallet balance cannot cover this withdrawal.',
      );
    }
    const deltaMinor = isDebit ? -topup.amountMinor : topup.amountMinor;
    const deltaPoints = isDebit ? -topup.points : topup.points;
    const balanceAfterMinor = account.balanceMinor + deltaMinor;
    const entryId = isDebit ? `withdrawal-${topup.topupId}` : `topup-${topup.topupId}`;
    const entry: WalletLedgerEntry = {
      entryId,
      accountId: topup.userId,
      userId: topup.userId,
      type: isDebit ? 'WITHDRAWAL_DEBIT' : 'TOPUP_CREDIT',
      pointsDelta: deltaPoints,
      amountMinor: deltaMinor,
      sourceType: isDebit ? 'withdrawal' : 'topup',
      sourceId: topup.topupId,
      balanceAfterMinor,
      paymentMethod: topup.method,
      ...(topup.reference ? { reference: topup.reference } : {}),
      description: isDebit
        ? `Withdrawal ${topup.points} points via ${topup.method}`
        : `Top-up ${topup.points} points via ${topup.method}`,
      status: 'POSTED',
      idempotencyKey: topup.idempotencyKey,
      createdAt: nowIso,
    };
    tx.set(
      db.collection(WALLET_LEDGER).doc(entryId),
      entry as unknown as Record<string, unknown>,
    );
    tx.set(accountRef, {
      userId: topup.userId,
      balanceMinor: balanceAfterMinor,
      currency: 'PKR',
      createdAt: account.createdAt || nowIso,
      updatedAt: nowIso,
      version: account.version + 1,
    });
    tx.update(topupRef, {
      status: 'CREDITED',
      ledgerEntryId: entryId,
      resolvedAt: nowIso,
      resolvedBy,
    });
    return {
      ...topup,
      status: 'CREDITED' as TopupStatus,
      ledgerEntryId: entryId,
      resolvedAt: nowIso,
      resolvedBy,
    };
  });
}

// ---------------------------------------------------------------------------
// Commission — charged inside the completion transaction of a ride or
// marketplace booking, so settlement is atomic with the status change.
// The ledger doc id is deterministic (`commission-{type}-{id}`) making a
// retried completion write the same entry — exactly-once by construction.
// ---------------------------------------------------------------------------

export interface CommissionCharge {
  entryId: string;
  commissionPoints: number;
  commissionMinor: number;
  grossMinor: number;
  bps: number;
  balanceAfterMinor: number;
}

/**
 * Reads walletConfig + walletAccount inside `tx` FIRST (Firestore requires
 * reads before writes), then writes the ledger entry + updated balance.
 * Floor rounding per approved policy: commission points =
 * floor(grossMinor × bps / 10000 / minorPerPoint). Negative balances are
 * allowed — settlement never blocks a completion.
 */
export async function chargeCommissionInsideTx(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  input: {
    uid: string;
    role: PartnerRole;
    sourceType: 'ride' | 'booking';
    sourceId: string;
    /** Gross completed amount in minor units (paisa). */
    grossMinor: number;
    description: string;
  },
  now: Date,
): Promise<CommissionCharge | null> {
  if (
    typeof input.grossMinor !== 'number' ||
    !Number.isInteger(input.grossMinor) ||
    input.grossMinor <= 0
  ) {
    return null; // Nothing completed/charged — no commission.
  }
  const config = await loadConfig(db, tx);
  const bps = config.commissionBps[input.role];
  if (bps <= 0) return null;
  const commissionMinorRaw = Math.floor(
    (input.grossMinor * bps) / 10_000,
  );
  const commissionPoints = Math.floor(
    commissionMinorRaw / config.minorPerPoint,
  );
  if (commissionPoints <= 0) return null;
  const commissionMinor = commissionPoints * config.minorPerPoint;

  const accountRef = db.collection(WALLET_ACCOUNTS).doc(input.uid);
  const accountSnap = await tx.get(accountRef);
  const nowIso = now.toISOString();
  const account = accountSnap.exists
    ? toAccount(input.uid, accountSnap.data() ?? {})
    : ({
        userId: input.uid,
        balanceMinor: 0,
        currency: 'PKR',
        createdAt: nowIso,
        updatedAt: nowIso,
        version: 0,
      } satisfies WalletAccount);
  const balanceAfterMinor = account.balanceMinor - commissionMinor;
  const entryId = `commission-${input.sourceType}-${input.sourceId}`;
  const entry: WalletLedgerEntry = {
    entryId,
    accountId: input.uid,
    userId: input.uid,
    type: 'COMMISSION_DEBIT',
    pointsDelta: -commissionPoints,
    amountMinor: -commissionMinor,
    sourceType: input.sourceType,
    sourceId: input.sourceId,
    role: input.role,
    grossMinor: input.grossMinor,
    commissionBps: bps,
    balanceAfterMinor,
    description: input.description,
    status: 'POSTED',
    idempotencyKey: entryId,
    createdAt: nowIso,
  };
  tx.set(
    db.collection(WALLET_LEDGER).doc(entryId),
    entry as unknown as Record<string, unknown>,
  );
  tx.set(accountRef, {
    userId: input.uid,
    balanceMinor: balanceAfterMinor,
    currency: 'PKR',
    createdAt: account.createdAt || nowIso,
    updatedAt: nowIso,
    version: account.version + 1,
  });
  return {
    entryId,
    commissionPoints,
    commissionMinor,
    grossMinor: input.grossMinor,
    bps,
    balanceAfterMinor,
  };
}

/**
 * Eligibility gate for accepting new work. A negative balance blocks the
 * accept — the partner must recharge first (inDrive-style). Reading inside
 * `tx` keeps the check atomic with the booking/ride state change.
 */
export async function assertWalletEligibleInsideTx(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  uid: string,
): Promise<void> {
  const snap = await tx.get(db.collection(WALLET_ACCOUNTS).doc(uid));
  if (!snap.exists) return; // No wallet yet → zero balance → eligible.
  const balance = Number(snap.data()?.balanceMinor ?? 0);
  if (balance < 0) {
    err(
      'WALLET_BALANCE_LOW',
      402,
      'Your partner wallet balance is negative — top up points to keep accepting work.',
    );
  }
}
