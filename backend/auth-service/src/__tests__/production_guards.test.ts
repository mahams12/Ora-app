import { describe, expect, it } from 'vitest';
import { assertProductionSecurityConfig } from '../config/production_guards';

describe('production security guards', () => {
  it('allows development with App Check off', () => {
    expect(() =>
      assertProductionSecurityConfig({
        ORA_ENV: 'development',
        REQUIRE_APP_CHECK: 'false',
      }),
    ).not.toThrow();
  });

  it('refuses production when REQUIRE_APP_CHECK is false', () => {
    expect(() =>
      assertProductionSecurityConfig({
        ORA_ENV: 'production',
        REQUIRE_APP_CHECK: 'false',
      }),
    ).toThrow(/REQUIRE_APP_CHECK=true/);
  });

  it('allows production when REQUIRE_APP_CHECK is true', () => {
    expect(() =>
      assertProductionSecurityConfig({
        ORA_ENV: 'production',
        REQUIRE_APP_CHECK: 'true',
      }),
    ).not.toThrow();
  });

  it('treats NODE_ENV=production as production', () => {
    expect(() =>
      assertProductionSecurityConfig({
        NODE_ENV: 'production',
        REQUIRE_APP_CHECK: 'false',
      }),
    ).toThrow(/REQUIRE_APP_CHECK=true/);
  });
});
