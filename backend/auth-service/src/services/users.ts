import type { Firestore } from 'firebase-admin/firestore';
import { toPublicProfile, normalizeAvatarData } from './profile';
import { normalizeDisplayName } from './display_name';
import { N3_BUSY_RIDE_STATES } from '../drivers/nearby_service';
import type {
  ActiveMode,
  AuthenticatedCaller,
  UserProfile,
  VendorType,
} from '../types';

const USERS = 'users';
const RIDES = 'rides';

export const VENDOR_TYPES: readonly VendorType[] = [
  'cargo',
  'rental',
  'service',
];

export const ACTIVE_MODES: readonly ActiveMode[] = ['passenger', 'driver'];

/**
 * Passenger-side states that block switching to driver mode: the user has a
 * live booking they must finish or cancel first. Terminal states and the
 * closeable end states (RIDE_COMPLETED, RETURNED) do not block.
 */
const PASSENGER_BLOCK_STATES = [
  'SEARCHING',
  'OFFERS_AVAILABLE',
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
  'DELIVERY_FAILED',
  'RETURNING',
] as const;

export class UserNotFoundError extends Error {
  constructor() {
    super('USER_NOT_FOUND');
    this.name = 'UserNotFoundError';
  }
}

/**
 * Idempotent first-sign-in bootstrap.
 *
 * Identity ALWAYS comes from the verified Firebase token — never from the
 * request body. Concurrent calls for the same uid create at most one document.
 */
export async function registerUser(
  db: Firestore,
  caller: AuthenticatedCaller,
  now: Date,
): Promise<UserProfile> {
  const ref = db.collection(USERS).doc(caller.uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      return;
    }

    tx.set(ref, {
      uid: caller.uid,
      phoneNumber: caller.phoneNumber ?? '',
      displayName: null,
      role: 'passenger',
      driverStatus: 'none',
      activeMode: 'passenger',
      isActive: true,
      banned: false,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    });
  });

  const after = await ref.get();
  if (!after.exists) {
    throw new Error('REGISTER_PERSIST_FAILED');
  }
  return toPublicProfile(after.data() ?? {}, caller.uid);
}

export async function getMe(
  db: Firestore,
  caller: AuthenticatedCaller,
): Promise<UserProfile | null> {
  const snap = await db.collection(USERS).doc(caller.uid).get();
  if (!snap.exists) {
    return null;
  }
  return toPublicProfile(snap.data() ?? {}, caller.uid);
}

/**
 * Thrown when a mode switch is refused because the account has a live job in
 * the current mode (active ride, courier delivery, or return leg).
 */
export class ModeSwitchBlockedError extends Error {
  constructor(
    readonly code: string,
    readonly httpStatus: number,
    message: string,
    readonly activeRideId: string | null = null,
  ) {
    super(message);
    this.name = 'ModeSwitchBlockedError';
  }
}

/**
 * Server-authoritative Passenger ⇄ Driver mode switch.
 *
 * - mode='driver' requires driverStatus='approved' (pending/suspended/never-
 *   onboarded get distinct refusal codes for the UI). A live passenger-side
 *   booking blocks the switch — finish or cancel it first.
 * - mode='passenger' blocks while the caller is the assigned driver on an
 *   in-flight job (N3 busy states incl. courier custody). Availability is
 *   flipped offline by the route handler via DriverAvailabilityService so the
 *   account can never be a "ghost driver" from passenger mode.
 * - `role` is never downgraded; an approved driver switching to driver mode
 *   with a legacy role='passenger' doc is repaired to role='driver'.
 *
 * The eligibility check + write happen inside one transaction, so concurrent
 * switches from multiple devices converge safely (last write wins; the guard
 * is re-evaluated inside the tx).
 */
