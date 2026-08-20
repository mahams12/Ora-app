# ORA — Safety Flow

## Safety Features (from prototype)

| Feature | Prototype Reference | Priority |
|---|---|---|
| Share live trip | Safety centre — "Share live trip" toggle | Phase 12 |
| Emergency contacts | Safety centre → "Emergency contacts: 2 saved" | Phase 12 |
| Emergency SOS | Safety centre → "Emergency SOS — Alert police & Ora" | Phase 12 |
| Verify driver | Safety centre → "Verify driver — Check plate & photo" | Phase 10 |
| Route deviation detection | Server-side | Phase 12 |
| Silent alert | Hidden gesture trigger | Phase 12 |
| Support call | "Call support" button | Phase 3 (phone only) |
| In-app messaging | Driver-passenger chat | Phase 10 |

## Share Live Trip

```
1. Passenger activates "Share live trip" (toggle in Safety Centre or Live Trip screen)
2. Server generates signed share URL: https://ora.app/track/{token}
3. URL valid for duration of trip + 30 minutes
4. Passenger shares URL via system share sheet
5. Recipient opens URL in browser:
   - Shows passenger name
   - Shows driver name, plate, photo
   - Shows live map with driver position
   - Updates every 5 seconds via polling (no app required)
6. On ride terminal state: URL shows "Trip ended" state
7. URL expires 30 min after trip completion
```

## Emergency SOS

```
1. Passenger taps "Emergency SOS" button
   OR uses hidden gesture (shake × 3, or press volume up 5×)
2. [Confirmation dialog — 3 second countdown, dismiss to cancel]
3. If confirmed:
   a. Creates safetyEvent in Firestore:
      { type: "SOS", rideId, passengerId, driverId, location, timestamp }
   b. Sends FCM to Ora Safety Team
   c. [Optional] Initiates call to emergency contacts
   d. [Optional] Dials local emergency number (115 Pakistan)
4. Safety team dashboard shows alert
5. In-app: "Help is on the way" + safety team contact number
```

## Verify Driver

```
1. Passenger taps "Verify driver" during DRIVER_EN_ROUTE
2. App shows:
   - Driver photo (from approved documents)
   - Driver name
   - Vehicle make, model, colour
   - Licence plate
3. Passenger visually matches with actual driver
4. If mismatch: "This isn't my driver" → creates safety event + cancels ride
```

## Route Deviation Detection

```
Server (Cloud Run, triggered every 60s during active trip):

1. Get current driver GPS from RTDB
2. Get expected route polyline from pricingSnapshot
3. Calculate perpendicular distance from driver position to route
4. If deviation > 300m:
   a. Log deviation event
   b. Wait 90 seconds (allow for traffic rerouting)
   c. If still > 300m: send push to passenger:
      "Your driver appears to have deviated from the expected route"
   d. Create safetyEvent with severity: LOW
5. If deviation > 1km for > 3 minutes:
   a. Create safetyEvent with severity: HIGH
   b. Alert safety team
   c. Passenger shown prominent alert with SOS option
```

## Emergency Contacts

```
Storage: encrypted in Firestore users/{uid}/emergencyContacts (server access only)
Display: name + phone number + relationship

Operations:
- Add contact: PATCH /v1/users/emergency-contacts
- Remove contact: DELETE /v1/users/emergency-contacts/{contactId}
- Max 5 contacts
- Contacts notified via SMS (Twilio / local SMS gateway) on SOS trigger
```

## Safety Event Schema

```json
{
  "eventId": "sos_abc123",
  "type": "SOS" | "ROUTE_DEVIATION" | "DRIVER_MISMATCH" | "SUPPORT_REQUEST",
  "severity": "LOW" | "MEDIUM" | "HIGH" | "CRITICAL",
  "rideId": "ride_abc",
  "passengerId": "uid_xyz",
  "driverId": "drv_456",
  "location": { "lat": 31.5204, "lng": 74.3587 },
  "timestamp": "2026-08-18T07:30:00Z",
  "resolved": false,
  "resolvedAt": null,
  "resolvedBy": null,
  "notes": ""
}
```
