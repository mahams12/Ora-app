# Mobile E2E / Physical-Verification Troubleshooting

**Status:** CURRENT (2026-10-14)
**Scope:** `uiautomator`-driven harnesses under `mobile/.e2e_artifacts/` (physical device + emulator). For backend symptoms see [`BACKEND_TROUBLESHOOTING.md`](BACKEND_TROUBLESHOOTING.md).

These are **harness** failure modes observed on the SM-A325F (passenger) and `emulator-5554` / Pixel_9_Pro (driver) — none indicated an app defect.

---

## Symptom: smoke test "misses" Places suggestions / review never reached (MAP-3 `I_map1Smoke`)

**Root cause (all harness-side):**

1. **Single-shot dump raced reverse-geocode** — GPS + Places `searchNearby` resolves pickup in >4s; a one-shot `uiautomator dump` at a fixed sleep misses the `Confirm pickup` proposal card.
2. **a11y viewport clip** — rendered cards below the fold are **absent from the dump** even though visible on screen (proven by screenshot vs dump comparison).
3. **Positional `EditText` targeting** — `edits[1]` assumed two fields; when the pickup field left the tree the *only* remaining EditText was the destination.
4. **Wrong `input text` escape** — only `%s`→space is unescaped; `Liberty%20Market` types literally.
5. **Stale review predicate** — `Google Map`/`Map preview` labels exist on the *compose* pane only; the *review* pane exposes `Select a ride` / `Trip summary`.

**Fix pattern (see `mobile/.e2e_artifacts/map2a_physical.py`):** poll for cards, scroll the sheet to expose below-fold a11y nodes, pick the last/sole-empty EditText, use `%s` escapes, match review-pane markers.

Evidence: `MAP3_I_MAP1SMOKE_CLOSEOUT_REPORT.json`.

---

## Symptom: automation stalls at DRIVER_ASSIGNED / can't reach assigned ride detail

**Root cause:** driver progression controls live under **drawer → My trips → assigned ride card**, not on the Open rides tab (`driver_shell_view.dart`). Tapping a top-level "My trips" label does nothing — it is a non-actionable title.

**Fix pattern:** tap `Menu` (drawer) → tap `My trips` drawer item → tap the card whose merged desc is `<jobTitle> | <STATE> | <pickup> → <dest>` (e.g. `Assigned — head to pickup | DRIVER_ASSIGNED | …`); the rideId is *not* in the a11y text — match by pickup locality or job-title prefix (`driverJobTitle` in `driver_display.dart`).

Evidence: `TWO_ACTOR_LIFECYCLE_RATINGS_CLOSEOUT.json`, `lr_d_rate_nav_trips_closed.xml`.

---

## Symptom: tap "does nothing" on a visible label

**Root cause:** merged semantics put the label on a non-clickable `View` heading *and* a `Button` sibling (e.g. "Submit offer" heading vs button). Tapping the first text match hits the heading.

**Fix pattern:** prefer nodes with `clickable="true"` whose desc *starts with* the label (`tap_button` helper in `two_actor_lifecycle_ratings_e2e.py`).

---

## Symptom: `uiautomator dump` exits 137 / "null root node"

**Root cause:** transient uiautomator/adb hiccup — worse on emulator, and made worse by concurrent adb commands against the same device while a harness runs.

**Fix pattern:** retry the dump a few times before failing; don't run manual `adb` on a device while a harness run is in flight.

---

## Symptom: app lands on "Signing you in…" / phone-auth mid-run

**Root cause:** cold restart or expired session between taps (emulator relaunch, process kill, screen lock).

**Fix pattern:** detect splash/sign-in, wait, re-auth via the EditText bounds (not hardcoded coordinates — layout shifts), then re-navigate to the target screen (`reauth_if_needed` + `open_driver_assigned_detail` recovery in `two_actor_lifecycle_ratings_e2e.py`).

---

## Symptom: Samsung screen locked mid-run, dumps show only clock/status bar

**Fix pattern:** tiny systemui-only dumps indicate lock; wake + swipe-unlock + relaunch, then re-dump (`wake_unlock` in the harness).

---

## Driver offer/discovery notes

- Open-ride cards merge a11y to `Respond to ride request` only — no rideId/destination text. Confirm identity via backend snapshot (`scripts/e2e_ride_snapshot.ts <rideId>`), not UI text.
- `isOpenDiscoverable` only returns unassigned, non-expired `SEARCHING`/`OFFERS_AVAILABLE` rides — a visible card on a fresh feed is the live ride.
- Feed load can lag app relaunch — poll + pull-to-refresh before declaring discovery empty.

---

