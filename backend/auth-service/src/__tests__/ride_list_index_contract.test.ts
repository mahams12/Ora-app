import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * GET /v1/rides (listRides) requires composite indexes in production Firestore.
 * If indexes from firestore.indexes.json are not deployed, Cloud Run returns 500 INTERNAL.
 */
describe('Firestore index contract — ride list (GET /v1/rides)', () => {
  const ridesIndexes = (): Array<{ fields: Array<{ fieldPath: string; order?: string }> }> => {
    const indexesPath = path.join(__dirname, '../../../../firestore.indexes.json');
    const raw = JSON.parse(readFileSync(indexesPath, 'utf8')) as {
      indexes: Array<{
        collectionGroup: string;
        fields: Array<{ fieldPath: string; order?: string }>;
      }>;
    };
    return raw.indexes.filter((i) => i.collectionGroup === 'rides');
  };

  function hasIndex(
    indexes: Array<{ fields: Array<{ fieldPath: string; order?: string }> }>,
    ownerField: 'passengerId' | 'assignedDriverId',
  ): boolean {
    return indexes.some((idx) => {
      const paths = idx.fields.map((f) => f.fieldPath);
      return (
        paths.includes(ownerField) &&
        paths.includes('createdAt') &&
        paths.includes('rideId')
      );
    });
  }

  it('includes passengerId + createdAt + rideId for passenger history', () => {
    expect(hasIndex(ridesIndexes(), 'passengerId')).toBe(true);
  });

  it('includes assignedDriverId + createdAt + rideId for approved driver history', () => {
    expect(hasIndex(ridesIndexes(), 'assignedDriverId')).toBe(true);
  });
});
