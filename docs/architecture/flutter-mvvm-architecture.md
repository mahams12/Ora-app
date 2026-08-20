# ORA — Flutter MVVM Architecture (Locked)

**Version:** 0.7.0  
**Status:** CANONICAL — Flutter implementation must follow this document  
**Pattern:** MVVM + Riverpod + feature-based clean architecture

This document supersedes the presentation-layer naming in `frontend-architecture.md`. Domain and data layering remain compatible; View/ViewModel naming is now mandatory.

---

## 1. Canonical Folder Structure

```
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   │   ├── app_router.dart
│   │   └── route_guards.dart
│   └── theme/
│       ├── ora_colors.dart
│       ├── ora_typography.dart
│       └── ora_theme.dart
│
├── core/
│   ├── errors/
│   ├── network/
│   ├── storage/
│   ├── location/
│   ├── maps/
│   └── utils/
│
├── features/
│   ├── auth/
│   ├── passenger/
│   ├── driver/
│   ├── ride/
│   ├── maps/
│   ├── payments/
│   └── safety/
│
└── main.dart
```

Each feature uses this internal layout:

```
features/{feature}/
├── presentation/
│   ├── views/
│   ├── view_models/
│   └── widgets/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── use_cases/
└── data/
    ├── models/
    ├── repositories/
    └── data_sources/
```

Shared UI primitives live in `app/theme` and, if needed, a later `shared/widgets` package. Shared widgets must remain presentation-only.

---

## 2. Layer Responsibilities

### VIEW (`presentation/views`, `presentation/widgets`)

A View:

- renders UI from immutable ViewModel state
- observes ViewModel state via Riverpod
- sends user intents to the ViewModel (`onConfirmOffer`, `onSelectOffer`)
- contains **no** business logic
- does **not** call repositories, data sources, Firestore, RTDB, Dio, or SDKs
- does **not** compute fares, eligibility, assignment, or payment outcomes
- does **not** own navigation policy beyond calling a ViewModel/router intent

Widgets are dumb. If a widget needs a decision, that decision belongs in a ViewModel or use case.

### VIEWMODEL (`presentation/view_models`)

A ViewModel:

- owns presentation state (`loading`, `error`, `success`, form fields, selected offer)
- maps user actions to use cases
- coordinates presentation behavior (debounce, retry UI, local validation of input format)
- exposes Freezed state unions
- does **not** contain infrastructure logic
- does **not** talk to Firestore/RTDB/Dio/Redis/Maps SDKs directly
- does **not** encode server-authoritative rules (assignment, agreed fare, payment capture)

ViewModels call use cases. Use cases call repositories.

### USE CASE (`domain/use_cases`)

A use case:

- represents one application/domain operation
- is independent of Flutter widgets
- may orchestrate multiple repository calls
- returns domain entities or typed failures
- does not know about `BuildContext`, `go_router`, or widget trees

Examples:

- `CreateRideRequest`
- `SubmitPassengerOffer`
- `CreateDriverOffer`
- `SelectRideOffer`
- `ConfirmCashCollected`

### REPOSITORY (`domain/repositories` + `data/repositories`)

The domain repository is an abstraction. The data repository implements it.

A repository:

- hides data-source details
- maps DTOs to domain entities
- is the only domain-facing way to reach remote/local data
- does not contain widget or navigation logic

### DATA SOURCE (`data/data_sources`)

A data source talks to one infrastructure concern:

- Cloud Run HTTP API
- Firestore listeners/reads
- RTDB listeners/writes (presence only from client; ride-scoped writes are server-only)
- local cache (`hive_ce` / secure storage)
- Google Maps / Places / Geolocator SDKs

Data sources must not be imported by Views or ViewModels.

---

## 3. Riverpod Role

Riverpod is used for:

- dependency injection of repositories and use cases
- ViewModel lifecycle (`AutoDisposeNotifier` / code-gen notifiers)
- reactive presentation state
- wiring: `DataSource → Repository → UseCase → ViewModel → View`

Rules:

- Providers for data sources and repositories are not watched by Views.
- Views watch **ViewModel state only**, using `select()` where rebuild cost matters.
- Use cases are constructed via providers; Views never construct them.
- `ref.invalidate()` is a cache/lifecycle tool, not a business-rule engine.

---

## 4. Freezed Role

Freezed is required for:

- immutable domain entities
- immutable ViewModel state
- typed unions for async/presentation states

