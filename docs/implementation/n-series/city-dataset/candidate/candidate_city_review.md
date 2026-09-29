# Candidate Pakistan City Dataset — Product Review Pack

**Status:** CANDIDATE — NOT APPROVED — NOT SEEDED

**Firestore:** NOT TOUCHED

**Licensing:** LICENSE_REVIEW_REQUIRED

## Source

- **Organization:** Pakistan Bureau of Statistics (PBS)
- **Dataset:** 7th Population and Housing Census 2023 — Table 2
- **Title:** Urban localities by population size and their population by sex, annual growth rate and household size
- **Result page:** https://www.pbs.gov.pk/result-excel/
- **Official Excel:** https://www.pbs.gov.pk/wp-content/uploads/2020/07/table_2_national.xlsx
- **Official PDF (cross-check):** https://www.pbs.gov.pk/wp-content/uploads/census_tables/tables/table_2_national.pdf
- **Local unmodified source:** `source/table_2_national.xlsx`
- **Download date (UTC):** 2026-09-21T09:16:41Z
- **Raw urban locality rows parsed:** 657
- **Province/territory hints (from district names; national sheet has no province col):** {"Punjab": 342, "Khyber Pakhtunkhwa": 67, "Sindh": 192, "Islamabad Capital Territory": 1, "Balochistan": 55}

## Transformation Rules

1. Parse PBS Table 2 national Excel (preserve source row + name + district + population).
2. **Do not** map 1 PBS row = 1 Ora city when the row is a metro/DMC split.
3. HIGH-confidence coalescing (explicit only):
   - Lahore Metropolitan Corporation (all Part-of tehsil rows) → `lahore`
   - Karachi DMC family (Karachi East/West/South/Central, Korangi, Malir, Keamari) → `karachi`
   - Hyderabad Municipal Corporation parts → `hyderabad`
   - Quetta Metropolitan Corporation parts → `quetta`
4. Other `Part of …` splits without an explicit rule → `REVIEW_REQUIRED` (not forced).
5. Cantonments → `REVIEW_REQUIRED` with suggested parent only (no auto-merge, no auto `*-cantonment` city).
6. Remaining single MC/TC/Municipal Corporation rows → `DIRECT` candidate.
7. Display names: cleaned passenger-facing Title Case (not raw census strings).
8. Canonical id: multi-word spaces→hyphens, then **only** `normalizeCitySlug()` (trim+lowercase); must match `^[a-z0-9]+(?:-[a-z0-9]+)*$`.
9. Duplicate canonical ids → demoted to `REVIEW_REQUIRED` (`DUPLICATE_CANONICAL_ID`).
10. **No population floor** applied.
11. `active: true` in the candidate catalog file is a **placeholder for review**, not ops activation.

## Candidate Count

- Raw PBS locality rows: **657**
- Candidate Ora cities (catalog file): **555**
- Coalesced groups: **4**
- Direct mappings: **551**
- Review-required provenance entries: **67**

## Coalescing Decisions

- **Hyderabad** (`hyderabad`) — 2 source rows; pop2023 sum=1,487,098; districts=HYDERABAD DISTRICT
  - Reason: Hyderabad Municipal Corporation taluka parts → one passenger city
- **Karachi** (`karachi`) — 28 source rows; pop2023 sum=17,895,193; districts=KARACHI CENTRAL DISTRICT, KARACHI EAST DISTRICT, KARACHI SOUTH DISTRICT, KARACHI WEST DISTRICT, KEAMARI DISTRICT, KORANGI DISTRICT, MALIR DISTRICT
  - Reason: Karachi District Municipal Corporation / district parts → one passenger city
- **Lahore** (`lahore`) — 5 source rows; pop2023 sum=11,750,082; districts=LAHORE DISTRICT
  - Reason: Multiple Lahore Metropolitan Corporation census parts → one passenger city
- **Quetta** (`quetta`) — 4 source rows; pop2023 sum=1,401,362; districts=QUETTA DISTRICT
  - Reason: Quetta Metropolitan Corporation subdivision parts → one passenger city

