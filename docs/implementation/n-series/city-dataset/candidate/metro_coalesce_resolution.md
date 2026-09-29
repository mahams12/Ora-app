# Metropolitan Coalesce Resolution (Slice 2C)

**Status:** Engineering evidence review — **NOT PRODUCT APPROVED**

Sukkur must not be assumed merely because other metros coalesced.

## Hyderabad (`hyderabad`) — currently COALESCED in candidate

- Source row count: 2
- Combined population 2023: **1,487,098**
- Districts: HYDERABAD DISTRICT
- Canonical ID: `hyderabad`
- Rationale: Hyderabad Municipal Corporation taluka parts → one passenger city
- Source localities:
  - row 29: HYDERABAD MUNICIPAL CORPORATION (Part of Latifabad Taluka)
  - row 31: HYDERABAD MUNICIPAL CORPORATION (Part of Hyderabad City Taluka)
- **Engineering assessment:** Source evidence consistent with one passenger-facing city.
- **Product decision status:** `PROPOSED` / awaiting formal approval (D-CITY-METRO-COALESCE)

## Karachi (`karachi`) — currently COALESCED in candidate

- Source row count: 28
- Combined population 2023: **17,895,193**
- Districts: KARACHI CENTRAL DISTRICT, KARACHI EAST DISTRICT, KARACHI SOUTH DISTRICT, KARACHI WEST DISTRICT, KEAMARI DISTRICT, KORANGI DISTRICT, MALIR DISTRICT
- Canonical ID: `karachi`
- Rationale: Karachi District Municipal Corporation / district parts → one passenger city
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
- **Engineering assessment:** Source evidence consistent with one passenger-facing city.
- **Product decision status:** `PROPOSED` / awaiting formal approval (D-CITY-METRO-COALESCE)

## Lahore (`lahore`) — currently COALESCED in candidate

- Source row count: 5
- Combined population 2023: **11,750,082**
- Districts: LAHORE DISTRICT
- Canonical ID: `lahore`
- Rationale: Multiple Lahore Metropolitan Corporation census parts → one passenger city
- Source localities:
  - row 5: LAHORE METROPOLITAN CORPORATION (Part of Lahore City Tehsil)
  - row 7: LAHORE METROPOLITAN CORPORATION (Part of Model Town Tehsil)
  - row 8: LAHORE METROPOLITAN CORPORATION (Part of Shalimar Tehsil)
  - row 17: LAHORE METROPOLITAN CORPORATION (Part of Raiwind Tehsil)
  - row 36: LAHORE METROPOLITAN CORPORATION (Part of Lahore Cantonment Tehsil)
- **Engineering assessment:** Source evidence consistent with one passenger-facing city.
- **Product decision status:** `PROPOSED` / awaiting formal approval (D-CITY-METRO-COALESCE)

## Quetta (`quetta`) — currently COALESCED in candidate

- Source row count: 4
- Combined population 2023: **1,401,362**
- Districts: QUETTA DISTRICT
- Canonical ID: `quetta`
- Rationale: Quetta Metropolitan Corporation subdivision parts → one passenger city
- Source localities:
  - row 18: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division City)
  - row 91: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Saddar Tehsil)
  - row 249: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Sariab)
  - row 303: QUETTA METROPOLITAN CORPORATION (Part of Sub-Division Kuchlak)
- **Engineering assessment:** Source evidence consistent with one passenger-facing city.
- **Product decision status:** `PROPOSED` / awaiting formal approval (D-CITY-METRO-COALESCE)

## Sukkur — NOT coalesced (REVIEW_REQUIRED)

- Source rows: 2
  - row 66: SUKKUR MUNICIPAL CORPORATION (Part of New Sukkur Taluka) — pop 296,743 — SUKKUR DISTRICT
  - row 75: SUKKUR MUNICIPAL CORPORATION (Part of Sukkur City Taluka) — pop 267,108 — SUKKUR DISTRICT
- Combined population if coalesced: **563,851**
- Proposed coalesced city (engineering lean only): `sukkur` / displayName `Sukkur`
- Rationale (proposal): Same Part-of Municipal Corporation pattern as Hyderabad
- **Must not auto-approve** from Lahore/Karachi/Hyderabad/Quetta precedent alone
- **Product decision status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-METRO-COALESCE / D-CITY-SPLIT-LOCALITY)

## Peshawar University TC

- Source: PESHAWAR UNIVERSITY TC
- District: PESHAWAR DISTRICT
- Population: 4,256
- Row: 658
- Classes: institutional township / TC
- Engineering lean: `EXCLUDE` from passenger city selector
- Alternatives: absorb into `peshawar` coverage without selector row
- **Status:** `REQUIRE_PRODUCT_DECISION` — insufficient to classify as passenger-facing city without policy

