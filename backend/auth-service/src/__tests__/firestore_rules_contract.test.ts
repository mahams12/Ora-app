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
      'locationStreams',
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

  it('denies all client writes to users/{uid}', () => {
    const idx = rules.indexOf('match /users/{uid}');
    expect(idx).toBeGreaterThan(-1);
    const slice = rules.slice(idx, idx + 280);
    expect(slice).toMatch(/allow create,\s*update,\s*delete:\s*if false/);
    expect(slice).not.toContain('userProtectedFieldsUnchanged');
  });

  it('denies safety/admin/report collections to clients', () => {
    for (const collection of [
      'reports',
      'blocks',
      'safetyEvents',
      'moderationCases',
      'tripShareTokens',
      'driverPayouts',
      'refunds',
    ]) {
      expect(rules).toContain(`match /${collection}/{`);
      const idx = rules.indexOf(`match /${collection}/{`);
      const slice = rules.slice(idx, idx + 180);
      expect(slice).toMatch(/allow read,\s*write:\s*if false/);
    }
  });
});
