# ORA — Disaster Recovery Runbook

## Failure Scenarios and Recovery

### Scenario 1: Cloud Run Instance Failure

**Detection:** Cloud Monitoring — health check failures; increased error rate  
**RTO:** < 30 seconds (auto-scaling replaces instances)  
**RPO:** 0 (stateless service)

**Recovery:**
- Auto: Cloud Run auto-restarts and scales
- Manual: `gcloud run services update ora-ride-engine --region asia-south1 --min-instances 2`
- Verify: hit `/health` endpoint; check latency dashboard

---

### Scenario 2: Redis Memorystore Failure

**Detection:** Alert on `redis.connection_failures > 0`  
**RTO:** < 5 minutes  
**RPO:** Ephemeral (acceptable — GEO index rebuilt; locks released by TTL)

**Recovery:**
1. Cloud Run: automatic Redis reconnect (exponential backoff, max 30s)
2. GEO index: rebuilt as drivers ping location updates after recovery
3. Locks: contention optimization unavailable; Firestore transaction remains correctness barrier
4. Durable idempotency store remains available; Redis cache hint is skipped
5. Dispatch may be temporarily degraded/unavailable rather than scanning the entire driver population
6. After Redis recovery: geo index and wave dispatch return to normal automatically

**Preventive:** Memorystore Standard HA (replica) for production.

---

### Scenario 3: Firestore Outage

**Detection:** Alert on Firestore write/read errors  
**RTO:** < 4 hours (Firestore SLA)  
**RPO:** < 1 minute (Firestore is multi-region)

**Recovery:**
1. Active trips: drivers and passengers see "reconnecting" state
2. New rides: cannot be created; show "Service temporarily unavailable"
3. Kill switch: Remote Config `rides_enabled: false` → block new bookings
4. RTDB: live trips still GPS-streaming (RTDB is independent)
5. On Firestore recovery: all listeners reconnect; latest state delivered
6. Post-incident: reconcile any rides stuck in non-terminal states

---

### Scenario 4: Firebase Auth Outage

**Detection:** 401 errors on all API calls  
**RTO:** < 1 hour (Google SLA)

**Recovery:**
1. Cached tokens: Flutter uses cached valid token up to expiry (1 hour)
2. Token refresh fails: user must wait or use cached state
3. No new logins during outage
4. Kill switch: Remote Config `auth_required: false` for ops emergency (NEVER for production rides)

---

### Scenario 5: Google Maps API Outage

**Detection:** Pricing estimates failing; route not rendered  
**RTO:** < 2 hours (Google SLA)

**Recovery:**
1. Pricing: return error `PRICING_UNAVAILABLE`; passenger shown estimated range from historical data
2. Maps tiles: Flutter SDK cached tiles render; new tiles fail gracefully
3. Autocomplete: fallback to recent places + saved places only
4. Route polyline: not shown; basic map still works

---

### Scenario 6: FCM Outage

**Detection:** Driver request delivery failure rate > 10%  
**RTO:** FCM SLA ~ 1 hour

**Recovery:**
1. RTDB is the PRIMARY channel — FCM is supplementary
2. Drivers with RTDB listener active still receive requests
3. Background drivers: miss requests until app reopens
4. Log FCM failure metrics; do not depend on FCM for correctness

---

### Scenario 7: Complete Region Failure (asia-south1)

**Detection:** All services unreachable  
**RTO:** < 24 hours  
**RPO:** < 15 minutes (multi-region Firestore)

**Recovery:**
1. Firestore: already multi-region (nam5 or custom multi-region)
2. Cloud Run: deploy to backup region (asia-southeast1)
3. Redis: lose ephemeral data; rebuild from driver check-ins
4. RTDB: single-region loss — acceptable for ephemeral data
5. Update DNS: point `api.ora.app` to backup region load balancer
6. Notify users: maintenance mode message

---

## Rollback Procedure

### Rolling Back a Cloud Run Deployment

```bash
# List recent revisions
gcloud run revisions list --service ora-ride-engine --region asia-south1

# Roll back to previous revision (split traffic instantly)
gcloud run services update-traffic ora-ride-engine \
  --to-revisions=ora-ride-engine-00042-xyz=100 \
  --region asia-south1
```

### Rolling Back Firestore Rules

```bash
git revert {commit-hash}
firebase deploy --only firestore:rules
```

### Rolling Back Flutter App

- Google Play: use phased rollout; halt rollout at 0%
- Apple App Store: phased rollout; no instant rollback; expedited review for critical fix
- Remote Config: use feature flags to disable broken features without app update

### Feature Flags (Remote Config)

```
rides_enabled: true | false
marketplace_mode_enabled: true | false
courier_enabled: true | false
intercity_enabled: true | false
payment_digital_enabled: true | false
minimum_app_version: "1.0.0"
force_update_required: false
maintenance_mode: false
maintenance_message: ""
```

Any feature can be remotely disabled without a new app build.
