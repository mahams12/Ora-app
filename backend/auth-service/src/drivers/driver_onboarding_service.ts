import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { DriverDomainError } from './types';

const USERS = 'users';
const DRIVERS = 'drivers';

export const DRIVER_VEHICLE_CATEGORIES = [
  'zip',
  'trio',
  'easy',
  'breeze',
  'premium',
  'executive',
] as const;

export type DriverVehicleCategory =
  (typeof DRIVER_VEHICLE_CATEGORIES)[number];

interface DriverOnboardingApplication {
  fullName: string;
  cnicNumber: string;
  homeCity: string;
  licenseNumber: string;
  licenseExpiry: string;
  vehicleCategory: DriverVehicleCategory;
  vehicleMake: string;
  vehicleModel: string;
  vehicleYear: number;
  vehicleColor: string;
  plateNumber: string;
}

export interface SubmitDriverOnboardingInput {
  caller: AuthenticatedCaller;
  body: unknown;
}

function invalid(field: string, message: string): never {
  throw new DriverDomainError(
    'VALIDATION_ERROR',
    400,
    `${field} ${message}`,
  );
}

function requiredString(
  body: Record<string, unknown>,
  field: string,
  minLength: number,
  maxLength: number,
): string {
  const value = body[field];
  if (typeof value !== 'string') {
    return invalid(field, 'must be a string.');
  }
  const normalized = value.trim();
  if (normalized.length < minLength || normalized.length > maxLength) {
    return invalid(
      field,
      `must be between ${minLength} and ${maxLength} characters.`,
    );
  }
  return normalized;
}

function parseApplication(body: unknown): DriverOnboardingApplication {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return invalid('application', 'must be an object.');
  }
  const fields = body as Record<string, unknown>;
  const fullName = requiredString(fields, 'fullName', 2, 64);

  const cnicInput = fields.cnicNumber;
  if (
    typeof cnicInput !== 'string' ||
    !/^\d{5}-?\d{7}-?\d$/.test(cnicInput.trim())
  ) {
    return invalid('cnicNumber', 'must match #####-#######-#.');
  }
  const cnicNumber = cnicInput.trim().replaceAll('-', '');

  const homeCity = requiredString(fields, 'homeCity', 2, 64);
  const licenseNumber = requiredString(fields, 'licenseNumber', 3, 32);

  const licenseExpiryValue = fields.licenseExpiry;
  if (
    typeof licenseExpiryValue !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(licenseExpiryValue.trim())
  ) {
    return invalid('licenseExpiry', 'must be a valid YYYY-MM-DD date.');
  }
  const licenseExpiry = licenseExpiryValue.trim();
  const expiryDate = new Date(`${licenseExpiry}T00:00:00.000Z`);
  const todayUtc = new Date().toISOString().slice(0, 10);
  if (
    Number.isNaN(expiryDate.getTime()) ||
    expiryDate.toISOString().slice(0, 10) !== licenseExpiry ||
    licenseExpiry < todayUtc
  ) {
    return invalid('licenseExpiry', 'must not be before today (UTC).');
  }

  const vehicleCategory = fields.vehicleCategory;
  if (
    typeof vehicleCategory !== 'string' ||
    !(DRIVER_VEHICLE_CATEGORIES as readonly string[]).includes(
      vehicleCategory,
    )
  ) {
    return invalid(
      'vehicleCategory',
      `must be one of ${DRIVER_VEHICLE_CATEGORIES.join(', ')}.`,
    );
  }

  const vehicleMake = requiredString(fields, 'vehicleMake', 1, 64);
  const vehicleModel = requiredString(fields, 'vehicleModel', 1, 64);
  const vehicleYear = fields.vehicleYear;
  const maxVehicleYear = new Date().getUTCFullYear() + 1;
  if (
    typeof vehicleYear !== 'number' ||
    !Number.isInteger(vehicleYear) ||
    vehicleYear < 1980 ||
    vehicleYear > maxVehicleYear
  ) {
    return invalid(
      'vehicleYear',
      `must be an integer from 1980 to ${maxVehicleYear}.`,
    );
  }
  const vehicleColor = requiredString(fields, 'vehicleColor', 1, 32);
  const plateInput = fields.plateNumber;
  if (typeof plateInput !== 'string') {
    return invalid('plateNumber', 'must be a string.');
  }
  const plateNumber = plateInput.trim();
  if (plateNumber.length < 2 || plateNumber.length > 16) {
    return invalid('plateNumber', 'must be between 2 and 16 characters.');
  }

  return {
    fullName,
    cnicNumber,
    homeCity,
    licenseNumber,
    licenseExpiry,
    vehicleCategory: vehicleCategory as DriverVehicleCategory,
    vehicleMake,
    vehicleModel,
    vehicleYear,
    vehicleColor,
    plateNumber: plateNumber.toUpperCase(),
  };
}

