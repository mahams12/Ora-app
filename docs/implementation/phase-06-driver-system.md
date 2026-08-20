# Phase 6 — Driver System

**Status:** NOT STARTED  
**Dependencies:** Phase 3

## Objectives

Driver onboarding, document upload, admin review, approval, driver home screen, go-online/offline.

## Key Implementation Points

- 4-step onboarding wizard (personal → vehicle → documents → pending)
- Document upload: client gets signed URL from server; uploads directly to GCS
- Server stores GCS path; document accessible only via server-generated signed URLs
- Admin review panel (web-based; Phase 15 or earlier if admin is priority)
- On approval: server sets `driverStatus: "approved"` + custom claim
- Driver home screen: map + online/offline toggle + earnings summary
- Go-online: `POST /v1/drivers/go-online` → validates approval → adds to Redis GEO → RTDB presence
- Go-offline: `POST /v1/drivers/go-offline` → removes from Redis GEO → RTDB offline

## Acceptance Criteria

- [ ] Onboarding 4-step flow completes without crash
- [ ] Documents upload successfully via signed URL
- [ ] `driverStatus: "pending"` after submission
- [ ] Admin can approve documents (even via Firebase console in Phase 6)
- [ ] `driverStatus: "approved"` + custom claim set after approval
- [ ] Driver home screen renders only after approval
- [ ] Go-online adds to Redis GEO index (verifiable via Redis CLI)
- [ ] Go-offline removes from Redis GEO
- [ ] RTDB presence updates correctly on go-online/offline
- [ ] Driver app shows correct earnings (all Rs 0 initially)
- [ ] Unit test: document status state machine