Example presentation union:

```text
AuthViewState.idle
AuthViewState.loading
AuthViewState.otpSent
AuthViewState.authenticated
AuthViewState.failed(AppError)
```

Views switch on unions. They do not infer business meaning from raw maps.

---

## 5. go_router Role

go_router is **navigation only**.

Allowed:

- route table
- auth redirect for unauthenticated users
- deep links
- shell routes

Forbidden inside Views:

- deciding ride assignment
- deciding payment success
- reconstructing business workflows as a sequence of `context.go` calls without a ViewModel intent

Navigation after a domain success is a ViewModel outcome (`NavigateToLiveTrip`) consumed by the View or a small router adapter. The View does not contain the business reason.

---

## 6. Strict Layer Rules

```
View  → ViewModel → UseCase → Repository → DataSource
```

Forbidden:

| From | To | Why |
|---|---|---|
| View | Repository | skips presentation orchestration |
| View | DataSource | leaks infrastructure into UI |
| View | UseCase | bypasses ViewModel state/error handling |
| ViewModel | DataSource | infrastructure in presentation |
| ViewModel | Firestore/RTDB SDK | source-of-truth leakage |
| UseCase | Widget / BuildContext | domain coupled to Flutter UI |
| DataSource | ViewModel | inverted dependency |
| Any client layer | authoritative assignment / ledger write | server-only |

Build-time / review checks:

- `presentation/views` must not import `data/`
- `presentation/view_models` must not import `data/data_sources`
- `domain/` must not import Flutter Material widgets
- `domain/` must not import Firebase/Dio packages

---

## 7. Feature Boundaries

| Feature | Owns |
|---|---|
| `auth` | sign-in, OTP, session, route guard inputs |
| `passenger` | home, destination, offer entry, offer comparison |
| `driver` | go online, incoming request cards, accept/counter/decline |
| `ride` | ride aggregate, offer selection, live trip, completion |
| `maps` | map rendering, camera, polylines, markers |
| `payments` | payment method selection, cash confirm, wallet presentation |
| `safety` | SOS, share trip, verify driver |

Cross-feature communication is through domain entities and shared providers, not by importing another feature's Views.

---

## 8. Authoritative State vs Presentation State

| Concern | Presentation | Authority |
|---|---|---|
| Typed OTP field | ViewModel | Firebase Auth / server |
| Recommended fare shown | ViewModel cache of pricing estimate | Pricing service snapshot |
| Passenger offer input | ViewModel | Ride create/update API |
| Driver offer list | ViewModel from repository stream | Firestore `rideOffers` |
| Assigned driver | ViewModel from ride stream | Firestore ride transaction |
| Agreed fare | display only | Firestore ride/offer snapshot |
| Payment status | display only | Payment aggregate |

The client may be optimistic for **input** (typing a price). It must not be optimistic for **assignment**, **agreed fare**, or **payment capture**.

---

## 9. Example Flow (Passenger Selects Offer)

```
OfferListView
  → OfferListViewModel.selectOffer(offerId)
    → SelectRideOffer use case
      → RideRepository.selectOffer(rideId, offerId, idempotencyKey)
        → RideRemoteDataSource POST /v1/rides/{id}/offers/{offerId}/select
          → Cloud Run Firestore transaction
            → ride assigned + agreedFare snapshotted
        ← 200 { state: DRIVER_ASSIGNED, agreedFareMinor }
    → ViewModel state = assigned
  → View renders live trip / router intent
```

If the server returns `409 OFFER_NOT_SELECTABLE`, the ViewModel maps that to presentation error state. The View does not retry assignment itself.

---

## 10. What Must Not Be Implemented in Flutter

- fare formula
- matching / ranking
- assignment transaction
- ledger posting
- payment capture
- offer expiry sweeper
- RTDB ride-scoped writes (except driver presence)

Those remain Cloud Run / Admin SDK responsibilities.

---

## 11. Client Security Boundaries (Flutter)

The app may:

- let a passenger enter `passengerOffer` and submit it for **their** ride
- let a driver create an offer only after the server has dispatched them that request
- let a passenger select an offer on **their** ride

The app must not:

- let a driver select themselves / call select-offer
- write `agreedFare`, `platformFee`, `driverNetAmount`, ledger entries, payment status, or assignment fields
- treat RTDB “payment successful” or client booleans as financial truth