## Cantonment Decisions

- Cantonment source rows: **55** — all marked `REVIEW_REQUIRED` (no silent merge / no separate auto cities).
- Suggested parents (for human review only):
  - `ABBOTTABAD CANTONMENT` (ABBOTTABAD DISTRICT, pop 159,683) → suggestedParent=`abbottabad`
  - `ATTOCK CANTONMENT` (ATTOCK DISTRICT, pop 33,718) → suggestedParent=`attock`
  - `BAHAWALPUR CANTONMENT` (BAHAWALPUR DISTRICT, pop 88,593) → suggestedParent=`bahawalpur`
  - `BANNU CANTONMENT` (BANNU DISTRICT, pop 7,383) → suggestedParent=`bannu`
  - `CHAKLALA CANTONMENT` (RAWALPINDI DISTRICT, pop 333,115) → suggestedParent=`rawalpindi`
  - `CHERAT CANTONMENT` (NOWSHERA DISTRICT, pop 1,311) → suggestedParent=`None`
  - `CLIFTON CANTONMENT (Part of Civil Lines Sub-Division)` (KARACHI SOUTH DISTRICT, pop 196,813) → suggestedParent=`karachi`
  - `CLIFTON CANTONMENT (Part of Korangi Sub-Division)` (KORANGI DISTRICT, pop 5,623) → suggestedParent=`karachi`
  - `CLIFTON CANTONMENT (Part of Saddar Sub-Division)` (KARACHI SOUTH DISTRICT, pop 43,507) → suggestedParent=`karachi`
  - `DERA ISMAIL KHAN CANTONMENT` (DERA ISMAIL KHAN DISTRICT, pop 6,819) → suggestedParent=`dera-ismail-khan`
  - `FAISAL CANTONMENT (Part of Airport Sub-Division)` (MALIR DISTRICT, pop 30,981) → suggestedParent=`karachi`
  - `FAISAL CANTONMENT (Part of Gulshan-e-Iqbal Sub-Division)` (KARACHI EAST DISTRICT, pop 289,473) → suggestedParent=`karachi`
  - `FAISAL CANTONMENT (Part of Shah Faisal Sub-Division)` (KORANGI DISTRICT, pop 30,064) → suggestedParent=`karachi`
  - `GUJRANWALA CANTONMENT` (GUJRANWALA DISTRICT, pop 156,929) → suggestedParent=`gujranwala`
  - `HAVELIAN CANTONMENT` (ABBOTTABAD DISTRICT, pop 37,509) → suggestedParent=`abbottabad`
  - `HYDERABAD CANTONMENT (Part of Hyderabad City Taluka)` (HYDERABAD DISTRICT, pop 52,827) → suggestedParent=`hyderabad`
  - `HYDERABAD CANTONMENT (Part of Latifabad Taluka)` (HYDERABAD DISTRICT, pop 39,190) → suggestedParent=`hyderabad`
  - `HYDERABAD CANTONMENT (Part of Qasimabad Taluka)` (HYDERABAD DISTRICT, pop 6,402) → suggestedParent=`hyderabad`
  - `JHELUM CANTONMENT` (JHELUM DISTRICT, pop 21,404) → suggestedParent=`jhelum`
  - `KAMRA CANTONMENT` (ATTOCK DISTRICT, pop 67,425) → suggestedParent=`attock`
  - `KARACHI CANTONMENT (Part of Civil Lines Sub-Division)` (KARACHI SOUTH DISTRICT, pop 2,664) → suggestedParent=`karachi`
  - `KARACHI CANTONMENT (Part of Jamshed Quarters Sub-Division)` (KARACHI EAST DISTRICT, pop 15,577) → suggestedParent=`karachi`
  - `KARACHI CANTONMENT (Part of Sadar Sub-Division)` (KARACHI SOUTH DISTRICT, pop 68,097) → suggestedParent=`karachi`
  - `KHARIAN CANTONMENT` (GUJRAT DISTRICT, pop 58,523) → suggestedParent=`gujrat`
  - `KOHAT CANTONMENT` (KOHAT DISTRICT, pop 31,051) → suggestedParent=`kohat`
  - `KORANGI CREEK CANTONMENT (Part of Ibrahim Hydri Sub-Division)` (MALIR DISTRICT, pop 17,398) → suggestedParent=`malir`
  - `KORANGI CREEK CANTONMENT (Part of Korangi Sub-Division)` (KORANGI DISTRICT, pop 52,186) → suggestedParent=`korangi`
  - `LAHORE CANTONMENT` (LAHORE DISTRICT, pop 443,314) → suggestedParent=`lahore`
  - `LORALAI CANTONMENT` (LORALAI DISTRICT, pop 2,988) → suggestedParent=`loralai`
  - `MALIR CANTONMENT (Part of Airport Sub-Division)` (MALIR DISTRICT, pop 106,089) → suggestedParent=`malir`
  - `MALIR CANTONMENT (Part of Gulzar-e-Hijri Sub-Division)` (KARACHI EAST DISTRICT, pop 88,335) → suggestedParent=`karachi-east`
  - `MALIR CANTONMENT (Part of Murad Memon Sub-Division)` (MALIR DISTRICT, pop 23,065) → suggestedParent=`malir`
  - `MANGLA CANTONMENT` (JHELUM DISTRICT, pop 19,129) → suggestedParent=`jhelum`
  - `MANORA CANTONMENT (Part of Keamari Sub-Division)` (KEAMARI DISTRICT, pop 2,956) → suggestedParent=`karachi`
  - `MARDAN CANTONMENT` (MARDAN DISTRICT, pop 4,514) → suggestedParent=`mardan`
  - `MULTAN CANTONMENT` (MULTAN DISTRICT, pop 45,466) → suggestedParent=`multan`
  - `MURREE GALLIES CANTONMENT` (ABBOTTABAD DISTRICT, pop 784) → suggestedParent=`murree`
  - `MURREE HILLS CANTONMENT` (RAWALPINDI DISTRICT, pop 8,869) → suggestedParent=`rawalpindi`
  - `NOWSHERA CANTONMENT` (NOWSHERA DISTRICT, pop 34,481) → suggestedParent=`nowshera`
  - `OKARA CANTONMENT` (OKARA DISTRICT, pop 65,590) → suggestedParent=`okara`
  - `ORMARA CANTONMENT` (GWADAR DISTRICT, pop 2,784) → suggestedParent=`ormara`
  - `PANO AQIL CANTONMENT` (SUKKUR DISTRICT, pop 25,759) → suggestedParent=`sukkur`
  - `PESHAWAR CANTONMENT` (PESHAWAR DISTRICT, pop 63,978) → suggestedParent=`peshawar`
  - `QUETTA CANTONMENT` (QUETTA DISTRICT, pop 164,184) → suggestedParent=`quetta`
  - `RAWALPINDI CANTONMENT` (RAWALPINDI DISTRICT, pop 740,483) → suggestedParent=`rawalpindi`
  - `RISALPUR CANTONMENT` (NOWSHERA DISTRICT, pop 36,074) → suggestedParent=`nowshera`
  - `SANJWAL CANTONMENT` (ATTOCK DISTRICT, pop 11,751) → suggestedParent=`attock`
  - `SARGODHA CANTONMENT` (SARGODHA DISTRICT, pop 190,188) → suggestedParent=`sargodha`
  - `SHORKOT CANTONMENT (Part of Pirmahal Tehsil)` (TOBA TEK SINGH DISTRICT, pop 12,081) → suggestedParent=`toba-tek-singh`
  - `SHORKOT CANTONMENT (Part of Shorkot Tehsil)` (JHANG DISTRICT, pop 20,246) → suggestedParent=`jhang`
  - `SIALKOT CANTONMENT` (SIALKOT DISTRICT, pop 76,480) → suggestedParent=`sialkot`
  - `TAXILA CANTONMENT` (RAWALPINDI DISTRICT, pop 61,456) → suggestedParent=`rawalpindi`
  - `WAH CANTONMENT` (RAWALPINDI DISTRICT, pop 400,733) → suggestedParent=`rawalpindi`
  - `WALTON CANTONMENT` (LAHORE DISTRICT, pop 810,739) → suggestedParent=`lahore`
  - `ZHOB CANTONMENT` (ZHOB DISTRICT, pop 2,725) → suggestedParent=`zhob`

