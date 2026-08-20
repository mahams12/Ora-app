# Phase 12 — Safety

**Status:** NOT STARTED  
**Dependencies:** Phase 10

## Objectives

Share trip, emergency contacts, SOS, route deviation, verify driver.

## Key Implementation Points

- Share trip: server generates signed JWT URL; accessible without login
- Emergency contacts: encrypted Firestore subcollection; max 5
- SOS: one-tap; server creates safetyEvent; FCM to safety team
- Route deviation: server-side every 60s; threshold 300m warning, 1km alert
- Verify driver: shows approved document photo + plate; mismatch → create safetyEvent
- Silent alert: shake gesture → SOS confirmation (with dismiss window)

## Acceptance Criteria

- [ ] Share trip URL works in browser without login
- [ ] URL shows live driver position (5s refresh)
- [ ] URL expires 30 min after trip completion
- [ ] Emergency contacts saved (encrypted); max 5 enforced
- [ ] SOS creates safetyEvent in Firestore
- [ ] SOS sends FCM to safety team phone (test notification)
- [ ] Route deviation > 300m logged
- [ ] Route deviation > 1km shows passenger alert in UI
- [ ] Verify driver shows correct approved photo and plate
- [ ] Mismatch creates safetyEvent and allows ride cancellation
