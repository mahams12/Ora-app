import { RideDomainError } from './types';

export function assertIntegerMinor(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || !Number.isFinite(value)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must be an integer minor-unit amount.`,
    );
  }
  if (value < 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must not be negative.`,
    );
  }
  if (value > 50_000_000) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} exceeds maximum allowed amount.`,
    );
  }
  return value;
}

export function assertPositiveIntegerMinor(value: unknown, field: string): number {
  const n = assertIntegerMinor(value, field);
  if (n === 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must be greater than zero.`,
    );
  }
  return n;
}

export function assertCurrency(value: unknown): string {
  if (value !== 'PKR') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'currency must be PKR.',
    );
  }
  return value;
}