export async function switchMode(
  db: Firestore,
  caller: AuthenticatedCaller,
  modeRaw: unknown,
  now: Date,
): Promise<UserProfile> {
  if (
    typeof modeRaw !== 'string' ||
    !(ACTIVE_MODES as readonly string[]).includes(modeRaw)
  ) {
    throw new ModeSwitchBlockedError(
      'VALIDATION_ERROR',
      400,
      "mode must be 'passenger' or 'driver'.",
    );
  }
  const mode = modeRaw as ActiveMode;
  const ref = db.collection(USERS).doc(caller.uid);
  const nowIso = now.toISOString();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new UserNotFoundError();
    }
    const data = snap.data() ?? {};
    if (data.isActive === false || data.banned === true) {
      throw new ModeSwitchBlockedError(
        'ACCOUNT_DISABLED',
        403,
        'This account is disabled.',
      );
    }
    const driverStatus =
      typeof data.driverStatus === 'string' ? data.driverStatus : 'none';
    const isApprovedDriver = driverStatus === 'approved';
    const cargoApp = ((data.vendorApplications ?? {}) as Record<
      string,
      unknown
    >)['cargo'] as Record<string, unknown> | undefined;
    const isDeliveryOperator =
      isApprovedDriver || cargoApp?.['status'] === 'approved';

    if (mode === 'driver') {
      if (driverStatus === 'pending') {
        throw new ModeSwitchBlockedError(
          'DRIVER_APPROVAL_PENDING',
          409,
          'Driver application is still under review.',
        );
      }
      if (driverStatus === 'suspended') {
        throw new ModeSwitchBlockedError(
          'DRIVER_SUSPENDED',
          403,
          'Driver access is suspended.',
        );
      }
      if (!isApprovedDriver) {
        throw new ModeSwitchBlockedError(
          'DRIVER_ONBOARDING_REQUIRED',
          409,
          'Complete driver onboarding before switching to driver mode.',
        );
      }
      const activeAsPassenger = await tx.get(
        db
          .collection(RIDES)
          .where('passengerId', '==', caller.uid)
          .where('state', 'in', [...PASSENGER_BLOCK_STATES])
          .limit(1),
      );
      if (!activeAsPassenger.empty) {
        const rideId = String(activeAsPassenger.docs[0]?.data()?.rideId ?? '');
        throw new ModeSwitchBlockedError(
          'ACTIVE_JOB',
          409,
          'Finish or cancel your active booking before switching modes.',
          rideId || null,
        );
      }
      const patch: Record<string, unknown> = {
        activeMode: 'driver',
        updatedAt: nowIso,
      };
      if (data.role !== 'driver') {
        // Legacy approved-driver doc missing role='driver' — repair, never merge.
        patch.role = 'driver';
      }
      tx.update(ref, patch);
      return;
    }

    // mode === 'passenger': block while assigned on an in-flight job
    // (approved driver or logistics partner).
    if (isDeliveryOperator) {
      const activeAsDriver = await tx.get(
        db
          .collection(RIDES)
          .where('assignedDriverId', '==', caller.uid)
          .where('state', 'in', [...N3_BUSY_RIDE_STATES])
          .limit(1),
      );
      if (!activeAsDriver.empty) {
        const rideId = String(activeAsDriver.docs[0]?.data()?.rideId ?? '');
        throw new ModeSwitchBlockedError(
          'ACTIVE_JOB',
          409,
          'You have an active trip or delivery. Finish it or return the parcel before switching to passenger mode.',
          rideId || null,
        );
      }
    }
    tx.update(ref, { activeMode: 'passenger', updatedAt: nowIso });
  });

  const profile = await getMe(db, caller);
  if (!profile) {
    throw new UserNotFoundError();
  }
  return profile;
}

export class VendorApplicationError extends Error {
  constructor(
    readonly code: string,
    readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'VendorApplicationError';
  }
}

const VENDOR_DETAILS_MAX_KEYS = 20;
const VENDOR_DETAILS_MAX_VALUE_LEN = 500;
const VENDOR_DETAILS_MAX_BYTES = 4_000;

/**
 * Keeps only shallow scalar fields from a vendor application payload —
 * enough for admin review, too small to abuse as free-form storage.
 */
