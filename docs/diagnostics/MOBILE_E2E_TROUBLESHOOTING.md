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
