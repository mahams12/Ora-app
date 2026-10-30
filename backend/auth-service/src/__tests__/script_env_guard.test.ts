import { describe, expect, it } from 'vitest';
import { assertScriptFirebaseTarget } from '../../scripts/lib/script_env';
import { assertFirebaseTargetConfig } from '../config/firebase_target_guards';

describe('script firebase-target guard (fail-closed)', () => {
  it('refuses a bare run with no emulator hosts', () => {
    expect(() => assertScriptFirebaseTarget({})).toThrow(
      /REFUSING_START.*emulators/,
    );
  });

  it('refuses a partially-configured run', () => {
    expect(() =>
      assertScriptFirebaseTarget({
        FIRESTORE_EMULATOR_HOST: '127.0.0.1:8181',
      }),
    ).toThrow(/Missing: FIREBASE_AUTH_EMULATOR_HOST/);
  });

  it('passes with all emulator hosts set', () => {
    expect(() =>
      assertScriptFirebaseTarget({
        FIRESTORE_EMULATOR_HOST: '127.0.0.1:8181',
        FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
        FIREBASE_DATABASE_EMULATOR_HOST: '127.0.0.1:9000',
      }),
    ).not.toThrow();
  });

  it('passes on explicit ORA_ENV=staging/production', () => {
    expect(() =>
      assertScriptFirebaseTarget({ ORA_ENV: 'staging' }),
    ).not.toThrow();
    expect(() =>
      assertScriptFirebaseTarget({ ORA_ENV: 'production' }),
    ).not.toThrow();
  });
});

describe('backend firebase-target guard (index.ts path)', () => {
  it('refuses bare launch without emulators', () => {
    expect(() => assertFirebaseTargetConfig({})).toThrow(/REFUSING_START/);
  });

  it('refuses emulator run without ORA_FCM_SENDER=none', () => {
    expect(() =>
      assertFirebaseTargetConfig({
        FIRESTORE_EMULATOR_HOST: 'x',
        FIREBASE_AUTH_EMULATOR_HOST: 'x',
        FIREBASE_DATABASE_EMULATOR_HOST: 'x',
      }),
    ).toThrow(/ORA_FCM_SENDER=none/);
  });

  it('refuses emulator run without ORA_ROUTING_PROVIDER=haversine', () => {
    expect(() =>
      assertFirebaseTargetConfig({
        FIRESTORE_EMULATOR_HOST: 'x',
        FIREBASE_AUTH_EMULATOR_HOST: 'x',
        FIREBASE_DATABASE_EMULATOR_HOST: 'x',
        ORA_FCM_SENDER: 'none',
      }),
    ).toThrow(/ORA_ROUTING_PROVIDER=haversine/);
  });

  it('refuses ORA_ENV=staging + ORA_REQUIRE_FIREBASE_EMULATOR conflict', () => {
    expect(() =>
      assertFirebaseTargetConfig({
        ORA_ENV: 'staging',
        ORA_REQUIRE_FIREBASE_EMULATOR: 'true',
      }),
    ).toThrow(/REFUSING_START/);
  });
});
