# ORA — Frontend Architecture

**Canonical pattern:** MVVM + Riverpod + feature-based architecture.  
See `docs/architecture/flutter-mvvm-architecture.md` for the locked folder tree, layer rules, and Riverpod/Freezed/go_router roles.

This file remains a navigation, rebuild, and error-handling companion. Presentation types are **Views / ViewModels / widgets**, not screens-as-controllers.

## Pattern: Feature-First MVVM

Each feature is self-contained with three layers:

```
features/
  ride/
    data/
      repositories/          # Concrete implementation
        ride_repository_impl.dart
      datasources/
        ride_remote_datasource.dart   # API calls
        ride_local_datasource.dart    # Hive cache
      models/
        ride_dto.dart                 # JSON serialization
    domain/
      repositories/
        ride_repository.dart          # Abstract interface
      entities/
        ride.dart                     # Immutable business entity
      usecases/
        accept_passenger_price_usecase.dart
        create_counteroffer_usecase.dart
        select_offer_usecase.dart
        cancel_ride_usecase.dart
    presentation/
      views/
        destination_view.dart
        vehicle_selection_view.dart
        finding_view.dart
        offer_inbox_view.dart
        live_trip_view.dart
        trip_completion_view.dart
      view_models/
        ride_request_view_model.dart
        offer_inbox_view_model.dart
        live_trip_view_model.dart
      widgets/
        ride_category_card.dart
        driver_offer_card.dart
        fare_display.dart
```

## State Management (Riverpod)

ViewModels are Riverpod notifiers. They call use cases; they do not call data sources.

Rules:
- Never put business logic in Views
- Never call APIs, repositories, or data sources from `build()`
- Views watch ViewModel state with `select()` to prevent unnecessary rebuilds
- Use cases own ride/offer/payment workflows
- `ref.invalidate()` is cache/lifecycle only

## Navigation (go_router)

```
/splash
/auth
  /auth/phone
  /auth/otp
/home (ShellRoute — persistent bottom nav)
  /home/passenger
  /home/passenger/destination
  /home/passenger/vehicle
  /home/passenger/finding
  /home/passenger/offers
  /home/passenger/live
  /home/passenger/rate
  /home/driver
  /home/driver/request
  /home/driver/pickup-nav
  /home/driver/active-nav
  /home/driver/completion
/profile
/settings
/wallet
/rides
/safety
/driver-onboarding
  /driver-onboarding/vehicle
  /driver-onboarding/documents
  /driver-onboarding/pending
/intercity
/courier
/move
```

## Rebuild Prevention Strategy

| Situation | Solution |
|---|---|
| Ride state update triggers full tree rebuild | `select((ride) => ride.state)` — rebuilds only state-dependent widgets |
| GPS update triggers map rebuild only | Separate `driverLocationProvider`; map widget only watches this |
| Driver list updates | `AutoDisposeProvider` + `select` for each card |
| Auth state | Top-level `authProvider`; guarded routes via `redirect` |

## Error Handling

All errors flow through `AppError` sealed class:
```dart
sealed class AppError {
  const AppError();
}
class NetworkError extends AppError { ... }
class AuthError extends AppError { ... }
class RideConflictError extends AppError { ... } // 409 — someone else accepted
class ValidationError extends AppError { ... }
class ServerError extends AppError { ... }
```

Errors surfaced to UI via `AsyncError` in providers → error widgets with retry.

## Immutable Models (freezed)

```dart
@freezed
class Ride with _$Ride {
  const factory Ride({
    required String rideId,
    required RideState state,
    required int version,
    required LatLng pickup,
    required LatLng destination,
    required String passengerId,
    String? assignedDriverId,
    required Fare fare,
    required DateTime createdAt,
  }) = _Ride;
  
  factory Ride.fromJson(Map<String, dynamic> json) => _$RideFromJson(json);
}
```

## Background Work

- GPS updates: Isolate via Transistor BGGeo plugin (separate process)
- FCM handler: Dart isolate (Flutter background execution)
- Hive cache writes: Main isolate (fast enough; non-blocking)
- Heavy computation (route decode, Kalman filter): `compute()` isolate
