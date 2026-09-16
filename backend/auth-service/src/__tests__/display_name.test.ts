import { describe, expect, it } from 'vitest';
import { normalizeDisplayName } from '../services/display_name';

describe('normalizeDisplayName', () => {
  it('trims, NFC-normalizes, and collapses whitespace', () => {
    expect(normalizeDisplayName('  Ada   Khan  ')).toBe('Ada Khan');
  });

  it('rejects empty and whitespace-only values', () => {
    expect(() => normalizeDisplayName('')).toThrow(/required/i);
    expect(() => normalizeDisplayName('   ')).toThrow(/required/i);
  });

  it('rejects non-strings', () => {
    expect(() => normalizeDisplayName(1)).toThrow(/string/i);
  });

  it('rejects too-short, too-long, control, and non-letter names', () => {
    expect(() => normalizeDisplayName('A')).toThrow(/at least 2/i);
    expect(() => normalizeDisplayName('A'.repeat(51))).toThrow(/at most 50/i);
    expect(() => normalizeDisplayName('Ada\u0007Khan')).toThrow(/invalid/i);
    expect(() => normalizeDisplayName('12')).toThrow(/two letters/i);
  });
});
