# ORA — Realtime Database Schema

## Design Principles

- RTDB holds ONLY ephemeral, high-frequency, or real-time state
- All durable state lives in Firestore
- RTDB data is auto-cleaned by server after use
- Security: drivers write own presence; server writes ride-scoped realtime projections

## Root Structure

```
{
  "driverPresence": {
    "{driverId}": {
      "online": true,
      "lastSeen": 1724035800000,
      "city": "lahore",
      "connectedAt": 1724035200000,
      "stale": false
    }
  },

  "rideAccess": {
    "{rideId}": {
      "{uid}": true
    }
  },

  "tripLocations": {
    "{rideId}": {
      "latest": {
        "lat": 31.5204,
        "lng": 74.3587,
        "accuracy": 8.5,
        "heading": 245.0,
        "speed": 35.2,
        "ts": 1724035800000,
        "driverId": "{driverId}",
        "locationSeq": 142,
        "locationStreamId": "locstream_01JABC"
      },
      "recent": {
        "{eventSequence}": {
          "lat": 31.5204,
          "lng": 74.3587,
          "accuracy": 8.5,
          "heading": 245.0,
          "speed": 35.2,
          "ts": 1724035800000,
          "driverId": "{driverId}",
          "locationSeq": 142,
          "locationStreamId": "locstream_01JABC"
        }
      }
    }
  },

  "rideSignals": {
    "{rideId}": {
      "state": "DRIVER_ASSIGNED",
      "driverId": "{driverId}",
      "aggregateVersion": 6,
      "eventSequence": 991,
      "ts": 1724035800000
    }
  },

  "rideRequests": {
    "{driverId}": {
      "pending": {
        "{rideId}": {
          "pickup": {
            "lat": 31.5204,
            "lng": 74.3587,
            "address": "Gulberg III, Lahore"
          },
          "destination": {
            "lat": 31.5147,
            "lng": 74.3422,
            "address": "Liberty Market, Gulberg"
          },
          "distanceKm": 5.8,
          "estimatedDurationMin": 14,
          "passengerOfferMinor": 34000,
          "recommendedFareMinor": 34000,
          "requestVersion": 1,
          "category": "easy",
          "passengerRating": 4.8,
          "passengerTripCount": 214,
          "serviceType": "ride",
          "expiresAt": 1724036100000,
          "createdAt": 1724035800000
        }
      }
    }
  }
}
```

## Lifecycle Management

### driverPresence
- Written by driver (RTDB SDK) on go-online
- `onDisconnect().remove()` registered on connection
- Server sweeper removes stale entries (no update > 30s) every 30s
- Cleaned immediately on go-offline server call

### rideAccess
- Written by server only
- Contains currently authorized ride participants for RTDB access checks
- Removed shortly after ride terminal state

### tripLocations
- Written by server (Admin SDK) only — validates GPS before writing
- Retained during active trip
- `latest` is used for current rendering; `recent` is bounded history only
- Server deletes entire `tripLocations/{rideId}` node within 60s of ride terminal state
- No long-term storage — all ephemeral

### rideSignals
- Written by server only
- Retained 5 minutes after trip terminal state
- Cleaned by server sweep

### rideRequests/{driverId}/pending
- Written by server (Admin SDK) for each notified driver
- Deleted by server when:
  - Driver declined or card TTL elapsed
  - Driver's offer withdrawn
  - Ride is assigned (delete for all except winner; winner switches to assigned trip UI)
  - Ride is cancelled/expired (delete for all)
  - Request card expires (server TTL sweep matches expiresAt)

Accept/counter does **not** delete other drivers' pending cards. Only passenger selection / assignment does.

## RTDB Security Rules (Design)

```json
{
  "rules": {
    "driverPresence": {
      "$driverId": {
        ".read": "auth != null && auth.uid === $driverId",
        ".write": "auth != null && auth.uid === $driverId"
      }
    },
    "rideAccess": {
      "$rideId": {
        ".read": "false",
        ".write": "false"
      }
    },
    "tripLocations": {
      "$rideId": {
        ".read": "auth != null && root.child('rideAccess').child($rideId).child(auth.uid).val() === true",
        ".write": "false"
      }
    },
    "rideSignals": {
      "$rideId": {
        ".read": "auth != null && root.child('rideAccess').child($rideId).child(auth.uid).val() === true",
        ".write": "false"
      }
    },
    "rideRequests": {
      "$driverId": {
        ".read": "auth != null && auth.uid === $driverId",
        ".write": "false"
      }
    }
  }
}
```

## Performance Notes

- Passenger and driver primarily read `tripLocations/{rideId}/latest`
- `recent` is bounded and optional for interpolation/debugging
- Don't read full trip history on reconnect; use `latest` and authoritative Firestore ride state
