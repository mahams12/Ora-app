# ORA Admin Platform — Frontend Screen Inventory

**Status:** DRAFT for review — reconciled 2026-11-24 — **inventory only, no UI design**
**Date:** 2026-11-24
**Boundary:** no visual design, navigation, or components are specified here. Each screen lists its functional purpose and the backend capabilities it consumes. Design references will be supplied separately; final UI must match Ora branding (navy/gold/teal, Sora/Inter — per `docs/ORA_CURRENT_STATE.md` MK1 notes).

**App shape (assumption to confirm — D-15):** separate admin web app (`admin-web/`) authenticating via Firebase Auth and calling `/v1/admin/*` only.

---

## 1. Authentication & shell

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F1 | Admin sign-in | Firebase Auth (phone OTP or email — decision); lands on dashboard | Firebase Auth only |
| F2 | Access denied / inactive operator | Shown when token valid but no active `adminOperators` record | `GET /v1/admin/me` → 403 |
| F3 | App shell / navigation | Role-filtered nav (permissions drive menu visibility — cosmetic only) | `/v1/admin/me` permissions |

## 2. Dashboard

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F4 | Overview dashboard | KPI cards (users, drivers by status, rides today, pending queues), trend charts, ops health | `GET /dashboard/summary`, `/timeseries`, `/operations` |
| F5 | Operations live view | Active rides by state/city/age; online driver count; outbox backlog | `GET /dashboard/operations`, `GET /rides?state=…` |

## 3. Users

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F6 | User search & list | Query by phone/uid/name; filters: role, status, dates; paginated table | `GET /admin/users` |
| F7 | User 360 detail | Profile, linked driver/vendor, ride history tabs, activity timeline, admin notes (internal, `adminUserNotes`) | `GET /admin/users/:uid`, `/rides`, `/activity`, `/notes` |
| F8 | Account action dialogs | Suspend/reactivate/ban/unban/deactivate with mandatory reason + active-ride warning | `POST /admin/users/:uid/{suspend,reactivate,ban,unban,deactivate}` |

## 4. Drivers

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F9 | Application review queue | Pending list sorted oldest-first, aging badges | `GET /admin/drivers/applications` |
| F10 | Application detail / review | Full application: identity, license, vehicle, **text KYC fields** (CNIC/license numbers, masked→unmask with `drivers.review.pii`; **no document images in V1** — D-04 Option A approved), `applicationVersion` shown, approve/reject/request-info/reopen actions — all require `expectedApplicationVersion` in the request; stale-review 409 triggers refetch+retry UX | `GET …/applications/:id`, `POST …/{approve,reject,request-info,reopen}` |
| F11 | Driver directory | All drivers filterable by status/availability/city/category | `GET /admin/drivers` |
| F12 | Driver 360 detail | Profile + vehicle + availability + stats + ride history + ratings + suspension metadata | `GET /admin/drivers/:id`, `/rides`, `/ratings` |
| F13 | Driver action dialogs | Suspend (reason + optional end date), reactivate, force-offline, edit operational fields | `POST …/{suspend,reactivate,force-offline}`, `PATCH …/:id` |

## 5. Rides (operations)

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F14 | Ride search & list | Cross-user ride search, filters (state, serviceType, category, city, date, fare) | `GET /admin/rides` |
| F15 | Ride detail | Full ride doc + state timeline (`rideEvents`) + offers + dispatch waves + settlement/dispute summary; force-cancel action | `GET /admin/rides/:id`, `POST …/force-cancel` |
| F16 | Active rides monitor | Non-terminal rides with age/city — ops wallboard view | `GET /admin/rides/active`, `/dashboard/operations` |

## 6. Vendors (Phase 3 — spec approved via D-02; gated on marketplace backend)

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F17 | Vendor application queue | Mirror of driver review queue for `vendors` statuses | future `/admin/vendors/applications` |
| F18 | Vendor 360 | Business profile, documents, listings, status actions | future `/admin/vendors/:id` |
| F19 | Vendor directory & actions | List/filter/suspend/reactivate | future `/admin/vendors*` |

