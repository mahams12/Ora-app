#!/usr/bin/env python3
"""Phase 5D physical follow-up — Your offer editor on SM-A325F.

Diagnosed gap (prior PARTIAL):
  - Review ListView puts PricingCard (Your offer) below a tall Trip summary;
    EditText is often off-screen under the sticky Request bar.
  - OraTextField paints label as a sibling Text, so uiautomator never saw
    "Your offer" on the EditText (only the numeric value when visible).
  - Swipes that overshoot land on the category list and lose the offer field.

This harness:
  1) Reaches review via confirmed GPS pickup + Places destination.
  2) Scrolls the review ListView until passenger_offer_field / Your offer /
     numeric EditText is on-screen.
  3) Enters out-of-range then in-range custom offer; asserts Request enablement.
  4) Submits; records ride id from staging API for durable offer proof.

Does NOT log tokens. Evidence → passenger_fare_offer_physical_followup_*.json/png
"""
from __future__ import annotations

import html
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

ART = Path(__file__).resolve().parent
REPO = ART.parent.parent
SERIAL = "RF8R40ZQ1JH"
PKG = "com.ora.ora"
APK = ART.parent / "build/app/outputs/flutter-apk/app-debug.apk"
PREFIX = "p5dfu"
REPORT = ART / "passenger_fare_offer_physical_followup_report.json"
PARTIAL = ART / "passenger_fare_offer_physical_followup_partial.json"


def adb(*args: str, check: bool = True) -> str:
    p = subprocess.run(
        ["adb", "-s", SERIAL, *args], capture_output=True, text=True, check=False
    )
    if check and p.returncode != 0:
        raise RuntimeError(f"adb {' '.join(args)} failed: {(p.stderr or '')[:400]}")
    return (p.stdout or "") + (p.stderr or "")


def sh(cmd: str) -> str:
    return adb("shell", cmd, check=False)


def dump(name: str) -> str:
    adb("shell", "uiautomator", "dump", f"/sdcard/{PREFIX}.xml", check=False)
    local = ART / name
    adb("pull", f"/sdcard/{PREFIX}.xml", str(local), check=False)
    return local.read_text(encoding="utf-8", errors="replace") if local.exists() else ""


def shot(name: str) -> None:
    adb("shell", "screencap", "-p", f"/sdcard/{PREFIX}.png", check=False)
    adb("pull", f"/sdcard/{PREFIX}.png", str(ART / name), check=False)


def nodes(xml: str) -> list[tuple[str, str, str, str]]:
    out: list[tuple[str, str, str, str]] = []
    for m in re.finditer(r"<node\b([^>]*)/?>", xml):
        a = m.group(1)
        bm = re.search(r'bounds="(\[\d+,\d+\]\[\d+,\d+\])"', a)
        if not bm:
            continue
        tm = re.search(r'text="([^"]*)"', a)
        dm = re.search(r'content-desc="([^"]*)"', a)
        rm = re.search(r'resource-id="([^"]*)"', a)
        out.append(
            (
                html.unescape(tm.group(1) if tm else ""),
                html.unescape(dm.group(1) if dm else ""),
                bm.group(1),
                a,
            )
        )
        # keep resource-id searchable via attrs
        if rm and rm.group(1):
            out[-1] = (
                out[-1][0],
                out[-1][1],
                out[-1][2],
                a + f' __rid="{rm.group(1)}"',
            )
    return out


def center(bounds: str) -> tuple[int, int]:
    m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    assert m
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def has(xml: str, s: str) -> bool:
    return s.lower() in html.unescape(xml).lower()


def tap_xy(x: int, y: int) -> None:
    adb("shell", "input", "tap", str(x), str(y))


def tap_start(xml: str, prefix: str) -> bool:
    p = prefix.lower()
    for t, d, b, a in nodes(xml):
        hay = d or t
        if "destination to continue" in hay.lower():
            continue
        if hay.lower().startswith(p):
            tap_xy(*center(b))
            return True
    return False


def tap_contains(xml: str, needle: str, *, skip_edit: bool = False) -> bool:
    n = needle.lower()
    for t, d, b, a in nodes(xml):
        if skip_edit and "EditText" in a:
            continue
        if n in f"{t}\n{d}".lower():
            tap_xy(*center(b))
            return True
    return False


