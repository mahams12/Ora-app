/**
 * Firestore rules structural tests (Phase 2B).
 *
 * Full emulator rules evaluation requires the Firebase emulator suite
 * (REQUIRES LIVE ENVIRONMENT). This suite asserts the checked-in rules file
 * remains fail-closed for authoritative collections.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const rulesPath = resolve(__dirname, '../../../../firestore.rules');

describe('firestore.rules fail-closed contract', () => {
  const rules = readFileSync(rulesPath, 'utf8');

  it('declares rules_version 2', () => {
    expect(rules).toMatch(/rules_version\s*=\s*'2'/);
  });

  it('denies authoritative ride/payment/driver collections to clients', () => {
    for (const collection of [
      'rides',
      'rideOffers',
      'paymentIntents',
      'walletAccounts',
      'outboxEvents',
      'idempotencyRecords',
      'drivers',
      'adminAuditLogs',
      'otpSessions',
    ]) {
      expect(rules).toContain(`match /${collection}/{`);
      // Each of these blocks should contain allow read, write: if false
      const idx = rules.indexOf(`match /${collection}/{`);
      const slice = rules.slice(idx, idx + 180);
      expect(slice).toMatch(/allow read,\s*write:\s*if false/);
    }
  });

  it('includes a catch-all deny', () => {
    expect(rules).toMatch(/match \/\{document=\*\*\}/);
    expect(rules).toMatch(/allow read,\s*write:\s*if false/);
  });

  it('protects users immutable security fields on update', () => {
    expect(rules).toContain('userProtectedFieldsUnchanged');
    expect(rules).toContain("'role'");
    expect(rules).toContain("'banned'");
  });
});
