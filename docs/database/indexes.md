# ORA — Firestore Index Design

## Single-Field Indexes (auto-created by Firestore)

These require no configuration:
- `rides.passengerId`
- `rides.assignedDriverId`
- `rides.state`
- `rides.createdAt`
- `drivers.driverStatus`
- `drivers.activeRideId`

## Composite Indexes Required

```json
// firestore.indexes.json

{
  "indexes": [
    {
      "collectionGroup": "rides",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "passengerId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "rides",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "assignedDriverId", "order": "ASCENDING" },
        { "fieldPath": "state", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "rides",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "state", "order": "ASCENDING" },
        { "fieldPath": "expiresAt", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "drivers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "driverStatus", "order": "ASCENDING" },
        { "fieldPath": "homeCity", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "rideOffers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "rideId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "rideOffers",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "rideId", "order": "ASCENDING" },
        { "fieldPath": "driverId", "order": "ASCENDING" },
        { "fieldPath": "requestVersion", "order": "ASCENDING" }
      ]
    },
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "ratings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ratedId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "safetyEvents",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "resolved", "order": "ASCENDING" },
        { "fieldPath": "severity", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "DESCENDING" }
      ]
    }
  ]
}
```

## Index Exemptions (Fields NOT indexed)

Mark these as excluded to avoid unnecessary index writes:

- `rides.routePolyline` — large string; never queried
- `rides.stateHistory` — array; queried only via rideEvents collection
- `driverDocuments.*` — document contents; not queried directly
- `pricingSnapshots.inputs` — map; never queried as filter

## Index Cost Analysis

Firestore charges per indexed write. Excessive indexes = higher cost.

Guidelines:
- Only create indexes that match actual query patterns
- Do NOT create indexes on fields written on every GPS update
- Monitor unused indexes in Firestore console after Phase 10