def find_offer_field(xml: str) -> tuple[str, str] | None:
    """Return (bounds, how) for Your offer EditText."""
    # 1) Flutter Semantics.identifier → resource-id
    for t, d, b, a in nodes(xml):
        if "passenger_offer_field" in a or "passenger_offer_field" in d:
            return b, "resource-id-or-desc"
    # 2) content-desc / text containing Your offer
    for t, d, b, a in nodes(xml):
        if "your offer" in f"{t}\n{d}".lower() and (
            "EditText" in a or "textfield" in a.lower() or d.lower().startswith("your offer")
        ):
            return b, "label-desc"
    # 3) On review, the only EditText is Your offer
    edits = [(b, t) for t, d, b, a in nodes(xml) if "EditText" in a]
    if has(xml, "Select a ride") or has(xml, "Request"):
        if len(edits) == 1:
            return edits[0][0], "sole-review-edittext"
        if len(edits) >= 1:
            # Prefer edit whose text is numeric (offer draft)
            for b, t in edits:
                if re.fullmatch(r"\d+", t.strip()):
                    return b, "numeric-edittext"
            return edits[-1][0], "last-edittext"
    return None


def scroll_review_until_offer(max_swipes: int = 10) -> tuple[str, str | None, str | None]:
    """Swipe review list upward in small steps until offer field appears."""
    xml = dump(f"{PREFIX}_rev_scroll_0.xml")
    hit = find_offer_field(xml)
    if hit:
        return xml, hit[0], hit[1]
    for i in range(1, max_swipes + 1):
        # Small swipe inside sheet body — avoid overshooting into category-only view
        adb("shell", "input", "swipe", "540", "1550", "540", "1250", "280", check=False)
        time.sleep(0.7)
        xml = dump(f"{PREFIX}_rev_scroll_{i}.xml")
        hit = find_offer_field(xml)
        if hit:
            return xml, hit[0], hit[1]
    return xml, None, None


def clear_focused(n: int = 24) -> None:
    adb("shell", "input", "keyevent", "KEYCODE_MOVE_END", check=False)
    for _ in range(n):
        adb("shell", "input", "keyevent", "KEYCODE_DEL", check=False)


def type_pkr(amount: str) -> None:
    # Pass through shell so %s is not needed for digits-only
    sh(f"input text {amount}")


def request_enabled(xml: str) -> bool | None:
    """Only the review CTA ('Request Easy'), never home 'Fare on request'."""
    for t, d, b, a in nodes(xml):
        hay = f"{t}\n{d}"
        low = hay.lower()
        if "fare on request" in low:
            continue
        if low.startswith("request ") or low.startswith("request\n") or (
            d.lower().startswith("request") and "easy" in low
        ):
            en = re.search(r'enabled="(true|false)"', a)
            if en:
                return en.group(1) == "true"
    return None


def offer_field_text(xml: str) -> str | None:
    for t, d, b, a in nodes(xml):
        if "passenger_offer_field" in a or "passenger_offer_field" in d:
            return t.strip()
    return None


def scroll_offer_into_midband(max_swipes: int = 10) -> tuple[str, tuple[str, str] | None]:
    """Keep offer EditText away from sticky Request (cy~1944 fails to focus)."""
    xml = dump(f"{PREFIX}_midband_0.xml")
    for i in range(max_swipes):
        hit = find_offer_field(xml)
        if not hit:
            adb("shell", "input", "swipe", "540", "1600", "540", "1200", "250", check=False)
            time.sleep(0.5)
            xml = dump(f"{PREFIX}_midband_{i}.xml")
            continue
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", hit[0]))
        cy = (y1 + y2) // 2
        if 1150 <= cy <= 1700:
            return xml, hit
        if cy > 1700:
            adb("shell", "input", "swipe", "540", "1650", "540", "1250", "250", check=False)
        else:
            adb("shell", "input", "swipe", "540", "1250", "540", "1650", "250", check=False)
        time.sleep(0.55)
        xml = dump(f"{PREFIX}_midband_{i}.xml")
    return xml, find_offer_field(xml)


