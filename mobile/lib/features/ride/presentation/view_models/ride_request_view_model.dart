import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/ride.dart';
import '../../domain/models/ride_category_option.dart';
import '../../domain/use_cases/ride_use_cases.dart';

/// Production capabilities for ride create. Defaults are empty — no invented
/// pricing snapshot or GPS coordinates.
class RideRequestCapabilities {
  const RideRequestCapabilities({
    this.pricingSnapshotId,
    this.passengerOfferMinor,
    this.resolvedPickup,
    this.resolvedDestination,
  });

  final String? pricingSnapshotId;
  final int? passengerOfferMinor;
  final LatLngPoint? resolvedPickup;
  final LatLngPoint? resolvedDestination;

  bool get hasPricing =>
      pricingSnapshotId != null &&
      pricingSnapshotId!.isNotEmpty &&
      passengerOfferMinor != null &&
      passengerOfferMinor! > 0;

  bool get hasResolvedLocations =>
      resolvedPickup != null && resolvedDestination != null;

  bool get canCreateRide => hasPricing && hasResolvedLocations;
}

enum RideRequestPhase {
  compose,
  review,
  submitting,
  created,
  error,
  blocked,
}

enum RideRequestBlockReason {
  incomplete,
  pricingUnavailable,
  locationUnavailable,
}

class RideRequestUiState {
  const RideRequestUiState({
    this.phase = RideRequestPhase.compose,
    this.pickupText = '',
    this.destinationText = '',
    this.categoryId = 'easy',
    this.paymentMethod = 'CASH',
    this.blockReason,
    this.errorMessage,
    this.createdRide,
  });

  final RideRequestPhase phase;
  final String pickupText;
  final String destinationText;
  final String categoryId;
  final String paymentMethod;
  final RideRequestBlockReason? blockReason;
  final String? errorMessage;
  final Ride? createdRide;

  bool get hasPickupText => pickupText.trim().isNotEmpty;
  bool get hasDestinationText => destinationText.trim().isNotEmpty;

  bool get canAdvanceToReview => hasPickupText && hasDestinationText;

  RideCategoryOption get selectedCategory =>
      rideCategoryById(categoryId) ?? kRideCategoryOptions[2];

  RideRequestUiState copyWith({
    RideRequestPhase? phase,
    String? pickupText,
    String? destinationText,
    String? categoryId,
    String? paymentMethod,
    RideRequestBlockReason? blockReason,
    String? errorMessage,
    Ride? createdRide,
    bool clearBlock = false,
    bool clearError = false,
    bool clearCreated = false,
  }) {
    return RideRequestUiState(
      phase: phase ?? this.phase,
      pickupText: pickupText ?? this.pickupText,
      destinationText: destinationText ?? this.destinationText,
      categoryId: categoryId ?? this.categoryId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      blockReason: clearBlock ? null : (blockReason ?? this.blockReason),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      createdRide: clearCreated ? null : (createdRide ?? this.createdRide),
    );
  }
}

/// Compose → review → create (when capabilities allow). Never invents pricing
/// or coordinates.
class RideRequestViewModel extends AutoDisposeNotifier<RideRequestUiState> {
  late final CreateRideUseCase _createRide;
  late final FailureMapper _failures;
  late final RideRequestCapabilities _capabilities;

  /// Stable idempotency operation key for this compose session.
  String? _createOperationKey;

