# DRIVER OFFER GATE — TARGETED RETRY REPORT

**Time (UTC):** 2026-09-28 ~08:35–08:38  
**APK:** 2026-09-28 debug (unchanged) · **Backend:** UP · **No code changes**

---

## 1. Fresh rideId

| Attempt | Result |
|---------|--------|
| **Target** | One new open ride for offer test |
| **Latest in Firestore** | `56b16e49-5fc6-47da-bb5d-04ea02005ef7` (created `2026-09-28T08:19:15Z`) |
| **New ride this retry** | **NO** — fast automation did not complete pricing + request |
| **Previous correlated ride** | `03f8825a-9f70-4a35-83fd-c57801dde969` (expired) |

**TTL:** `56b16e49…` **expiresAt** `2026-09-28T08:24:15Z` → **expired** before driver offer could complete. Open-ride API excludes it.

---

## 2. Driver discovered ride

| Check | Result |
|-------|--------|
| Open Ride Requests (earlier evidence) | **YES** — Liberty / Rs 310 card with **Respond** (`cont_disc.xml`, bounds `[53,622][1028,1546]`) |
| This quick retry (Samsung low-battery run) | **Not confirmed** — UI dump did not show open-list ride (expired + navigation) |

---

## 3. Respond action

| Step | Result |
|------|--------|
| **Sheet opened?** | **NO** |
| Methods tried | UiAutomator hierarchy parse; taps at card bottom `(540, y2-40)`, center, lower-third; `Earn on ORA` → **Open ride requests** |
| Post-tap hierarchy | Still open-rides list (`og_offer2.xml`, `cont_offer2.xml`) — **no** `Submit offer` / `Accept passenger price` / `Amount (minor units)` |
| Evidence | `og_respond_fail.png` (if generated), `quick_sam.xml`, `driver_offer_gate.out` |

**Node (when ride was live):**

- **Class:** `android.widget.Button` (merged semantics — **entire card**, not isolated Respond control)
- **clickable/enabled:** `true` / `true`
- **bounds:** `[53,622][1028,1546]`
- **Recommended tap band:** x≈540, y≈**1496** (bottom of card)

---

## 4. Offer submitted

| Field | Value |
|-------|--------|
| offerId | — |
| Firestore offers count | **0** |
| HTTP / backend log | Not reached (no sheet) |

---

## 5. Passenger received offer

**NO** — no `Select` on emulator offers screen; no durable offer.

---

## 6. Failure evidence (short)

- `RuntimeError: pricing not loaded on passenger review` in `driver_offer_gate.py` (emulator stuck **Price TBD**, **Retry pricing** not reached by scroll/tap in time).
- Samsung **monkey**/launcher misfocus during some attempts (non-`com.ora.ora` dumps).
- **Merged a11y tree:** one `Button` node for full ride card + **Respond** label — coordinate taps did **not** open `showModalBottomSheet` (`driver_open_rides_view.dart` → `_openOfferSheet`).

---

## 7. Root cause classification

| Layer | Assessment |
|-------|------------|
| **BACKEND** | **Unlikely** — discovery worked when ride was non-expired; `offers: []` because POST never fired |
| **APP bug** | **Possible (UI/semantics)** — merged card button vs real `OraButton` hit target; needs **manual Respond** or semantics fix |
| **AUTOMATION** | **Primary** — expired TTL, slow passenger pricing path, imprecise taps under merged node |
| **Verdict** | **AUTOMATION + UI (accessibility/hit-testing)** |

---

## 8. Files changed

**NONE** (QA/ops only). Ops scripts: `driver_offer_gate.py`, `offer_gate_retry.py`.

---

## 9. Final verdict

## **DRIVER OFFER: RED**

Not **GREEN** — Firestore never showed `offers count = 1`.

---

## Fastest manual proof (when phone is charged)

1. **Emulator:** one ride → **Waiting for offers** (note `rideId` from backend within **5 min**).
2. **Samsung:** Driver → **Open ride requests** → **tap Respond** (physical tap on gold button).
3. **Accept passenger price** → **Submit offer** (use minor units in field if shown — P2 UX).
4. Re-check: `e2e_ride_snapshot.ts <rideId>` → `offers.length === 1`; emulator → **Select**.

**Charge Samsung first** — keep screen-on time minimal; one ride TTL is **5 minutes**.