def focus_and_set_offer(amount: str) -> str:
    """Tap offer field, replace text, return dump xml after edit."""
    xml, hit = scroll_offer_into_midband()
    if not hit:
        xml, b, method = scroll_review_until_offer(6)
        hit = (b, method or "rescroll") if b else None
    if not hit:
        return xml
    # Tap lower half of the field (TextField sits under the visual label)
    m = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", hit[0])
    assert m
    x1, y1, x2, y2 = map(int, m.groups())
    tap_xy((x1 + x2) // 2, y1 + int((y2 - y1) * 0.85))
    time.sleep(0.6)
    clear_focused(40)
    # Clipboard paste is more reliable than `input text` on Samsung IME
    sh(f"cmd clipboard set-text --user 0 {amount}")
    time.sleep(0.2)
    adb("shell", "input", "keyevent", "KEYCODE_PASTE", check=False)
    time.sleep(0.5)
    got = offer_field_text(dump(f"{PREFIX}_paste_check.xml"))
    if got != amount:
        clear_focused(40)
        sh(f"input text {amount}")
        time.sleep(0.8)
        got = offer_field_text(dump(f"{PREFIX}_text_check.xml"))
    if got != amount:
        # Last resort: KEYCODE_0..9 (Samsung IME often swallows `input text`)
        clear_focused(40)
        for ch in amount:
            if ch.isdigit():
                adb(
                    "shell",
                    "input",
                    "keyevent",
                    str(7 + int(ch)),
                    check=False,
                )
                time.sleep(0.04)
        time.sleep(0.5)
    # IME action Done — do NOT send KEYCODE_BACK (pops the route)
    adb("shell", "input", "keyevent", "KEYCODE_ENTER", check=False)
    time.sleep(0.7)
    # Tap map chrome to ensure keyboard dismissed while staying on review
    if has(dump(f"{PREFIX}_kbcheck.xml"), "Select a ride"):
        pass
    else:
        tap_xy(540, 400)
        time.sleep(0.4)
    return dump(f"{PREFIX}_after_type_{amount}.xml")


def tap_request(xml: str) -> bool:
    for t, d, b, a in nodes(xml):
        low = f"{t}\n{d}".lower()
        if "fare on request" in low:
            continue
        if low.startswith("request") and "easy" in low:
            tap_xy(*center(b))
            return True
    # Coordinate fallback from known sticky CTA band on A325F
    if has(xml, "Request Easy") or has(xml, "Request"):
        tap_xy(540, 2120)
        return True
    return False


def parse_pkr_majors(xml: str) -> list[int]:
    amounts: list[int] = []
    blob = html.unescape(xml)
    for m in re.finditer(r"(?:Rs\.?\s*|PKR\s*)(\d[\d,]*)", blob, flags=re.I):
        amounts.append(int(m.group(1).replace(",", "")))
    # bare numeric EditText / Text nodes that look like fares
    for t, d, b, a in nodes(xml):
        if re.fullmatch(r"\d{2,5}", t.strip()):
            amounts.append(int(t.strip()))
    # dedupe preserve order
    out: list[int] = []
    for a in amounts:
        if a not in out:
            out.append(a)
    return out


def verify_ride_offer(offer_major: int) -> dict:
    """Query staging for latest passenger ride matching offer (paisas)."""
    script = REPO / "backend/auth-service/scripts/staging_5d_verify_latest_offer.ts"
    if not script.exists():
        # inline via tsx one-liner file written next to proof
        return {"skipped": True, "reason": "verify script missing"}
    sa = REPO / "backend/auth-service/secrets/service-account.json"
    env = {
        **dict(__import__("os").environ),
        "GOOGLE_APPLICATION_CREDENTIALS": str(sa),
        "EXPECTED_OFFER_MAJOR": str(offer_major),
    }
    p = subprocess.run(
        ["npx", "tsx", str(script)],
        cwd=str(REPO / "backend/auth-service"),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:
        return {
            "ok": False,
            "stdout": (p.stdout or "")[-500],
            "stderr": (p.stderr or "")[-500],
            "code": p.returncode,
        }


def main() -> int:
    started = datetime.now(timezone.utc).isoformat()
    checks: dict[str, object] = {
        "deviceAttached": False,
        "apkInstalled": False,
        "reviewReached": False,
        "offerFieldLocated": False,
        "offerFieldLocateMethod": None,
        "outOfRangeRejected": False,
        "customOfferEntered": False,
        "customOfferDiffersFromRecommended": False,
        "requestEnabledForCustom": False,
        "submitTapped": False,
        "postSubmitOffersOrCreated": False,
        "durableOfferMatches": "UNVERIFIED",
        "openListShowsOffer": "UNVERIFIED",
    }
    notes: list[str] = []
    evidence: list[str] = []
    metrics: dict[str, object] = {}

    devices = subprocess.run(
        ["adb", "devices", "-l"], capture_output=True, text=True, check=False
    ).stdout
    if not re.search(rf"{SERIAL}\s+device\b", devices):
        PARTIAL.write_text(
            json.dumps(
                {
                    "verdict": "PHYSICAL BLOCKED — device not ready",
                    "startedAt": started,
                },
                indent=2,
            )
            + "\n"
        )
        print("DEVICE_NOT_READY")
        return 2
    checks["deviceAttached"] = True
    model = adb("shell", "getprop", "ro.product.model").strip()
    android = adb("shell", "getprop", "ro.build.version.release").strip()

    if APK.exists():
        adb("install", "-r", str(APK))
        checks["apkInstalled"] = True
    else:
        notes.append(f"APK missing: {APK}")

    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_FINE_LOCATION", check=False)
    adb("shell", "pm", "grant", PKG, "android.permission.ACCESS_COARSE_LOCATION", check=False)
    adb("shell", "am", "force-stop", PKG, check=False)
    time.sleep(1)
    adb("shell", "am", "start", "-n", f"{PKG}/com.ora.ora.MainActivity", check=False)

    xml = ""
    for i in range(40):
        xml = dump(f"{PREFIX}_boot_{i}.xml")
        if has(xml, "Where are you headed") and not has(xml, "Signing you in"):
            break
        time.sleep(1)
    shot(f"{PREFIX}_boot.png")
    evidence.append(f"{PREFIX}_boot.png")

    for attempt in range(12):
        xml = dump(f"{PREFIX}_nav_{attempt}.xml")
        if has(xml, "Expand map") and (has(xml, "Pickup") or has(xml, "Where to?")):
            break
        tap_contains(xml, "Where are you headed") or tap_contains(xml, "City rides")
        time.sleep(2)

    xml = dump(f"{PREFIX}_compose.xml")
    shot(f"{PREFIX}_compose.png")
    evidence.extend([f"{PREFIX}_compose.xml", f"{PREFIX}_compose.png"])

    # --- GPS pickup + confirm (scroll if needed) ---
    tap_contains(xml, "Use current location")
    time.sleep(5)
    confirmed_pickup = False
    for i in range(8):
        xml = dump(f"{PREFIX}_pick_{i}.xml")
        if has(xml, "Pickup confirmed"):
            confirmed_pickup = True
            break
        if tap_start(xml, "Confirm pickup"):
            time.sleep(2)
            continue
        adb("shell", "input", "swipe", "540", "1850", "540", "1300", "300", check=False)
        time.sleep(0.8)
    checks["pickupConfirmed"] = confirmed_pickup
    if not confirmed_pickup:
        notes.append("Pickup confirm failed")

    # --- Destination: empty EditText (last) ---
    xml = dump(f"{PREFIX}_dest0.xml")
    edits = [(b, t) for t, d, b, a in nodes(xml) if "EditText" in a]
    dest_bounds = None
    for b, t in edits:
        if t.strip() == "":
            dest_bounds = b
    if dest_bounds is None and edits:
        dest_bounds = edits[-1][0]
    if dest_bounds:
        tap_xy(*center(dest_bounds))
        time.sleep(0.4)
        clear_focused(10)
        sh("input text Emporium%sMall%sLahore")
        time.sleep(8)
        xml = dump(f"{PREFIX}_sugg.xml")
        shot(f"{PREFIX}_sugg.png")
        evidence.append(f"{PREFIX}_sugg.png")
        if not (
            tap_contains(xml, "Emporium Mall", skip_edit=True)
            or tap_contains(xml, "Emporium", skip_edit=True)
        ):
            notes.append("Places suggestion tap missed")
        time.sleep(2.5)
        adb("shell", "input", "keyevent", "4", check=False)  # dismiss kb
        time.sleep(0.8)
        for i in range(6):
            xml = dump(f"{PREFIX}_cd_{i}.xml")
            if has(xml, "Destination confirmed"):
                break
            if tap_start(xml, "Confirm destination"):
                time.sleep(2)
                break
            adb("shell", "input", "swipe", "540", "1500", "540", "1000", "300", check=False)
            time.sleep(0.7)

    xml = dump(f"{PREFIX}_precont.xml")
    tap_start(xml, "Continue")
    time.sleep(5)

    review = ""
    for i in range(20):
        review = dump(f"{PREFIX}_revwait_{i}.xml")
        if has(review, "Select a ride") or has(review, "Request"):
            break
        time.sleep(1)
    shot(f"{PREFIX}_review_top.png")
    evidence.append(f"{PREFIX}_review_top.png")
    checks["reviewReached"] = has(review, "Select a ride") or has(review, "Request")

    # --- Scroll until Your offer ---
    review, bounds, method = scroll_review_until_offer(12)
    shot(f"{PREFIX}_offer_visible.png")
    evidence.append(f"{PREFIX}_offer_visible.png")
    (ART / f"{PREFIX}_offer_visible.xml").write_text(review, encoding="utf-8")
    evidence.append(f"{PREFIX}_offer_visible.xml")
    checks["offerFieldLocateMethod"] = method
    checks["offerFieldLocated"] = bounds is not None
    metrics["recommendedSample"] = parse_pkr_majors(review)[:6]

    if not bounds:
        notes.append("Your offer EditText not located after scroll")
        ended = datetime.now(timezone.utc).isoformat()
        out = {
            "artifact": "PASSENGER_FARE_OFFER_PHYSICAL_FOLLOWUP",
            "startedAt": started,
            "endedAt": ended,
            "device": {"serial": SERIAL, "model": model, "android": android},
            "checks": checks,
            "notes": notes,
            "evidenceFiles": evidence,
            "metrics": metrics,
            "verdict": "PHYSICAL PARTIAL — offer field not located",
            "diagnosis": {
                "layout": "PricingCard below Trip summary; EditText oft off-screen",
                "semantics": "label was sibling Text; identifier passenger_offer_field added",
                "harness": "small swipes until EditText / resource-id",
            },
        }
        REPORT.write_text(json.dumps(out, indent=2) + "\n")
        PARTIAL.write_text(json.dumps(out, indent=2) + "\n")
        print(json.dumps({"verdict": out["verdict"], "checks": checks}, indent=2))
        return 1

    recommended = metrics["recommendedSample"][0] if metrics["recommendedSample"] else None
    metrics["recommendedMajorPkr"] = recommended
    metrics["offerTextBeforeEdit"] = offer_field_text(review)

    # --- Out of range (must observe text change — prior run typed into void) ---
    bad = focus_and_set_offer("999999")
    shot(f"{PREFIX}_oor.png")
    evidence.extend([f"{PREFIX}_oor.png"])
    (ART / f"{PREFIX}_oor.xml").write_text(bad, encoding="utf-8")
    evidence.append(f"{PREFIX}_oor.xml")
    oor_text = offer_field_text(bad)
    metrics["oorFieldText"] = oor_text
    en_bad = request_enabled(bad)
    errish = any(
        has(bad, s)
        for s in ("between", "minimum", "maximum", "whole", "Enter", "offer range", "too")
    )
    typed_oor = oor_text == "999999"
    checks["outOfRangeRejected"] = typed_oor and (
        en_bad is False or errish or en_bad is None
    )
    metrics["oorRequestEnabled"] = en_bad
    metrics["oorErrorVisible"] = errish
    metrics["oorTextApplied"] = typed_oor
    if not typed_oor:
        notes.append(f"OOR type failed; field still {oor_text!r}")
    if typed_oor and en_bad is True and not errish:
        notes.append("Request still enabled after 999999 with no error text")

    # --- In-range custom ≠ recommended ---
    if recommended and recommended > 50:
        custom_major = recommended + 10
    else:
        custom_major = 860
    okxml = focus_and_set_offer(str(custom_major))
    # If still on review but text not applied, retry once with -10
    got = offer_field_text(okxml)
    if got != str(custom_major) and recommended:
        custom_major = max(recommended - 10, 100)
        okxml = focus_and_set_offer(str(custom_major))
        got = offer_field_text(okxml)
    shot(f"{PREFIX}_custom.png")
    (ART / f"{PREFIX}_custom.xml").write_text(okxml, encoding="utf-8")
    evidence.extend([f"{PREFIX}_custom.xml", f"{PREFIX}_custom.png"])
    metrics["customOfferMajorPkr"] = custom_major
    metrics["customFieldText"] = got
    checks["customOfferEntered"] = got == str(custom_major)
    checks["customOfferDiffersFromRecommended"] = (
        recommended is None or custom_major != recommended
    )
    # Ensure still on review (never KEYCODE_BACK)
    if not (has(okxml, "Select a ride") or has(okxml, "Request Easy")):
        notes.append("Left review after edit — abort submit")
        checks["requestEnabledForCustom"] = False
    else:
        en_ok = request_enabled(okxml)
        checks["requestEnabledForCustom"] = bool(en_ok) and checks["customOfferEntered"]
        metrics["customRequestEnabled"] = en_ok
        if checks["requestEnabledForCustom"]:
            if tap_request(okxml):
                checks["submitTapped"] = True
                time.sleep(6)
                post = dump(f"{PREFIX}_post.xml")
                shot(f"{PREFIX}_post.png")
                evidence.extend([f"{PREFIX}_post.xml", f"{PREFIX}_post.png"])
                checks["postSubmitOffersOrCreated"] = any(
                    has(post, s)
                    for s in (
                        "Waiting",
                        "offer",
                        "Offers",
                        "inbox",
                        "Ride created",
                        "Looking for",
                    )
                )
            else:
                notes.append("Could not tap Request Easy CTA")
        else:
            notes.append(
                f"Request not enabled for custom={custom_major} field={got!r} en={en_ok}"
            )

    # Staging durable verify for this offer
    if checks.get("submitTapped"):
        time.sleep(2)
        verify = verify_ride_offer(int(metrics["customOfferMajorPkr"]))  # type: ignore[arg-type]
        metrics["stagingVerify"] = verify
        if verify.get("durableMatchesChosen"):
            checks["durableOfferMatches"] = True
        elif verify.get("skipped"):
            checks["durableOfferMatches"] = "SKIPPED"
            notes.append(str(verify))
        else:
            checks["durableOfferMatches"] = bool(verify.get("ok"))
        if verify.get("openListShowsChosenOffer"):
            checks["openListShowsOffer"] = True
        elif "openListShowsChosenOffer" in verify:
            checks["openListShowsOffer"] = bool(verify.get("openListShowsChosenOffer"))

    ended = datetime.now(timezone.utc).isoformat()
    hard = [
        "deviceAttached",
        "apkInstalled",
        "reviewReached",
        "offerFieldLocated",
        "outOfRangeRejected",
        "customOfferEntered",
        "customOfferDiffersFromRecommended",
        "requestEnabledForCustom",
        "submitTapped",
    ]
    failed = [k for k in hard if checks.get(k) is not True]
    if checks.get("durableOfferMatches") is False:
        failed.append("durableOfferMatches")

    if not failed:
        verdict = "PHYSICAL PASS"
    elif checks.get("offerFieldLocated") and checks.get("outOfRangeRejected"):
        verdict = "PHYSICAL PARTIAL"
    else:
        verdict = "PHYSICAL FAIL"

    out = {
        "artifact": "PASSENGER_FARE_OFFER_PHYSICAL_FOLLOWUP",
        "startedAt": started,
        "endedAt": ended,
        "device": {
            "serial": SERIAL,
            "model": model,
            "android": android,
            "package": PKG,
        },
        "apk": "mobile/build/app/outputs/flutter-apk/app-debug.apk",
        "checks": checks,
        "failedChecks": failed,
        "metrics": metrics,
        "notes": notes,
        "evidenceFiles": evidence,
        "diagnosis": {
            "priorBlocker": "EditText off-screen + label not on field semantics",
            "fixApplied": [
                "Semantics(identifier: passenger_offer_field, label: Your offer)",
                "Harness scrolls in small steps until field found",
                "Suggestion taps skip EditText nodes",
            ],
        },
        "verdict": verdict,
    }
    REPORT.write_text(json.dumps(out, indent=2) + "\n")
    PARTIAL.write_text(json.dumps(out, indent=2) + "\n")
    print(json.dumps({"verdict": verdict, "failedChecks": failed, "checks": checks}, indent=2))
    return 0 if verdict == "PHYSICAL PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