## 7. Categories & configuration

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F20 | Category manager | List/create/edit/activate-deactivate categories by kind | `GET/POST/PATCH /admin/categories` |
| F21 | Pricing rules editor | View/edit `pricingRules` per city×category (versioned) | `GET/PUT /admin/pricing-rules` |
| F22 | Fee policy editor | Commission/fee policy management (finance permission) | `GET/PUT /admin/fee-policies` |
| F23 | City catalog | Activate/deactivate cities, display names | `GET/PUT /admin/cities` |
| F24 | Delivery/courier config | Limits, dispute window, feature toggles | `GET/PUT /admin/delivery-config` |
| F25 | Platform settings (Phase 2) | Feature flags via `platformConfig` | future `/admin/platform-config` |

## 8. Disputes, reports & moderation

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F26 | Dispute queue | Open courier disputes, aging | `GET /admin/disputes` |
| F27 | Dispute detail & resolution | Context + resolve/dismiss with note | `GET /admin/disputes/:id`, `POST …/resolve` |
| F28 | Reports queue (Phase 3) | User-submitted reports | future `/admin/reports*` |
| F29 | Moderation cases (Phase 3) | Content/account moderation | future |

## 9. Notifications (Phase 2)

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F30 | Announcement composer | Broadcast to audience segments, schedule | `POST/GET /admin/announcements` |
| F31 | Send notification to user | Single-user push with audit | `POST /admin/users/:uid/notify` |

## 10. Admin management & audit

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F32 | Operator management | List/grant/update/disable admin operators (super_admin) | `/admin/operators*` |
| F33 | Audit log viewer | Searchable audit trail by actor/action/target/date | `GET /admin/audit-logs` |
| F34 | My permissions / session | Current role + permissions + **step-up re-auth trigger** (fresh Firebase re-auth when `auth_time` exceeds threshold → `STEP_UP_REQUIRED` retry flow) | `GET /admin/me` |

## 11. Reports & analytics

| # | Screen | Purpose | Backend |
|---|---|---|---|
| F35 | Standard reports | Driver performance, city activity, cancellation analysis | `GET /admin/reports/:report` |
| F36 | Financial overview (future) | Revenue/commission/payout summaries | gated by `finance.read` |

---

## 12. Screen → permission quick map

| Screen group | Minimum permissions |
|---|---|
| F4–F5 dashboard | `dashboard.read` |
| F6–F8 users | `users.read` (+`users.read_pii`, `users.suspend/ban/deactivate` for actions) |
| F9–F13 drivers | `drivers.review.read`/`drivers.read` (+decision perms) |
| F14–F16 rides | `rides.read` (+`rides.cancel`) |
| F17–F19 vendors | `vendors.read`/`vendors.review.read` (+`vendors.approve/reject/review/suspend/write`) |
| F20–F25 config | `config.read`/`config.write` (+`finance.read`/`finance.write`) |
| F26–F27 disputes | `disputes.read`/`disputes.write` |
| F28–F29 reports/moderation | `reports.read`/`reports.write`/`moderation.write` |
| F30–F31 notifications | `notifications.read`/`notifications.write` |
| F32 operators | `operators.read`/`operators.write` |
| F33 audit | `audit.read` |
| F35–F36 reports | `dashboard.read`/`dashboard.read_financial`/`finance.read` |

## 13. Out-of-scope surfaces (not admin screens)

- **Driver-facing application status** lives in the **mobile app**, not the admin panel: `GET /v1/drivers/application-status` backs a driver status screen showing current review state, info-requested notice + what to fix, rejection reason, and resubmission path. Push notifications are supplementary only — status must be readable in-app at all times.

## 14. Explicit non-goals (v1 UI)

- No raw database browser/console — ever.
- No bulk-action grids (approve 50 at once) — v1 is single-target.
- No document image viewing/editing — **no KYC images exist in V1** (D-04 Option A approved: text-only KYC, no paid Storage); text KYC fields only.
- No fare/payment editing on rides — read-only financial context.
- No real-time dashboards — refresh-on-load.
