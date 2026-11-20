import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';

const driverOfferTypes = [
  'PASSENGER_PRICE_ACCEPTED',
  'DRIVER_COUNTEROFFER',
];

enum DriverDirectOfferPhase {
  idle,
  creating,
  withdrawing,
}

class DriverDirectOfferUiState {
  const DriverDirectOfferUiState({
    this.phase = DriverDirectOfferPhase.idle,
    this.rideId = '',
    this.expectedRequestVersion = '',
    this.type = 'DRIVER_COUNTEROFFER',
    this.amountMinor = '',
    this.lastCreatedOffer,
    this.errorMessage,
    this.infoMessage,
  });

  final DriverDirectOfferPhase phase;
  final String rideId;
  final String expectedRequestVersion;
  final String type;
  final String amountMinor;
  final RideOffer? lastCreatedOffer;
  final String? errorMessage;
  final String? infoMessage;

  bool get isBusy =>
      phase == DriverDirectOfferPhase.creating ||
      phase == DriverDirectOfferPhase.withdrawing;

  bool get canCreate {
    if (isBusy) return false;
    if (rideId.trim().isEmpty) return false;
    if (int.tryParse(expectedRequestVersion.trim()) == null) return false;
    if (!driverOfferTypes.contains(type)) return false;
    if (int.tryParse(amountMinor.trim()) == null) return false;
    return true;
  }

  bool get canWithdraw =>
      !isBusy &&
      lastCreatedOffer != null &&
      lastCreatedOffer!.offerId.isNotEmpty &&
      lastCreatedOffer!.rideId.isNotEmpty;

  DriverDirectOfferUiState copyWith({
    DriverDirectOfferPhase? phase,
    String? rideId,
    String? expectedRequestVersion,
    String? type,
    String? amountMinor,
    RideOffer? lastCreatedOffer,
    String? errorMessage,
    String? infoMessage,
    bool clearLastOffer = false,
    bool clearError = false,
    bool clearInfo = false,
  }) {
    return DriverDirectOfferUiState(
      phase: phase ?? this.phase,
      rideId: rideId ?? this.rideId,
      expectedRequestVersion:
          expectedRequestVersion ?? this.expectedRequestVersion,
      type: type ?? this.type,
      amountMinor: amountMinor ?? this.amountMinor,
      lastCreatedOffer: clearLastOffer
          ? null
          : (lastCreatedOffer ?? this.lastCreatedOffer),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
    );
  }
}

/// Direct offer by known rideId — lab/tooling only; not a marketplace browse.
class DriverDirectOfferViewModel
    extends AutoDisposeNotifier<DriverDirectOfferUiState> {
  late final CreateOfferUseCase _createOffer;
  late final WithdrawOfferUseCase _withdrawOffer;
  late final FailureMapper _failures;
  late final IdempotencyNonceStore _nonceStore;

  String? _createOpKey;
  String? _withdrawOpKey;
  int _mutationGen = 0;

  @override
  DriverDirectOfferUiState build() {
    _createOffer = ref.read(createOfferUseCaseProvider);
    _withdrawOffer = ref.read(withdrawOfferUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);
    return const DriverDirectOfferUiState();
  }

  void setRideId(String value) {
    state = state.copyWith(rideId: value, clearError: true);
  }

  void setExpectedRequestVersion(String value) {
    state = state.copyWith(
      expectedRequestVersion: value,
      clearError: true,
    );
  }

  void setType(String value) {
    if (!driverOfferTypes.contains(value)) return;
    state = state.copyWith(type: value, clearError: true);
  }

  void setAmountMinor(String value) {
    state = state.copyWith(amountMinor: value, clearError: true);
  }

  Future<void> createOffer() async {
    if (!state.canCreate) return;

    final rideId = state.rideId.trim();
    final expectedRequestVersion =
        int.parse(state.expectedRequestVersion.trim());
    final amountMinor = int.parse(state.amountMinor.trim());
    final type = state.type;

    final gen = ++_mutationGen;
    _createOpKey ??= 'offer:create:$rideId:${const Uuid().v4()}';
    state = state.copyWith(
      phase: DriverDirectOfferPhase.creating,
      clearError: true,
      clearInfo: true,
    );

    try {
      final offer = await _createOffer(
        rideId: rideId,
        body: {
          'type': type,
          'amountMinor': amountMinor,
          'expectedRequestVersion': expectedRequestVersion,
        },
        operationKey: _createOpKey!,
      );
      if (gen != _mutationGen) return;
      // New create next time; keep withdraw key separate.
      final old = _createOpKey;
      _createOpKey = null;
      if (old != null) unawaited(_nonceStore.clear(old));

      state = state.copyWith(
        phase: DriverDirectOfferPhase.idle,
        lastCreatedOffer: offer,
        infoMessage:
            'Offer ${offer.offerId} created on the server for ride '
            '${offer.rideId}. This is a known-rideId direct offer — not a '
            'marketplace feed.',
        clearError: true,
      );
    } catch (error, stack) {
      if (gen != _mutationGen) return;
      await _handleFailure(
        _failures.fromException(error, stack),
        clearCreateKey: true,
      );
    }
  }

  Future<void> withdrawOffer() async {
    if (!state.canWithdraw) return;
    final offer = state.lastCreatedOffer!;
    final gen = ++_mutationGen;
    _withdrawOpKey ??=
        'offer:withdraw:${offer.rideId}:${offer.offerId}:${const Uuid().v4()}';
    state = state.copyWith(
      phase: DriverDirectOfferPhase.withdrawing,
      clearError: true,
      clearInfo: true,
    );

    try {
      final updated = await _withdrawOffer(
        rideId: offer.rideId,
        offerId: offer.offerId,
        operationKey: _withdrawOpKey!,
      );
      if (gen != _mutationGen) return;
      final old = _withdrawOpKey;
      _withdrawOpKey = null;
      if (old != null) unawaited(_nonceStore.clear(old));

      state = state.copyWith(
        phase: DriverDirectOfferPhase.idle,
        lastCreatedOffer: updated,
        infoMessage:
            'Offer ${updated.offerId} withdrawn on the server '
            '(status ${updated.status}).',
        clearError: true,
      );
    } catch (error, stack) {
      if (gen != _mutationGen) return;
      await _handleFailure(
        _failures.fromException(error, stack),
        clearCreateKey: false,
      );
    }
  }

  Future<void> _handleFailure(
    AppFailure failure, {
    required bool clearCreateKey,
  }) async {
    final code = failure.maybeWhen(
      conflict: (message, code) => code,
      orElse: () => null,
    );

    final definitive = code == 'VERSION_CONFLICT' ||
        code == 'STATE_CONFLICT' ||
        code == 'IDEMPOTENCY_KEY_REUSED';

    if (definitive) {
      if (clearCreateKey) {
        final old = _createOpKey;
        _createOpKey = null;
        if (old != null) unawaited(_nonceStore.clear(old));
      } else {
        final old = _withdrawOpKey;
        _withdrawOpKey = null;
        if (old != null) unawaited(_nonceStore.clear(old));
      }
    }

    state = state.copyWith(
      phase: DriverDirectOfferPhase.idle,
      errorMessage: failure.userMessage,
      clearInfo: true,
    );
  }
}

final driverDirectOfferViewModelProvider = NotifierProvider.autoDispose<
    DriverDirectOfferViewModel, DriverDirectOfferUiState>(
  DriverDirectOfferViewModel.new,
);