function normalizeVendorDetails(
  raw: unknown,
): Record<string, string | number | boolean> | undefined {
  if (raw === undefined || raw === null) {
    return undefined;
  }
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    throw new VendorApplicationError(
      'VALIDATION_ERROR',
      400,
      'details must be a JSON object.',
    );
  }
  const out: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (Object.keys(out).length >= VENDOR_DETAILS_MAX_KEYS) break;
    if (typeof key !== 'string' || key.length === 0 || key.length > 60) {
      continue;
    }
    if (
      typeof value === 'string' &&
      value.trim().length > 0 &&
      value.length <= VENDOR_DETAILS_MAX_VALUE_LEN
    ) {
      out[key] = value.trim();
    } else if (
      (typeof value === 'number' && Number.isFinite(value)) ||
      typeof value === 'boolean'
    ) {
      out[key] = value;
    }
  }
  if (JSON.stringify(out).length > VENDOR_DETAILS_MAX_BYTES) {
    throw new VendorApplicationError(
      'VALIDATION_ERROR',
      400,
      'details payload too large.',
    );
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

/**
 * Server-authoritative partner application. Mirrors the driver onboarding
 * gate: apply once → pending until an admin flips vendorApplications.{type}
 * to approved/rejected/suspended (seed script or console).
 *
 * Idempotent: re-submitting while pending or approved is a no-op that
 * returns the current profile. Rejected applicants may re-apply; suspended
 * is hard-blocked like DRIVER_SUSPENDED.
 */
export async function applyVendorApplication(
  db: Firestore,
  caller: AuthenticatedCaller,
  typeRaw: unknown,
  detailsRaw: unknown,
  now: Date,
): Promise<UserProfile> {
  if (
    typeof typeRaw !== 'string' ||
    !(VENDOR_TYPES as readonly string[]).includes(typeRaw)
  ) {
    throw new VendorApplicationError(
      'VALIDATION_ERROR',
      400,
      "type must be 'cargo', 'rental', or 'service'.",
    );
  }
  const type = typeRaw as VendorType;
  const details = normalizeVendorDetails(detailsRaw);
  const ref = db.collection(USERS).doc(caller.uid);
  const nowIso = now.toISOString();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new UserNotFoundError();
    }
    const data = snap.data() ?? {};
    if (data.isActive === false || data.banned === true) {
      throw new VendorApplicationError(
        'ACCOUNT_DISABLED',
        403,
        'This account is disabled.',
      );
    }
    const apps = (data.vendorApplications ?? {}) as Record<
      string,
      { status?: unknown }
    >;
    const existing = apps[type];
    if (
      existing &&
      (existing.status === 'pending' || existing.status === 'approved')
    ) {
      // Idempotent no-op — profile is re-read below.
      return;
    }
    if (existing && existing.status === 'suspended') {
      throw new VendorApplicationError(
        'VENDOR_SUSPENDED',
        403,
        'This partner access is suspended — contact support.',
      );
    }
    tx.update(ref, {
      [`vendorApplications.${type}`]: {
        status: 'pending',
        submittedAt: nowIso,
        ...(details ? { details } : {}),
      },
      updatedAt: nowIso,
    });
  });

  const profile = await getMe(db, caller);
  if (!profile) {
    throw new UserNotFoundError();
  }
  return profile;
}

/**
 * Updates only displayName + updatedAt for the authenticated caller.
 * Security fields are never written from this path.
 */
export async function updateProfile(
  db: Firestore,
  caller: AuthenticatedCaller,
  displayNameRaw: unknown,
  now: Date,
  avatarDataRaw?: unknown,
): Promise<UserProfile> {
  const displayName = normalizeDisplayName(displayNameRaw);
  // undefined → leave untouched; null/'' → clear; string → validate+set.
  const avatarData =
    avatarDataRaw === undefined ? undefined : normalizeAvatarData(avatarDataRaw);
  const ref = db.collection(USERS).doc(caller.uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new UserNotFoundError();
    }
    const patch: Record<string, unknown> = {
      displayName,
      updatedAt: now.toISOString(),
    };
    if (avatarData === null) {
      patch.avatarData = null;
    } else if (avatarData !== undefined) {
      patch.avatarData = avatarData;
    }
    tx.update(ref, patch);
  });

  const after = await ref.get();
  if (!after.exists) {
    throw new UserNotFoundError();
  }
  return toPublicProfile(after.data() ?? {}, caller.uid);
}
