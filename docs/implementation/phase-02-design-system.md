# Phase 2 — Ora Design System

**Status:** NOT STARTED  
**Dependencies:** Phase 1  
**Estimated effort:** 1 week

## Objectives

Build the complete Ora Design System (ODS) as a reusable component library. No screens yet — only the building blocks.

## Design Tokens (from prototype analysis)

```dart
// lib/core/theme/ora_colors.dart
class OraColors {
  static const navy = Color(0xFF12182B);
  static const navy2 = Color(0xFF1B2340);
  static const gold = Color(0xFFD4A756);
  static const goldLight = Color(0x2ED4A756);  // 18% opacity
  static const goldDark = Color(0xFFF3E3C2);
  static const teal = Color(0xFF1F9C82);
  static const tealLight = Color(0x301F9C82);
  static const tealDark = Color(0xFF7CFFCE);
  static const blue = Color(0xFF4FA3D9);
  static const blueLight = Color(0x384FA3D9);
  static const purple = Color(0xFFA78BFA);
  static const purpleLight = Color(0x37A78BFA);
  static const coral = Color(0xFFF08A6A);
  static const coralLight = Color(0x33F08A6A);
  static const slate = Color(0xFFA8AEBF);
  static const slateLight = Color(0xFF7A8196);
  static const line = Color(0xFF2A334D);
  static const card = Color(0xFF1B2340);
  static const ink = Color(0xFFF4F6FA);
  static const paper = Color(0xFF12182B);
  static const background = Color(0xFF0B0F1C);
}
```

## Typography (Sora + Inter)

```dart
// Sora: headings, labels, amounts, CTAs
// Inter: body text, descriptions, inputs
```

## Component Inventory

| Component | Notes |
|---|---|
| `OraButton` | Primary (gold), teal, ghost, danger variants |
| `OraCard` | Card with border, radius 18px |
| `OraTextField` | Input with icon, label, focus state (gold border) |
| `OraListRow` | Icon + text + chevron/toggle pattern |
| `OraToggle` | Custom toggle (not Material Switch) |
| `OraRideCard` | Horizontal scrollable category card |
| `OraVehicleRow` | Vertical list vehicle selection row |
| `OraDriverCard` | Driver info card (photo, name, rating, plate) |
| `OraPricePreview` | Dark fare preview pill |
| `OraSheet` | Bottom sheet with drag handle |
| `OraMapBox` | Map container with overlaid UI |
| `OraStarRating` | 5-star rating input |
| `OraStepper` | Progress dots for onboarding |
| `OraPhotoSlot` | Document upload slot (empty/done/optional states) |
| `OraOptionTile` | 2-column option grid tile |
| `OraStatMini` | Small stat card (value + label) |
| `OraChip` | Selectable chip |
| `OraStatusBadge` | Completed/Cancelled/Courier etc. |
| `OraDrawer` | Passenger/driver side navigation drawer |
| `OraOtpBox` | OTP input digit box |

## Acceptance Criteria

- [ ] All color tokens defined and named correctly
- [ ] Both fonts load without runtime fetching
- [ ] All listed components exist as reusable widgets
- [ ] No hardcoded colors anywhere — all use OraColors constants
- [ ] Widget catalog screen exists (dev-only, not in production routing)
- [ ] Dark theme renders correctly on all components
- [ ] `flutter test` widget tests for OraButton (all variants), OraTextField, OraToggle
- [ ] Components are `const`-constructable where possible
- [ ] Components do NOT contain business logic (pure presentation)