## Ambiguous Records

- Total `REVIEW_REQUIRED` entries: **67**
- Of which cantonments: **55**
- Metropolitan/split source rows in raw data: **61**
- Non-cantonment reviews: **12** (see provenance JSON for full list)
  - row 46: SAHIWAL METROPOLITAN CORPORATION — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'sahiwal' shared by: DIRECT:Sahiwa
  - row 77: KHANPUR MC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'khanpur' shared by: DIRECT:Khanpu
  - row 275: SAHIWAL MC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'sahiwal' shared by: DIRECT:Sahiwa
  - row 432: KHANGARH TC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'khangarh' shared by: DIRECT:Khang
  - row 434: KHANGARH MC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'khangarh' shared by: DIRECT:Khang
  - row 470: KARAMPUR TC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'karampur' shared by: DIRECT:Karam
  - row 502: HYDERABAD TC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'hyderabad' shared by: COALESCED:H
  - row 552: KARAMPUR TC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'karampur' shared by: DIRECT:Karam
  - row 579: KHANPUR TC — Single urban locality row maps 1:1 to candidate service city | DUPLICATE_CANONICAL_ID 'khanpur' shared by: DIRECT:Khanpu
  - row 66: SUKKUR MUNICIPAL CORPORATION (Part of New Sukkur Taluka) — Split locality (Part of …) without an explicit HIGH-confidence coalesce rule — do not invent a merge
  - row 75: SUKKUR MUNICIPAL CORPORATION (Part of Sukkur City Taluka) — Split locality (Part of …) without an explicit HIGH-confidence coalesce rule — do not invent a merge
  - row 658: PESHAWAR UNIVERSITY TC — Special/university TC — may not be a passenger service city

