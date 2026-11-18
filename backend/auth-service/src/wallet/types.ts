import type { VendorType } from '../types';

/** Firestore collections (already reserved in firestore.rules — server-only). */
export const WALLET_ACCOUNTS = 'walletAccounts';
export const WALLET_LEDGER = 'walletLedgerEntries';
export const WALLET_TOPUPS = 'walletTopups';
export const WALLET_CONFIG = 'walletConfig';
export const WALLET_CONFIG_DOC = 'global';

/** A partner can earn as a driver and/or any vendor type — one wallet each. */
export type PartnerRole = 'driver' | VendorType;
export const PARTNER_ROLES: readonly PartnerRole[] = [
  'driver',
  'cargo',
  'rental',
  'service',
];

export class WalletError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'WalletError';
  }
}

/** walletConfig/global — every field optional; defaults apply per-key. */
export interface WalletConfig {
  /** Minor units per wallet point. Default 100 → 1 point = Rs 1. */
  minorPerPoint: number;
  /** Commission in basis points per role. Default 1000 = 10% everywhere. */
  commissionBps: Record<PartnerRole, number>;
  /** Below this balance (minor) the wallet shows a low-balance warning. */
  lowBalanceWarnMinor: number;
}

export const DEFAULT_WALLET_CONFIG: WalletConfig = {
  minorPerPoint: 100,
  commissionBps: { driver: 1000, cargo: 1000, rental: 1000, service: 1000 },
  lowBalanceWarnMinor: 50_000,
};

export interface WalletAccount {
  userId: string;
  /** Signed balance in minor units (paisa). May go negative by policy. */
  balanceMinor: number;
  currency: string;
  createdAt: string;
  updatedAt: string;
  version: number;
}

export type LedgerType =
  | 'TOPUP_CREDIT'
  | 'COMMISSION_DEBIT'
  | 'WITHDRAWAL_DEBIT'
  | 'ADJUSTMENT';

export interface WalletLedgerEntry {
  entryId: string;
  accountId: string;
  userId: string;
  type: LedgerType;
  /** Signed points delta (+ top-up, − deduction). Whole points. */
  pointsDelta: number;
  /** Signed minor-unit delta backing the points movement. */
  amountMinor: number;
  sourceType?: 'ride' | 'booking' | 'topup' | 'withdrawal' | 'admin';
  sourceId?: string;
  role?: PartnerRole;
  /** Gross completed amount (minor) a commission was computed on. */
  grossMinor?: number;
  commissionBps?: number;
  balanceAfterMinor: number;
  paymentMethod?: string;
  reference?: string;
  description: string;
  status: 'POSTED';
  idempotencyKey: string;
  createdAt: string;
}

export type TopupStatus = 'PENDING' | 'CREDITED' | 'REJECTED';

export interface WalletTopup {
  topupId: string;
  userId: string;
  /** 'credit' adds points after verification; 'debit' is a payout request. */
  kind: 'credit' | 'debit';
  points: number;
  amountMinor: number;
  method: string;
  reference?: string;
  status: TopupStatus;
  ledgerEntryId?: string;
  idempotencyKey: string;
  createdAt: string;
  resolvedAt?: string;
  resolvedBy?: string;
}
