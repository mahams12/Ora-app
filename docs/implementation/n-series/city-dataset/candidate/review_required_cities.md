# REVIEW_REQUIRED Cities — Complete Decision Table

**Status:** CANDIDATE ambiguity review — **NOT APPROVED** — **NOT SEEDED**

**Source package:** Slice 2A candidate from PBS Census 2023 Table 2

**Rule:** Recommended treatment is advisory for product/ops. It is **not** a silent final decision.

Allowed recommended-treatment labels: `DIRECT` | `COALESCE` | `MERGE_WITH_PARENT` | `EXCLUDE_FROM_CITY_CATALOG` | `REVIEW_REQUIRED`

## Category breakdown

| Category | Code | Count |
| -------- | ---- | ----- |
| Cantonments | A | 55 |
| Metropolitan / municipal split | B | 2 |
| Other "Part of…" records | C | 0 |
| Duplicate canonical IDs | D | 9 |
| University / institutional township | E | 1 |
| Other special cases | F | 0 |
| **Total** | | **67** |

## Complete table (all 67)

| # | PBS source locality | Province/region | District | Tehsil / part-of | Pop 2023 | Source row | Proposed parent | Candidate ID | Why REVIEW_REQUIRED | Recommended treatment | Confidence | DISPLAY_NAME_PROPOSAL |
| - | ------------------- | --------------- | -------- | ---------------- | -------- | ---------- | --------------- | ------------ | ------------------- | --------------------- | ---------- | --------------------- |
| 1 | WALTON CANTONMENT | Punjab | LAHORE DISTRICT | — | 810,739 | 27 | `lahore` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `lahore` for pickup-city UX (not a separate Ora city) | LOW | Walton |
| 2 | RAWALPINDI CANTONMENT | Punjab | RAWALPINDI DISTRICT | — | 740,483 | 30 | `rawalpindi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) | LOW | Rawalpindi |
| 3 | LAHORE CANTONMENT | Punjab | LAHORE DISTRICT | — | 443,314 | 55 | `lahore` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `lahore` for pickup-city UX (not a separate Ora city) | LOW | Lahore |
| 4 | WAH CANTONMENT | Punjab | RAWALPINDI DISTRICT | — | 400,733 | 57 | `rawalpindi` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Wah is often treated as its own town vs Rawalpindi suburb — product must choose | LOW | Wah |
| 5 | CHAKLALA CANTONMENT | Punjab | RAWALPINDI DISTRICT | — | 333,115 | 63 | `rawalpindi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) | LOW | Chaklala |
| 6 | FAISAL CANTONMENT (Part of Gulshan-e-Iqbal Sub-Division) | Sindh | KARACHI EAST DISTRICT | Gulshan-e-Iqbal Sub-Division | 289,473 | 69 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Faisal |
| 7 | CLIFTON CANTONMENT (Part of Civil Lines Sub-Division) | Sindh | KARACHI SOUTH DISTRICT | Civil Lines Sub-Division | 196,813 | 96 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Clifton |
| 8 | SARGODHA CANTONMENT | Punjab | SARGODHA DISTRICT | — | 190,188 | 101 | `sargodha` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `sargodha` for pickup-city UX (not a separate Ora city) | LOW | Sargodha |
| 9 | QUETTA CANTONMENT | Balochistan | QUETTA DISTRICT | — | 164,184 | 111 | `quetta` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `quetta` for pickup-city UX (not a separate Ora city) | LOW | Quetta |
| 10 | ABBOTTABAD CANTONMENT | Khyber Pakhtunkhwa | ABBOTTABAD DISTRICT | — | 159,683 | 113 | `abbottabad` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `abbottabad` for pickup-city UX (not a separate Ora city) | LOW | Abbottabad |
| 11 | GUJRANWALA CANTONMENT | Punjab | GUJRANWALA DISTRICT | — | 156,929 | 115 | `gujranwala` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `gujranwala` for pickup-city UX (not a separate Ora city) | LOW | Gujranwala |
| 12 | MALIR CANTONMENT (Part of Airport Sub-Division) | Sindh | MALIR DISTRICT | Airport Sub-Division | 106,089 | 164 | `malir` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` | LOW | Malir |
| 13 | BAHAWALPUR CANTONMENT | Punjab | BAHAWALPUR DISTRICT | — | 88,593 | 190 | `bahawalpur` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `bahawalpur` for pickup-city UX (not a separate Ora city) | LOW | Bahawalpur |
| 14 | MALIR CANTONMENT (Part of Gulzar-e-Hijri Sub-Division) | Sindh | KARACHI EAST DISTRICT | Gulzar-e-Hijri Sub-Division | 88,335 | 193 | `karachi-east` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Suggested parent `karachi-east` is admin/district-shaped; passenger merge target is likely `karachi` | LOW | Malir |
| 15 | SIALKOT CANTONMENT | Punjab | SIALKOT DISTRICT | — | 76,480 | 215 | `sialkot` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `sialkot` for pickup-city UX (not a separate Ora city) | LOW | Sialkot |
| 16 | KARACHI CANTONMENT (Part of Sadar Sub-Division) | Sindh | KARACHI SOUTH DISTRICT | Sadar Sub-Division | 68,097 | 242 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Karachi |
| 17 | KAMRA CANTONMENT | Punjab | ATTOCK DISTRICT | — | 67,425 | 244 | `attock` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) | LOW | Kamra |
| 18 | OKARA CANTONMENT | Punjab | OKARA DISTRICT | — | 65,590 | 253 | `okara` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `okara` for pickup-city UX (not a separate Ora city) | LOW | Okara |
| 19 | PESHAWAR CANTONMENT | Khyber Pakhtunkhwa | PESHAWAR DISTRICT | — | 63,978 | 257 | `peshawar` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `peshawar` for pickup-city UX (not a separate Ora city) | LOW | Peshawar |
| 20 | TAXILA CANTONMENT | Punjab | RAWALPINDI DISTRICT | — | 61,456 | 264 | `rawalpindi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) | LOW | Taxila |
| 21 | KHARIAN CANTONMENT | Punjab | GUJRAT DISTRICT | — | 58,523 | 271 | `gujrat` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `gujrat` for pickup-city UX (not a separate Ora city) | LOW | Kharian |
| 22 | HYDERABAD CANTONMENT (Part of Hyderabad City Taluka) | Sindh | HYDERABAD DISTRICT | Hyderabad City Taluka | 52,827 | 289 | `hyderabad` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) | LOW | Hyderabad |
| 23 | KORANGI CREEK CANTONMENT (Part of Korangi Sub-Division) | Sindh | KORANGI DISTRICT | Korangi Sub-Division | 52,186 | 296 | `korangi` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Suggested parent `korangi` is admin/district-shaped; passenger merge target is likely `karachi` | LOW | Korangi Creek |
| 24 | MULTAN CANTONMENT | Punjab | MULTAN DISTRICT | — | 45,466 | 330 | `multan` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `multan` for pickup-city UX (not a separate Ora city) | LOW | Multan |
| 25 | CLIFTON CANTONMENT (Part of Saddar Sub-Division) | Sindh | KARACHI SOUTH DISTRICT | Saddar Sub-Division | 43,507 | 343 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Clifton |
| 26 | HYDERABAD CANTONMENT (Part of Latifabad Taluka) | Sindh | HYDERABAD DISTRICT | Latifabad Taluka | 39,190 | 373 | `hyderabad` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) | LOW | Hyderabad |
| 27 | HAVELIAN CANTONMENT | Khyber Pakhtunkhwa | ABBOTTABAD DISTRICT | — | 37,509 | 387 | `abbottabad` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `abbottabad` for pickup-city UX (not a separate Ora city) | LOW | Havelian |
| 28 | RISALPUR CANTONMENT | Khyber Pakhtunkhwa | NOWSHERA DISTRICT | — | 36,074 | 401 | `nowshera` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `nowshera` for pickup-city UX (not a separate Ora city) | LOW | Risalpur |
| 29 | NOWSHERA CANTONMENT | Khyber Pakhtunkhwa | NOWSHERA DISTRICT | — | 34,481 | 417 | `nowshera` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `nowshera` for pickup-city UX (not a separate Ora city) | LOW | Nowshera |
| 30 | ATTOCK CANTONMENT | Punjab | ATTOCK DISTRICT | — | 33,718 | 423 | `attock` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) | LOW | Attock |
| 31 | KOHAT CANTONMENT | Khyber Pakhtunkhwa | KOHAT DISTRICT | — | 31,051 | 438 | `kohat` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `kohat` for pickup-city UX (not a separate Ora city) | LOW | Kohat |
| 32 | FAISAL CANTONMENT (Part of Airport Sub-Division) | Sindh | MALIR DISTRICT | Airport Sub-Division | 30,981 | 439 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Faisal |
| 33 | FAISAL CANTONMENT (Part of Shah Faisal Sub-Division) | Sindh | KORANGI DISTRICT | Shah Faisal Sub-Division | 30,064 | 449 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Faisal |
| 34 | PANO AQIL CANTONMENT | Sindh | SUKKUR DISTRICT | — | 25,759 | 497 | `sukkur` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `sukkur` for pickup-city UX (not a separate Ora city) | LOW | Pano Aqil |
| 35 | MALIR CANTONMENT (Part of Murad Memon Sub-Division) | Sindh | MALIR DISTRICT | Murad Memon Sub-Division | 23,065 | 523 | `malir` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` | LOW | Malir |
| 36 | JHELUM CANTONMENT | Punjab | JHELUM DISTRICT | — | 21,404 | 539 | `jhelum` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `jhelum` for pickup-city UX (not a separate Ora city) | LOW | Jhelum |
| 37 | SHORKOT CANTONMENT (Part of Shorkot Tehsil) | Punjab | JHANG DISTRICT | Shorkot Tehsil | 20,246 | 548 | `jhang` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `jhang` for pickup-city UX (not a separate Ora city) | LOW | Shorkot |
| 38 | MANGLA CANTONMENT | Punjab | JHELUM DISTRICT | — | 19,129 | 564 | `jhelum` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `jhelum` for pickup-city UX (not a separate Ora city) | LOW | Mangla |
| 39 | KORANGI CREEK CANTONMENT (Part of Ibrahim Hydri Sub-Division) | Sindh | MALIR DISTRICT | Ibrahim Hydri Sub-Division | 17,398 | 589 | `malir` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` | LOW | Korangi Creek |
| 40 | KARACHI CANTONMENT (Part of Jamshed Quarters Sub-Division) | Sindh | KARACHI EAST DISTRICT | Jamshed Quarters Sub-Division | 15,577 | 602 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Karachi |
| 41 | SHORKOT CANTONMENT (Part of Pirmahal Tehsil) | Punjab | TOBA TEK SINGH DISTRICT | Pirmahal Tehsil | 12,081 | 624 | `toba-tek-singh` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `toba-tek-singh` for pickup-city UX (not a separate Ora city) | LOW | Shorkot |
| 42 | SANJWAL CANTONMENT | Punjab | ATTOCK DISTRICT | — | 11,751 | 626 | `attock` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) | LOW | Sanjwal |
| 43 | MURREE HILLS CANTONMENT | Punjab | RAWALPINDI DISTRICT | — | 8,869 | 643 | `rawalpindi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) | LOW | Murree Hills |
| 44 | BANNU CANTONMENT | Khyber Pakhtunkhwa | BANNU DISTRICT | — | 7,383 | 646 | `bannu` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `bannu` for pickup-city UX (not a separate Ora city) | LOW | Bannu |
| 45 | DERA ISMAIL KHAN CANTONMENT | Khyber Pakhtunkhwa | DERA ISMAIL KHAN DISTRICT | — | 6,819 | 647 | `dera-ismail-khan` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `dera-ismail-khan` for pickup-city UX (not a separate Ora city) | LOW | Dera Ismail Khan |
| 46 | HYDERABAD CANTONMENT (Part of Qasimabad Taluka) | Sindh | HYDERABAD DISTRICT | Qasimabad Taluka | 6,402 | 649 | `hyderabad` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) | LOW | Hyderabad |
| 47 | CLIFTON CANTONMENT (Part of Korangi Sub-Division) | Sindh | KORANGI DISTRICT | Korangi Sub-Division | 5,623 | 653 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Clifton |
| 48 | MARDAN CANTONMENT | Khyber Pakhtunkhwa | MARDAN DISTRICT | — | 4,514 | 657 | `mardan` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `mardan` for pickup-city UX (not a separate Ora city) | LOW | Mardan |
| 49 | LORALAI CANTONMENT | Balochistan | LORALAI DISTRICT | — | 2,988 | 662 | `loralai` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `loralai` for pickup-city UX (not a separate Ora city) | LOW | Loralai |
| 50 | MANORA CANTONMENT (Part of Keamari Sub-Division) | Sindh | KEAMARI DISTRICT | Keamari Sub-Division | 2,956 | 663 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Manora |
| 51 | ORMARA CANTONMENT | Balochistan | GWADAR DISTRICT | — | 2,784 | 664 | `ormara` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — Ormara Cantonment vs Ormara town / Gwadar — confirm parent | LOW | Ormara |
| 52 | ZHOB CANTONMENT | Balochistan | ZHOB DISTRICT | — | 2,725 | 665 | `zhob` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `zhob` for pickup-city UX (not a separate Ora city) | LOW | Zhob |
| 53 | KARACHI CANTONMENT (Part of Civil Lines Sub-Division) | Sindh | KARACHI SOUTH DISTRICT | Civil Lines Sub-Division | 2,664 | 666 | `karachi` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) | LOW | Karachi |
| 54 | CHERAT CANTONMENT | Khyber Pakhtunkhwa | NOWSHERA DISTRICT | — | 1,311 | 667 | `—` | `—` | Cantonment — no auto city / no silent merge | **REVIEW_REQUIRED** — No clear passenger-facing parent / specialty military site | LOW | Cherat |
| 55 | MURREE GALLIES CANTONMENT | Khyber Pakhtunkhwa | ABBOTTABAD DISTRICT | — | 784 | 668 | `murree` | `—` | Cantonment — no auto city / no silent merge | **MERGE_WITH_PARENT** — Proposal only: treat as part of `murree` for pickup-city UX (not a separate Ora city) | LOW | Murree Gallies |
| 56 | SUKKUR MUNICIPAL CORPORATION (Part of New Sukkur Taluka) | Sindh | SUKKUR DISTRICT | New Sukkur Taluka | 296,743 | 66 | `—` | `—` | Municipal Corporation Part-of split without approved coalesce rule | **COALESCE** — Proposal only: Sukkur MC taluka parts → one passenger city `sukkur` (same pattern as Hyderabad) | LOW | Sukkur |
| 57 | SUKKUR MUNICIPAL CORPORATION (Part of Sukkur City Taluka) | Sindh | SUKKUR DISTRICT | Sukkur City Taluka | 267,108 | 75 | `—` | `—` | Municipal Corporation Part-of split without approved coalesce rule | **COALESCE** — Proposal only: Sukkur MC taluka parts → one passenger city `sukkur` (same pattern as Hyderabad) | LOW | Sukkur |
| 58 | SAHIWAL METROPOLITAN CORPORATION | Punjab | SAHIWAL DISTRICT | — | 538,344 | 46 | `—` | `sahiwal` | DUPLICATE_CANONICAL_ID → `sahiwal` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Sahiwal |
| 59 | KHANPUR MC | Punjab | RAHIM YAR KHAN DISTRICT | — | 247,170 | 77 | `—` | `khanpur` | DUPLICATE_CANONICAL_ID → `khanpur` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Khanpur |
| 60 | SAHIWAL MC | Punjab | SARGODHA DISTRICT | — | 57,374 | 275 | `—` | `sahiwal` | DUPLICATE_CANONICAL_ID → `sahiwal` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Sahiwal |
| 61 | KHANGARH TC | Sindh | GHOTKI DISTRICT | — | 32,648 | 432 | `—` | `khangarh` | DUPLICATE_CANONICAL_ID → `khangarh` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Khangarh |
| 62 | KHANGARH MC | Punjab | MUZAFFARGARH DISTRICT | — | 32,161 | 434 | `—` | `khangarh` | DUPLICATE_CANONICAL_ID → `khangarh` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Khangarh |
| 63 | KARAMPUR TC | Punjab | VEHARI DISTRICT | — | 27,840 | 470 | `—` | `karampur` | DUPLICATE_CANONICAL_ID → `karampur` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Karampur |
| 64 | HYDERABAD TC | Punjab | BHAKKAR DISTRICT | — | 25,319 | 502 | `—` | `hyderabad` | DUPLICATE_CANONICAL_ID → `hyderabad` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Hyderabad |
| 65 | KARAMPUR TC | Sindh | KASHMORE DISTRICT | — | 20,050 | 552 | `—` | `karampur` | DUPLICATE_CANONICAL_ID → `karampur` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Karampur |
| 66 | KHANPUR TC | Sindh | SHIKARPUR DISTRICT | — | 18,052 | 579 | `—` | `khanpur` | DUPLICATE_CANONICAL_ID → `khanpur` | **REVIEW_REQUIRED** — Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes | LOW | Khanpur |
| 67 | PESHAWAR UNIVERSITY TC | Khyber Pakhtunkhwa | PESHAWAR DISTRICT | — | 4,256 | 658 | `—` | `—` | University / institutional TC | **EXCLUDE_FROM_CITY_CATALOG** — Proposal only: university township unlikely as passenger pickup-city selector row | LOW | Peshawar University |

## A. Cantonments (55)

Policy constraint from Slice 2A: do **not** auto-create `*-cantonment` Ora cities; do **not** silently merge.

| Cantonment | District | Pop 2023 | Suggested parent | Recommended treatment | Reason |
| ---------- | -------- | -------- | ---------------- | --------------------- | ------ |
| WALTON CANTONMENT | LAHORE DISTRICT | 810,739 | `lahore` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `lahore` for pickup-city UX (not a separate Ora city) |
| RAWALPINDI CANTONMENT | RAWALPINDI DISTRICT | 740,483 | `rawalpindi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) |
| LAHORE CANTONMENT | LAHORE DISTRICT | 443,314 | `lahore` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `lahore` for pickup-city UX (not a separate Ora city) |
| WAH CANTONMENT | RAWALPINDI DISTRICT | 400,733 | `rawalpindi` | **REVIEW_REQUIRED** | Wah is often treated as its own town vs Rawalpindi suburb — product must choose |
| CHAKLALA CANTONMENT | RAWALPINDI DISTRICT | 333,115 | `rawalpindi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) |
| FAISAL CANTONMENT (Part of Gulshan-e-Iqbal Sub-Division) | KARACHI EAST DISTRICT | 289,473 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| CLIFTON CANTONMENT (Part of Civil Lines Sub-Division) | KARACHI SOUTH DISTRICT | 196,813 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| SARGODHA CANTONMENT | SARGODHA DISTRICT | 190,188 | `sargodha` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `sargodha` for pickup-city UX (not a separate Ora city) |
| QUETTA CANTONMENT | QUETTA DISTRICT | 164,184 | `quetta` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `quetta` for pickup-city UX (not a separate Ora city) |
| ABBOTTABAD CANTONMENT | ABBOTTABAD DISTRICT | 159,683 | `abbottabad` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `abbottabad` for pickup-city UX (not a separate Ora city) |
| GUJRANWALA CANTONMENT | GUJRANWALA DISTRICT | 156,929 | `gujranwala` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `gujranwala` for pickup-city UX (not a separate Ora city) |
| MALIR CANTONMENT (Part of Airport Sub-Division) | MALIR DISTRICT | 106,089 | `malir` | **REVIEW_REQUIRED** | Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` |
| BAHAWALPUR CANTONMENT | BAHAWALPUR DISTRICT | 88,593 | `bahawalpur` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `bahawalpur` for pickup-city UX (not a separate Ora city) |
| MALIR CANTONMENT (Part of Gulzar-e-Hijri Sub-Division) | KARACHI EAST DISTRICT | 88,335 | `karachi-east` | **REVIEW_REQUIRED** | Suggested parent `karachi-east` is admin/district-shaped; passenger merge target is likely `karachi` |
| SIALKOT CANTONMENT | SIALKOT DISTRICT | 76,480 | `sialkot` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `sialkot` for pickup-city UX (not a separate Ora city) |
| KARACHI CANTONMENT (Part of Sadar Sub-Division) | KARACHI SOUTH DISTRICT | 68,097 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| KAMRA CANTONMENT | ATTOCK DISTRICT | 67,425 | `attock` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) |
| OKARA CANTONMENT | OKARA DISTRICT | 65,590 | `okara` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `okara` for pickup-city UX (not a separate Ora city) |
| PESHAWAR CANTONMENT | PESHAWAR DISTRICT | 63,978 | `peshawar` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `peshawar` for pickup-city UX (not a separate Ora city) |
| TAXILA CANTONMENT | RAWALPINDI DISTRICT | 61,456 | `rawalpindi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) |
| KHARIAN CANTONMENT | GUJRAT DISTRICT | 58,523 | `gujrat` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `gujrat` for pickup-city UX (not a separate Ora city) |
| HYDERABAD CANTONMENT (Part of Hyderabad City Taluka) | HYDERABAD DISTRICT | 52,827 | `hyderabad` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) |
| KORANGI CREEK CANTONMENT (Part of Korangi Sub-Division) | KORANGI DISTRICT | 52,186 | `korangi` | **REVIEW_REQUIRED** | Suggested parent `korangi` is admin/district-shaped; passenger merge target is likely `karachi` |
| MULTAN CANTONMENT | MULTAN DISTRICT | 45,466 | `multan` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `multan` for pickup-city UX (not a separate Ora city) |
| CLIFTON CANTONMENT (Part of Saddar Sub-Division) | KARACHI SOUTH DISTRICT | 43,507 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| HYDERABAD CANTONMENT (Part of Latifabad Taluka) | HYDERABAD DISTRICT | 39,190 | `hyderabad` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) |
| HAVELIAN CANTONMENT | ABBOTTABAD DISTRICT | 37,509 | `abbottabad` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `abbottabad` for pickup-city UX (not a separate Ora city) |
| RISALPUR CANTONMENT | NOWSHERA DISTRICT | 36,074 | `nowshera` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `nowshera` for pickup-city UX (not a separate Ora city) |
| NOWSHERA CANTONMENT | NOWSHERA DISTRICT | 34,481 | `nowshera` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `nowshera` for pickup-city UX (not a separate Ora city) |
| ATTOCK CANTONMENT | ATTOCK DISTRICT | 33,718 | `attock` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) |
| KOHAT CANTONMENT | KOHAT DISTRICT | 31,051 | `kohat` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `kohat` for pickup-city UX (not a separate Ora city) |
| FAISAL CANTONMENT (Part of Airport Sub-Division) | MALIR DISTRICT | 30,981 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| FAISAL CANTONMENT (Part of Shah Faisal Sub-Division) | KORANGI DISTRICT | 30,064 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| PANO AQIL CANTONMENT | SUKKUR DISTRICT | 25,759 | `sukkur` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `sukkur` for pickup-city UX (not a separate Ora city) |
| MALIR CANTONMENT (Part of Murad Memon Sub-Division) | MALIR DISTRICT | 23,065 | `malir` | **REVIEW_REQUIRED** | Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` |
| JHELUM CANTONMENT | JHELUM DISTRICT | 21,404 | `jhelum` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `jhelum` for pickup-city UX (not a separate Ora city) |
| SHORKOT CANTONMENT (Part of Shorkot Tehsil) | JHANG DISTRICT | 20,246 | `jhang` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `jhang` for pickup-city UX (not a separate Ora city) |
| MANGLA CANTONMENT | JHELUM DISTRICT | 19,129 | `jhelum` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `jhelum` for pickup-city UX (not a separate Ora city) |
| KORANGI CREEK CANTONMENT (Part of Ibrahim Hydri Sub-Division) | MALIR DISTRICT | 17,398 | `malir` | **REVIEW_REQUIRED** | Suggested parent `malir` is admin/district-shaped; passenger merge target is likely `karachi` |
| KARACHI CANTONMENT (Part of Jamshed Quarters Sub-Division) | KARACHI EAST DISTRICT | 15,577 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| SHORKOT CANTONMENT (Part of Pirmahal Tehsil) | TOBA TEK SINGH DISTRICT | 12,081 | `toba-tek-singh` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `toba-tek-singh` for pickup-city UX (not a separate Ora city) |
| SANJWAL CANTONMENT | ATTOCK DISTRICT | 11,751 | `attock` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `attock` for pickup-city UX (not a separate Ora city) |
| MURREE HILLS CANTONMENT | RAWALPINDI DISTRICT | 8,869 | `rawalpindi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `rawalpindi` for pickup-city UX (not a separate Ora city) |
| BANNU CANTONMENT | BANNU DISTRICT | 7,383 | `bannu` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `bannu` for pickup-city UX (not a separate Ora city) |
| DERA ISMAIL KHAN CANTONMENT | DERA ISMAIL KHAN DISTRICT | 6,819 | `dera-ismail-khan` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `dera-ismail-khan` for pickup-city UX (not a separate Ora city) |
| HYDERABAD CANTONMENT (Part of Qasimabad Taluka) | HYDERABAD DISTRICT | 6,402 | `hyderabad` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `hyderabad` for pickup-city UX (not a separate Ora city) |
| CLIFTON CANTONMENT (Part of Korangi Sub-Division) | KORANGI DISTRICT | 5,623 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| MARDAN CANTONMENT | MARDAN DISTRICT | 4,514 | `mardan` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `mardan` for pickup-city UX (not a separate Ora city) |
| LORALAI CANTONMENT | LORALAI DISTRICT | 2,988 | `loralai` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `loralai` for pickup-city UX (not a separate Ora city) |
| MANORA CANTONMENT (Part of Keamari Sub-Division) | KEAMARI DISTRICT | 2,956 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| ORMARA CANTONMENT | GWADAR DISTRICT | 2,784 | `ormara` | **REVIEW_REQUIRED** | Ormara Cantonment vs Ormara town / Gwadar — confirm parent |
| ZHOB CANTONMENT | ZHOB DISTRICT | 2,725 | `zhob` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `zhob` for pickup-city UX (not a separate Ora city) |
| KARACHI CANTONMENT (Part of Civil Lines Sub-Division) | KARACHI SOUTH DISTRICT | 2,664 | `karachi` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `karachi` for pickup-city UX (not a separate Ora city) |
| CHERAT CANTONMENT | NOWSHERA DISTRICT | 1,311 | `None` | **REVIEW_REQUIRED** | No clear passenger-facing parent / specialty military site |
| MURREE GALLIES CANTONMENT | ABBOTTABAD DISTRICT | 784 | `murree` | **MERGE_WITH_PARENT** | Proposal only: treat as part of `murree` for pickup-city UX (not a separate Ora city) |

### Cantonment notes for product

- **Lahore cluster:** Walton + Lahore Cantonment — suggested parent `lahore` (already coalesced metro).
- **Rawalpindi cluster:** Rawalpindi + Wah + Chaklala — suggested parent `rawalpindi` (Wah is often perceived as its own town — confirm).
- **Karachi cluster:** Faisal / Clifton / Malir / Manora / Karachi Cantonments — Malir Cantt currently suggests `malir`; passenger-facing parent is likely `karachi` if merging.
- **Specialty:** Cherat (no parent), Murree Gallies (Murree vs Abbottabad), Ormara Cantt (Ormara vs Gwadar).

## B. Metropolitan / municipal splits (not yet coalesced)

- **SUKKUR MUNICIPAL CORPORATION (Part of New Sukkur Taluka)** — SUKKUR DISTRICT — pop 296,743 — row 66
- **SUKKUR MUNICIPAL CORPORATION (Part of Sukkur City Taluka)** — SUKKUR DISTRICT — pop 267,108 — row 75

Combined Sukkur MC parts population if coalesced: **563,851**

**Proposal (not approved):** `COALESCE` → `sukkur` / displayName `Sukkur` (same pattern as Hyderabad MC parts).

## C. Other Part-of records

_None in this REVIEW_REQUIRED set (Karachi/Lahore/Hyderabad/Quetta Part-of rows were already coalesced in Slice 2A)._

## D. Duplicate canonical IDs

`normalizeCitySlug` = trim + lowercase only. Multi-word shaping uses spaces→hyphens before that.
Collisions happen when **different districts** share the same cleaned base name.

### `sahiwal`

| PBS source | District | Pop | Prior decision | Display | Why same ID |
| ---------- | -------- | --- | -------------- | ------- | ----------- |
| SAHIWAL METROPOLITAN CORPORATION | SAHIWAL DISTRICT | 538,344 | DIRECT | Sahiwal | cleaned base → `sahiwal` |
| SAHIWAL MC | SARGODHA DISTRICT | 57,374 | DIRECT | Sahiwal | cleaned base → `sahiwal` |

- Sahiwal MetCorp (Sahiwal District, ~538k) vs Sahiwal MC (Sargodha District, ~57k) are **different passenger-facing places**.
- Possible approach (examples only — product must choose): keep larger as `sahiwal`; disambiguate smaller with a product-approved naming rule — **do not invent suffixes in this review**.

### `khanpur`

| PBS source | District | Pop | Prior decision | Display | Why same ID |
| ---------- | -------- | --- | -------------- | ------- | ----------- |
| KHANPUR MC | RAHIM YAR KHAN DISTRICT | 247,170 | DIRECT | Khanpur | cleaned base → `khanpur` |
| KHANPUR TC | SHIKARPUR DISTRICT | 18,052 | DIRECT | Khanpur | cleaned base → `khanpur` |

- Khanpur MC (Rahim Yar Khan, ~247k) vs Khanpur TC (Shikarpur, ~18k) — **different places**.
- Product must assign distinct canonical IDs or exclude one.

### `khangarh`

| PBS source | District | Pop | Prior decision | Display | Why same ID |
| ---------- | -------- | --- | -------------- | ------- | ----------- |
| KHANGARH TC | GHOTKI DISTRICT | 32,648 | DIRECT | Khangarh | cleaned base → `khangarh` |
| KHANGARH MC | MUZAFFARGARH DISTRICT | 32,161 | DIRECT | Khangarh | cleaned base → `khangarh` |

- Khangarh TC (Ghotki, Sindh) vs Khangarh MC (Muzaffargarh, Punjab) — **different places**.
- Product must assign distinct canonical IDs or exclude one.

### `karampur`

| PBS source | District | Pop | Prior decision | Display | Why same ID |
| ---------- | -------- | --- | -------------- | ------- | ----------- |
| KARAMPUR TC | VEHARI DISTRICT | 27,840 | DIRECT | Karampur | cleaned base → `karampur` |
| KARAMPUR TC | KASHMORE DISTRICT | 20,050 | DIRECT | Karampur | cleaned base → `karampur` |

- Karampur TC (Vehari, Punjab) vs Karampur TC (Kashmore, Sindh) — **different places**.
- Product must assign distinct canonical IDs or exclude one.

### `hyderabad`

| PBS source | District | Pop | Prior decision | Display | Why same ID |
| ---------- | -------- | --- | -------------- | ------- | ----------- |
| HYDERABAD TC | BHAKKAR DISTRICT | 25,319 | DIRECT | Hyderabad | cleaned base → `hyderabad` |

- Collision is between **coalesced Hyderabad (Sindh) metro** (kept in catalog) and **Hyderabad TC in Bhakkar District (Punjab)** (~25k).
- These are **different passenger-facing places**. Punjab TC must not steal `hyderabad` from Sindh metro. Distinct id for the TC is product-owned — **not assigned here**.

## E. University / institutional

- **PESHAWAR UNIVERSITY TC** — PESHAWAR DISTRICT — pop 4,256 — row 658
  - Recommended: **EXCLUDE_FROM_CITY_CATALOG** (proposal). Alternative: coverage via `peshawar` without a selector row.

## F. Other

_None._

## Metro coalesce validation (already in candidate catalog)

### Hyderabad (`hyderabad`)

- Source rows: **2**
- Combined population 2023: **1,487,098**
- Districts: HYDERABAD DISTRICT
- Reason: Hyderabad Municipal Corporation taluka parts → one passenger city
- Source localities:
  - row 29: HYDERABAD MUNICIPAL CORPORATION (Part of Latifabad Taluka)
  - row 31: HYDERABAD MUNICIPAL CORPORATION (Part of Hyderabad City Taluka)
- **Review verdict:** Source evidence is **consistent** with one passenger-facing city. **No change recommended** in this review (product still must formally approve).

### Karachi (`karachi`)

- Source rows: **28**
- Combined population 2023: **17,895,193**
- Districts: KARACHI CENTRAL DISTRICT, KARACHI EAST DISTRICT, KARACHI SOUTH DISTRICT, KARACHI WEST DISTRICT, KEAMARI DISTRICT, KORANGI DISTRICT, MALIR DISTRICT
- Reason: Karachi District Municipal Corporation / district parts → one passenger city
- Source localities:
  - row 13: DISTRICT MUNICIPAL CORPORATION KORANGI (Part of Korangi Sub-Division)
  - row 14: DISTRICT MUNICIPAL CORPORATION KARACHI EAST (Part of Ferozabad Sub-Division)
  - row 15: DISTRICT MUNICIPAL CORPORATION KARACHI CENTRAL (Part of New Karachi Sub-Division)
  - row 19: DISTRICT MUNICIPAL CORPORATION KARACHI EAST (Part of Gulzar-e-Hijri Sub-Division)
  - row 20: DISTRICT MUNICIPAL CORPORATION KARACHI WEST (Part of Mominabad Sub-Division)
  - row 21: DISTRICT MUNICIPAL CORPORATION KARACHI SOUTH (Part of Lyari Sub-Division)
  - row 22: DISTRICT MUNICIPAL CORPORATION KEAMARI (Part of Baldia Sub-Division)
  - row 23: DISTRICT MUNICIPAL CORPORATION KARACHI CENTRAL (Part of North Nazimabad Sub-Division)
  - row 25: DISTRICT MUNICIPAL CORPORATION KARACHI WEST (Part of Manghopir Sub-Division)
  - row 32: DISTRICT MUNICIPAL CORPORATION KARACHI EAST (Part of Gulshan-e-Iqbal Sub-Division)
  - row 33: DISTRICT MUNICIPAL CORPORATION KORANGI (Part of Landhi Sub-Division)
  - row 34: DISTRICT MUNICIPAL CORPORATION MALIR (Part of Ibrahim Hydri Sub-Division)
  - row 35: DISTRICT MUNICIPAL CORPORATION KARACHI EAST (Part of Jamshed Quarters Sub-Division)
  - row 37: DISTRICT MUNICIPAL CORPORATION KARACHI CENTRAL (Part of Gulberg Sub-Division)
  - row 38: DISTRICT MUNICIPAL CORPORATION KORANGI (Part of Shah Faisal Sub-Division)
  - row 40: DISTRICT MUNICIPAL CORPORATION KARACHI WEST (Part of Orangi Sub-Division)
  - row 43: DISTRICT MUNICIPAL CORPORATION KARACHI CENTRAL (Part of Nazimabad Sub-Division)
  - row 45: DISTRICT MUNICIPAL CORPORATION KARACHI CENTRAL (Part of Liaquatabad Sub-Division)
  - row 50: DISTRICT MUNICIPAL CORPORATION KARACHI SOUTH (Part of Garden Sub-Division)
  - row 53: DISTRICT MUNICIPAL CORPORATION KEAMARI (Part of S.I.T.E. Sub-Division)
  - row 54: DISTRICT MUNICIPAL CORPORATION KEAMARI (Part of Keamari Sub-Division)
  - row 56: DISTRICT MUNICIPAL CORPORATION KORANGI (Part of Model Colony Sub-Division)
  - row 71: DISTRICT MUNICIPAL CORPORATION KARACHI SOUTH (Part of Civil Lines Sub-Division)
  - row 79: DISTRICT MUNICIPAL CORPORATION KARACHI SOUTH (Part of Aram Bagh Sub-Division)
  - row 85: DISTRICT MUNICIPAL CORPORATION KEAMARI (Part of Mauripur Sub-Division)
  - row 94: DISTRICT MUNICIPAL CORPORATION MALIR (Part of Murad Memon Sub-Division)
  - row 150: DISTRICT MUNICIPAL CORPORATION MALIR (Part of Airport Sub-Division)
  - row 320: DISTRICT MUNICIPAL CORPORATION KARACHI SOUTH (Part of Saddar Sub-Division)
- **Review verdict:** Source evidence is **consistent** with one passenger-facing city. **No change recommended** in this review (product still must formally approve).

### Lahore (`lahore`)

- Source rows: **5**
- Combined population 2023: **11,750,082**
- Districts: LAHORE DISTRICT
- Reason: Multiple Lahore Metropolitan Corporation census parts → one passenger city
- Source localities:
  - row 5: LAHORE METROPOLITAN CORPORATION (Part of Lahore City Tehsil)
  - row 7: LAHORE METROPOLITAN CORPORATION (Part of Model Town Tehsil)
  - row 8: LAHORE METROPOLITAN CORPORATION (Part of Shalimar Tehsil)
  - row 17: LAHORE METROPOLITAN CORPORATION (Part of Raiwind Tehsil)
  - row 36: LAHORE METROPOLITAN CORPORATION (Part of Lahore Cantonment Tehsil)
- **Review verdict:** Source evidence is **consistent** with one passenger-facing city. **No change recommended** in this review (product still must formally approve).

### Quetta (`quetta`)

- Source rows: **4**
- Combined population 2023: **1,401,362**
- Districts: QUETTA DISTRICT
- Reason: Quetta Metropolitan Corporation subdivision parts → one passenger city
- Source localities:
  - row 18: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division City)
  - row 91: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Saddar Tehsil)
  - row 249: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Sariab)
  - row 303: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Kuchlak)
- **Review verdict:** Source evidence is **consistent** with one passenger-facing city. **No change recommended** in this review (product still must formally approve).

## Population distribution (candidate catalog — informational)

No population floor applied.

| Band | Candidate cities |
| ---- | ---------------- |
| <5k | 3 |
| 5k–10k | 13 |
| 10k–25k | 118 |
| 25k–50k | 184 |
| 50k–100k | 120 |
| 100k–500k | 97 |
| 500k–1m | 10 |
| >1m | 10 |
| **Total** | **555** |

## Licensing

**LICENSE_REVIEW_REQUIRED** — unchanged from Slice 2A.

## Extraction bugs

_None identified that require changing `candidate_city_catalog.json` in this slice._

Note: province/territory on provenance rows are **hints derived from district names** (national Table 2 has no province column).