## Duplicate IDs

- Demoted duplicate canonical ids: hyderabad, karampur, khangarh, khanpur, sahiwal

## Population Distribution

### Raw PBS locality rows (no coalesce)

- >=500k: 46
- 100k-499k: 119
- 50k-99k: 134
- 25k-49k: 200
- 10k-24k: 128
- 5k-9k: 18
- <5k: 12

### Candidate catalog cities (coalesced sums / direct)

- >=500k: 20
- 100k-499k: 97
- 50k-99k: 120
- 25k-49k: 184
- 10k-24k: 118
- 5k-9k: 13
- <5k: 3

No population cutoff was applied.

## Licensing Status

**LICENSE_REVIEW_REQUIRED**

PBS dissemination materials describe Tier 1 aggregate products as reusable with attribution under an open-government-style licence. That is **not** a substitute for Ora legal clearance to store a derived city catalog in Firestore and expose it via API.

## Product Decisions Still Required

1. Approve or revise HIGH-confidence coalescing (Lahore, Karachi, Hyderabad, Quetta).
2. Cantonment policy: merge into parent vs exclude vs separate service cities.
3. Resolve every `REVIEW_REQUIRED` row (accept / merge / drop).
4. Confirm displayName spelling (English Title Case vs official PBS casing).
5. Confirm multi-word slug shaping (spaces→hyphens then `normalizeCitySlug`).
6. Activation policy: all candidates `active=true` vs staged rollout.
7. Optional later population floor — **not** applied here.
8. **Legal/license approval** before any Firestore population.
9. Deliver a signed approved import list matching CityCatalogService contract.

## Files

- `candidate/candidate_city_catalog.json`
- `candidate/candidate_city_provenance.json`
- `candidate/candidate_city_stats.json`
- `candidate/candidate_city_review.md`
- `source/` — unmodified PBS downloads + manifest