  @override
  RideRequestUiState build() {
    _createRide = ref.read(createRideUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _capabilities = ref.read(rideRequestCapabilitiesProvider);
    return const RideRequestUiState();
  }

  void seedCategory(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return;
    if (rideCategoryById(categoryId) == null) return;
    state = state.copyWith(categoryId: categoryId);
  }

  void setPickupText(String value) {
    state = state.copyWith(
      pickupText: value,
      clearBlock: true,
      clearError: true,
    );
  }

  void setDestinationText(String value) {
    state = state.copyWith(
      destinationText: value,
      clearBlock: true,
      clearError: true,
    );
  }

  void selectCategory(String categoryId) {
    if (rideCategoryById(categoryId) == null) return;
    state = state.copyWith(
      categoryId: categoryId,
      clearBlock: true,
      clearError: true,
    );
  }

  void goToCompose() {
    if (state.phase == RideRequestPhase.submitting) return;
    state = state.copyWith(
      phase: RideRequestPhase.compose,
      clearBlock: true,
      clearError: true,
    );
  }

  void goToReview() {
    if (!state.canAdvanceToReview) {
      state = state.copyWith(
        phase: RideRequestPhase.blocked,
        blockReason: RideRequestBlockReason.incomplete,
      );
      return;
    }
    state = state.copyWith(
      phase: RideRequestPhase.review,
      clearBlock: true,
      clearError: true,
    );
  }

  RideRequestCapabilities get capabilities => _capabilities;

  bool get canSubmitRideRequest =>
      state.canAdvanceToReview && _capabilities.canCreateRide;

  RideRequestBlockReason? get submitBlockReason {
    if (!state.canAdvanceToReview) {
      return RideRequestBlockReason.incomplete;
    }
    if (!_capabilities.hasPricing) {
      return RideRequestBlockReason.pricingUnavailable;
    }
    if (!_capabilities.hasResolvedLocations) {
      return RideRequestBlockReason.locationUnavailable;
    }
    return null;
  }

  String messageFor(RideRequestBlockReason reason) {
    return switch (reason) {
      RideRequestBlockReason.incomplete =>
        'Enter both a pickup and a destination to continue.',
      RideRequestBlockReason.pricingUnavailable =>
        'Pricing isn\'t available right now. Please try again later.',
      RideRequestBlockReason.locationUnavailable =>
        'Location isn\'t available yet. Ora will not invent pickup or '
            'destination coordinates.',
    };
  }

  /// Attempts create only when pricing + resolved coordinates exist.
  Future<void> submit() async {
    if (state.phase == RideRequestPhase.submitting) return;

    final block = submitBlockReason;
    if (block != null) {
      state = state.copyWith(
        phase: RideRequestPhase.blocked,
        blockReason: block,
        clearError: true,
      );
      return;
    }

    final pickup = _capabilities.resolvedPickup!;
    final destination = _capabilities.resolvedDestination!;
    final snapshotId = _capabilities.pricingSnapshotId!;
    final offerMinor = _capabilities.passengerOfferMinor!;

    _createOperationKey ??= 'ride:create:${const Uuid().v4()}';

    state = state.copyWith(
      phase: RideRequestPhase.submitting,
      clearBlock: true,
      clearError: true,
    );

    try {
      final ride = await _createRide(
        body: <String, Object?>{
          'pickup': <String, Object?>{
            'lat': pickup.lat,
            'lng': pickup.lng,
            if (pickup.address != null) 'address': pickup.address,
          },
          'destination': <String, Object?>{
            'lat': destination.lat,
            'lng': destination.lng,
            if (destination.address != null) 'address': destination.address,
          },
          'category': state.categoryId,
          'serviceType': 'ride',
          'passengerOfferMinor': offerMinor,
          'pricingSnapshotId': snapshotId,
          'paymentMethod': state.paymentMethod,
          'passengerCount': 1,
        },
        operationKey: _createOperationKey!,
      );
      state = state.copyWith(
        phase: RideRequestPhase.created,
        createdRide: ride,
        clearError: true,
        clearBlock: true,
      );
    } catch (error, stack) {
      final failure = _failures.fromException(error, stack);
      state = state.copyWith(
        phase: RideRequestPhase.error,
        errorMessage: failure.userMessage,
      );
    }
  }

  void clearBlocked() {
    state = state.copyWith(
      phase: RideRequestPhase.review,
      clearBlock: true,
    );
  }

  void retryAfterError() {
    state = state.copyWith(
      phase: RideRequestPhase.review,
      clearError: true,
    );
  }
}

final rideRequestCapabilitiesProvider = Provider<RideRequestCapabilities>(
  (ref) => const RideRequestCapabilities(),
);

final rideRequestViewModelProvider =
    NotifierProvider.autoDispose<RideRequestViewModel, RideRequestUiState>(
  RideRequestViewModel.new,
);