## Symptom: every screen shows "Something went wrong" / ride create fails at review

**Check staging health first** — 2026-10-19: this exact presentation was caused by the staging API being down (billing disabled; see [`BACKEND_TROUBLESHOOTING.md`](BACKEND_TROUBLESHOOTING.md)). The app error screen was correct behavior — not a harness or app defect.

---

## Wait-clock / NO_SHOW notes (2026-10-19)

- The passenger wait-clock **exists in app code** — do not rebuild it. `DRIVER_ARRIVED` → "Driver has arrived" + `Waiting Xm Ys` from server `arrivedAt` (1 Hz `arrivedNow` clock); `NO_SHOW` → "No-show recorded" terminal + "no fees invented". Backend rule: `RIDE_NO_SHOW_WAIT_MS = 5min`, sweep `POST /v1/internal/rides/no-show-sweep` (staging cron `*/5 * * * *`).
- Harness `no_show_wait_clock_e2e.py` drives request → assign → EN_ROUTE → ARRIVED → wait for scheduled sweep → NO_SHOW terminal capture. Its 2026-10-19 run was BLOCKED by the staging outage (`no_show_run1.out`, `two_actor_lifecycle_ratings_report_noshow_blocked.json`).
- **Import caveat:** `two_actor_lifecycle_ratings_e2e.py::fail()` writes `two_actor_lifecycle_ratings_report.json` (a tracked artifact). A script that imports it and fails mid-run **overwrites committed evidence** — preserve the new report under a distinct name and `git checkout` the original (done 2026-10-19 for `two_actor_lifecycle_ratings_report_noshow_blocked.json`).

---

## Symptom: `ORA_FRAME` emits zero samples even with the flag set

