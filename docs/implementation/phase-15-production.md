# Phase 15 — Production

**Status:** NOT STARTED  
**Dependencies:** Phase 14

## Objectives

Security audit, App Store submissions, monitoring, alerts, runbooks.

## Key Activities

- Third-party security audit (penetration test)
- OWASP Mobile Top 10 checklist
- Certificate pinning evaluation
- Firestore rules review
- Secret scanner: no keys in code or history
- App Check enforcement: debug token removed from production builds
- Play Store: create app listing, upload screenshots, submit for review
- App Store: create app listing, upload screenshots, submit for review
- Cloud Monitoring dashboards activated
- PagerDuty alerts wired
- On-call runbook published
- Disaster recovery runbook tested
- Remote Config kill switches tested
- Load test at 2× expected launch traffic

## Acceptance Criteria

- [ ] Security audit: no critical or high findings unresolved
- [ ] `trufflehog` secret scan: clean
- [ ] App Check: debug provider absent from production binary
- [ ] Play Store: app approved
- [ ] App Store: app approved
- [ ] All monitoring dashboards live with real data
- [ ] PagerDuty: test alert fires and resolves correctly
- [ ] On-call runbook: reviewed by 2 engineers
- [ ] Disaster recovery: Redis failover tested in staging
- [ ] Kill switch: `rides_enabled: false` tested; blocks new rides instantly
- [ ] Load test: 2× expected traffic → no SLO violations
- [ ] All Phase 0–14 acceptance criteria re-verified in production environment

## Launch Checklist

```
□ Firebase project: production environment locked (not dev)
□ All API keys: restricted to production domains
□ Cloud Armor rules: active
□ Redis: Standard HA tier (not Basic)
□ Firestore: multi-region
□ Cloud Run: min-instances = 2 for all services
□ Crashlytics: receiving data
□ Analytics: receiving data
□ Support email / chat: configured and staffed
□ Emergency contact for safety events: staffed
□ Driver onboarding: at least 50 approved drivers in launch city
□ Legal: terms of service, privacy policy live at ora.app/legal
□ Payment PSP: production credentials activated
```
