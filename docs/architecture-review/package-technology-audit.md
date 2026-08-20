# ORA — Package & Technology Audit

## Summary Recommendations

| Technology | Existing Doc Recommendation | Current Evidence | Recommendation |
|---|---|---|---|
| `flutter_riverpod` | `2.x` | current stable `3.4.2` | upgrade plan to 3.x before implementation |
| `go_router` | `14.x` | current stable `17.5.0` | use current stable after migration review |
| `google_maps_flutter` | `2.x` | current stable `2.18.0` | keep family; pin current stable |
| `geolocator` | `11.x` | current stable `14.0.3` | use current stable |
| `flutter_background_geolocation` | Transistor plugin | current stable `5.5.0`, active, Android release license required | keep, but add procurement gate |
| `firebase_messaging` | family only | current stable `16.5.0` | keep, pin current stable |
| `flutter_secure_storage` | family only | current stable `11.0.0`, recent breaking changes | keep, evaluate migration notes |
| `hive` | `2.x` | original stable line stale; `hive_ce` active | replace with `hive_ce` or reassess need |
| `dio` | family only | current stable `5.11.0` | keep, pin current stable |
| `freezed` | family only | current stable `3.2.5`; `4.x` still prerelease | stay on stable 3.x |

## Notable Findings

### Riverpod
Docs are behind current stable major versions. This is not inherently wrong, but it should be a deliberate compatibility choice, not an accidental stale recommendation.

### go_router
The current docs pin an older major. If the project starts fresh, using a much older major offers little benefit unless a known migration blocker exists.

### geolocator
Current architecture references `11.x`, which is behind current stable.

### Hive
This is the clearest package-level issue. The original `hive` stable line is old; `hive_ce` is the healthier recommendation for a new project if Hive-style local storage is still desired.

### Background geolocation
Technically strong and actively maintained, but licensing must be treated as a delivery dependency.