**Root cause (2026-10-19):** `bool.fromEnvironment('ORA_FRAME_TIMING')` accepts **only** the string `"true"`. `ORA_FRAME_TIMING=1` silently evaluates to `false` — the logger is never installed (this caused the prior debug build's "0 FrameTiming samples" gap).

**Fix:** `--dart-define=ORA_FRAME_TIMING=true` — profile mode required for reliable `FrameTiming` (`flutter build apk --profile`). 856 samples captured on SM-A325F; see `PROFILE_FRAME_TIMING_MAP_REPORT.json`.

**Note:** with staging down, a local `/v1/auth/me` stub (`stub_auth_api.py` + `adb reverse tcp:8081` + `ORA_API_BASE_URL=http://127.0.0.1:8081/v1` + `ORA_ALLOW_HTTP_API=true`) unblocks the auth gate without any app-code change.

## Symptom: "Use current location" always lands on "Location selected" (no place name)

**Root cause (2026-10-19, corrected after key audit):** `places.googleapis.com` returns **HTTP 403** on-device (`PlaceSearchFailureKind.network`, logged via `debugPrint('reverseGeocode soft-fail: …')`). Two separate issues found:

1. **Wrong key embedded in old builds:** `l1_build_ux.out` shows `ORA_GOOGLE_PLACES_API_KEY` was set to `AIzaSyD7c36…` — the **Firebase "Android key (auto created)"** (uid `1dda0eb6`), whose apiTargets are Firebase services only → `API_KEY_SERVICE_BLOCKED`. Always build with the key from `android/local.properties` `ORA_GOOGLE_PLACES_API_KEY` (`AIzaSyCdEpWc…`, console name "API key ", uid `c86457a2`) — its apiTargets include `places.googleapis.com` and the service is enabled.
2. **Project billing disabled (the real blocker):** with the correct key, `searchNearby`/`autocomplete` still 403 `PERMISSION_DENIED` — and so does `routes.googleapis.com` via the "Ora Routes Server" key. `gcloud billing projects describe ora-app-d8112` → `billingEnabled: false`; linked billing account `01F8D7-D18C5B-52F1F4` is **closed** (`open: false`). Paid Maps Platform calls fail project-wide while billing is off — same root cause as the staging Cloud Run outage. Geocoding API additionally not enabled (but not needed — Places New covers reverse geocode).

**Fix is in GCP Console (owner):** link `ora-app-d8112` to an open billing account, then rebuild with the correct `ORA_GOOGLE_PLACES_API_KEY` and re-test. No key-restriction change was needed — narrowing apiTargets was attempted and GCP correctly refused: the key has recent `geocoding-backend` usage by another consumer, so restrictions were left untouched.

**Diagnose on-device:** `adb logcat | grep reverseGeocode` → `soft-fail: PlaceSearchFailureKind.network — … (HTTP 403)` = key rejection; `empty` = no place found (now retried once at 2 km before failing).

**App-side behavior (since 2026-10-19):** GPS coords are always preserved; on failure the proposal card shows "Location selected" + "Couldn't fetch a place name — your exact position is still used." + "Retry name lookup" (name-only retry, never re-runs GPS, Confirm pickup stays enabled).

## Symptom: map raster tail on SM-A325F (rasterMs p95 ~19ms)

**Confirmed contributor (2026-10-19 A/B):** 3D tilt + building extrusions. Same profile APK, same gesture battery: raster p95 18.84→14.82ms, max 61.56→28.66ms, total p95 37.33→20.09ms with them off. Mitigation shipped: 3D/buildings apply only in expanded mode; post-fit tilt uses `moveCamera` (was a second 450ms `animateCamera` — `CameraUpdate.newLatLngBounds` resets tilt to 0, so the animation was a redundant extra raster pass). Steady-state tile rendering still dominates the raster median (~7-9ms) — not separately isolated.

**Build parity gotcha:** profile APK must get `--dart-define=MAPLIBRE_TILE_KEY=$(grep ^MAPLIBRE_TILE_KEY android/local.properties | cut -d= -f2)` or the compose map shows "Map preview unavailable · tile key not configured" and frame samples don't exercise tiles.

**Regression observed + fixed (2026-10-19, this is a build flag, not a code bug):** the "Map preview not available — key not configured" shell appeared on ad-hoc stub/debug builds because those raw `flutter build apk` invocations passed only `ORA_API_BASE_URL`/`ORA_ALLOW_HTTP_API` and omitted `MAPLIBRE_TILE_KEY`. `MapPreviewConfig.hasTileKey` resolves `MAPLIBRE_TILE_KEY` (or alias `ORA_MAPTILER_API_KEY`) from dart-defines at **build time** — `local.properties` is NOT read at runtime. Verified fix on SM-A325F: rebuild debug APK with `--dart-define=MAPLIBRE_TILE_KEY=$(awk -F= '/^MAPLIBRE_TILE_KEY=/{print substr($0,index($0,"=")+1); exit}' android/local.properties)` (plus the stub defines + `ORA_GOOGLE_PLACES_API_KEY`) → compose renders dark MapTiler tiles, pickup/destination pins, 3D toggle; full pickup→destination confirm flow verified. Evidence: `p3_map_preview_fixed.png`, `p3_map_preview_tiles.png`. **To avoid recurrence:** always build via `mobile/scripts/build_staging_apk.sh` (auto-injects `MAPLIBRE_TILE_KEY` + `ORA_GOOGLE_PLACES_API_KEY` from `local.properties`), or when using raw `flutter build` copy the full define set — including `MAPLIBRE_TILE_KEY` — from that script.

---

## Realtime smoothness Phase 1 notes (2026-10-19)

- **Driver marker interpolation (MAP-RT)** lives in `driver_marker_interpolator.dart` + `active_ride_map.dart` — presentation-only. Marker position = `_displayDriver` (interpolated); camera policy still reads the raw authoritative fix (`_driverLatLng`). Snap conditions: ≥150m jump, `locationStreamId` change, seq regression, stale/expired/ineligible data, ride-state transition, recenter, init. Segment duration 700ms; ticker only runs while a segment is active. If the marker ever looks "stuck": the interpolator is fed only via `didUpdateWidget`/init — a fix that never reaches `TripLocationSession.latest` (freshness gate, listener off-state) won't render; check `session.freshness` first.
- **FCM ride nudge (NOTIF-RIDE-NUDGE):** `DispatchFcmService.rideNudges` emits for any non-invite message with non-empty `data.rideId` (or `ride_id`); `eventId`/`delivery_event_id` dedupes via the shared 200-entry seen set. VMs debounce 500ms into one extra `refresh()` per burst — polling schedule untouched. **There is no backend ride-state push today** — the projector is dispatch-invite-only; nudges stay inert until backend sends `{data:{rideId,eventId}}`. When testing the client path without backend pushes, `fcmRideNudgeProvider` can be overridden with a synthetic stream (see `active_ride_view_model_test.dart` group "FCM ride nudge").
- **Physical measurement gap:** marker-smoothness and push→visible latency can't be measured while staging is down (no live ride / RTDB stream / backend push). Re-run after billing is restored; the two-actor harness pattern (`two_actor_lifecycle_ratings_e2e.py`) is the closest template.
- **Pre-existing test debt:** `ride_history_ui_test.dart` fails 2 tests at HEAD ("Completed" appears twice — filter chip + ride-card status badge — vs `findsOneWidget`). Unrelated to Phase 1; fix by scoping the finder or renaming the badge label in a separate change.