export class DriverOnboardingService {
  constructor(
    private readonly db: Firestore,
    private readonly autoApprove = true,
  ) {}

  async submit(input: SubmitDriverOnboardingInput): Promise<{
    httpStatus: number;
    body: { data: { driverStatus: 'approved' | 'pending'; approved: boolean } };
  }> {
    const application = parseApplication(input.body);
    const userRef = this.db.collection(USERS).doc(input.caller.uid);
    const driverRef = this.db.collection(DRIVERS).doc(input.caller.uid);
    const nowIso = new Date().toISOString();

    const result = await this.db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const driverSnap = await tx.get(driverRef);

      if (!userSnap.exists) {
        throw new DriverDomainError(
          'FORBIDDEN',
          403,
          'User profile does not exist. Call POST /v1/auth/register.',
        );
      }

      const user = userSnap.data() ?? {};
      if (user.isActive === false || user.banned === true) {
        throw new DriverDomainError(
          'ACCOUNT_DISABLED',
          403,
          'This account is disabled.',
        );
      }

      const currentStatus =
        typeof user.driverStatus === 'string' ? user.driverStatus : 'none';
      if (currentStatus === 'approved') {
        return { driverStatus: 'approved' as const, approved: true };
      }
      if (currentStatus === 'suspended') {
        throw new DriverDomainError(
          'DRIVER_SUSPENDED',
          403,
          'This driver account is suspended.',
        );
      }
      if (currentStatus !== 'none' && currentStatus !== 'pending') {
        throw new DriverDomainError(
          'DRIVER_STATUS_UNAVAILABLE',
          403,
          'This driver application cannot be changed.',
        );
      }

      const approved = this.autoApprove;
      const driverStatus: 'approved' | 'pending' = approved
        ? 'approved'
        : 'pending';
      const userPatch: Record<string, unknown> = approved
        ? {
            role: 'driver',
            driverStatus,
            driverApprovalSource: 'auto',
            updatedAt: nowIso,
          }
        : { driverStatus };
      tx.update(userRef, userPatch);

      const driverPatch: Record<string, unknown> = {
        driverId: input.caller.uid,
        userId: input.caller.uid,
        fullName: application.fullName,
        homeCity: application.homeCity,
        vehicle: {
          category: application.vehicleCategory,
          make: application.vehicleMake,
          model: application.vehicleModel,
          year: application.vehicleYear,
          color: application.vehicleColor,
          plateNumber: application.plateNumber,
        },
        documents: {
          cnicNumber: application.cnicNumber,
          licenseNumber: application.licenseNumber,
          licenseExpiry: application.licenseExpiry,
        },
        onboardingSubmittedAt: nowIso,
        updatedAt: nowIso,
        ...(approved ? { approvedAt: nowIso } : {}),
      };

      if (driverSnap.exists) {
        tx.update(driverRef, driverPatch);
      } else {
        tx.set(driverRef, {
          ...driverPatch,
          availabilityState: 'offline',
          createdAt: nowIso,
        });
      }

      return { driverStatus, approved };
    });

    return { httpStatus: 200, body: { data: result } };
  }
}
