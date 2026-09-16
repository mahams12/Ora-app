export const DISPLAY_NAME_MIN_LENGTH = 2;
export const DISPLAY_NAME_MAX_LENGTH = 50;

export class DisplayNameValidationError extends Error {
  readonly code = 'VALIDATION_ERROR';

  constructor(message: string) {
    super(message);
    this.name = 'DisplayNameValidationError';
  }
}

const CONTROL_CHARS = /[\u0000-\u001F\u007F-\u009F]/;
const UNPAIRED_SURROGATE = /[\uD800-\uDFFF]/;
const LETTERS = /\p{L}/gu;

/**
 * Normalize and validate a passenger display name.
 *
 * Server-authoritative. Rejects empty/whitespace, control characters,
 * unpaired surrogates, and lengths outside [2, 50] after NFC + trim.
 */
export function normalizeDisplayName(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new DisplayNameValidationError('displayName must be a string.');
  }

  const normalized = raw.normalize('NFC').trim().replace(/\s+/g, ' ');

  if (normalized.length === 0) {
    throw new DisplayNameValidationError('displayName is required.');
  }
  if (CONTROL_CHARS.test(normalized) || UNPAIRED_SURROGATE.test(normalized)) {
    throw new DisplayNameValidationError(
      'displayName contains invalid characters.',
    );
  }
  if (normalized.length < DISPLAY_NAME_MIN_LENGTH) {
    throw new DisplayNameValidationError(
      `displayName must be at least ${DISPLAY_NAME_MIN_LENGTH} characters.`,
    );
  }
  if (normalized.length > DISPLAY_NAME_MAX_LENGTH) {
    throw new DisplayNameValidationError(
      `displayName must be at most ${DISPLAY_NAME_MAX_LENGTH} characters.`,
    );
  }

  const letterCount = normalized.match(LETTERS)?.length ?? 0;
  if (letterCount < DISPLAY_NAME_MIN_LENGTH) {
    throw new DisplayNameValidationError(
      'displayName must contain at least two letters.',
    );
  }

  return normalized;
}
