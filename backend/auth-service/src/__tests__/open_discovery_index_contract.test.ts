import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Documents the composite index for ordered open-discovery (optional in prod).
 * M0 listOpenRides uses an unordered scan + in-memory sort when this index is absent.
 */
describe('Firestore index contract — M0 open discovery', () => {
  it('firestore.indexes.json includes assignedDriverId + state + createdAt + rideId', () => {
    const indexesPath = path.join(
      __dirname,
      '../../../../firestore.indexes.json',
    );
    const raw = JSON.parse(readFileSync(indexesPath, 'utf8')) as {
      indexes: Array<{ collectionGroup: string; fields: Array<{ fieldPath: string }> }>;
    };
    const ridesIndexes = raw.indexes.filter((i) => i.collectionGroup === 'rides');
    const hasM0 = ridesIndexes.some((idx) => {
      const paths = idx.fields.map((f) => f.fieldPath);
      return (
        paths.includes('assignedDriverId') &&
        paths.includes('state') &&
        paths.includes('createdAt') &&
        paths.includes('rideId')
      );
    });
    expect(hasM0).toBe(true);
  });
});
