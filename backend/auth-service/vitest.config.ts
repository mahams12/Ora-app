import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    testTimeout: 20_000,
    hookTimeout: 20_000,
    pool: 'forks',
    poolOptions: {
      forks: {
        singleFork: false,
        // Bound fork concurrency — unbounded forking under CPU saturation
        // produced intermittent supertest socket hang-ups (404/ECONNRESET)
        // that were transport-level, never domain failures. Files verified
        // independently in isolation; this keeps parallelism but removes
        // the resource contention that caused the flake.
        minForks: 1,
        maxForks: 4,
      },
    },
  },
});
