import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';

/// Injectable clock — tests override to drive the countdown deterministically.
final inviteClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

enum DriverInvitesPhase { initialLoading, ready, empty, fatalError }

class DriverInvitesUiState {
  const DriverInvitesUiState({
    this.phase = DriverInvitesPhase.initialLoading,
    this.items = const [],
    this.respondingWaveIds = const {},
    this.tickMs = 0,
    this.infoMessage,
    this.errorMessage,
  });

  final DriverInvitesPhase phase;
  final List<DriverInvite> items;
  final Set<String> respondingWaveIds;
  /// Server-adjusted clock at last tick — rebuilds countdown labels.
  final int tickMs;
  final String? infoMessage;
  final String? errorMessage;

  bool isResponding(String waveId) => respondingWaveIds.contains(waveId);

  DriverInvitesUiState copyWith({
    DriverInvitesPhase? phase,
    List<DriverInvite>? items,
    Set<String>? respondingWaveIds,
    int? tickMs,
    String? infoMessage,
    String? errorMessage,
    bool clearInfo = false,
    bool clearError = false,
  }) {
    return DriverInvitesUiState(
      phase: phase ?? this.phase,
      items: items ?? this.items,
      respondingWaveIds: respondingWaveIds ?? this.respondingWaveIds,
      tickMs: tickMs ?? this.tickMs,
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Incoming dispatch invitations with an authoritative server countdown.
///
/// Clock-skew safety: `serverNowMs` from the last invited-list response is
/// compared to the device clock once per fetch; all remaining-time math uses
/// the server-adjusted clock, never the raw device clock.
class DriverInvitesViewModel
    extends AutoDisposeNotifier<DriverInvitesUiState> {
  late final ListInvitedRidesUseCase _listInvited;
  late final AcceptInviteUseCase _accept;
  late final DeclineInviteUseCase _decline;
  late final FailureMapper _failures;
  late final DateTime Function() _now;

  /// device-now → server-now offset (serverNowMs - deviceNowMs at fetch).
  int _serverOffsetMs = 0;
  Timer? _ticker;
  bool _refreshInFlight = false;

  @override
  DriverInvitesUiState build() {
    _listInvited = ref.read(listInvitedRidesUseCaseProvider);
    _accept = ref.read(acceptInviteUseCaseProvider);
    _decline = ref.read(declineInviteUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _now = ref.read(inviteClockProvider);
    ref.onDispose(() => _ticker?.cancel());
    return const DriverInvitesUiState();
  }

  /// Server-adjusted "now" in milliseconds.
  int _serverNowMs() => _now().millisecondsSinceEpoch + _serverOffsetMs;

  /// Remaining accept window for an invite (never negative).
  Duration remainingFor(DriverInvite invite) {
    final expiry = invite.inviteExpiresAt;
    if (expiry == null) return Duration.zero;
    final ms = expiry.millisecondsSinceEpoch - _serverNowMs();
    return ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  bool isLocallyExpired(DriverInvite invite) =>
      !invite.isActionable || remainingFor(invite) <= Duration.zero;

  Future<void> refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final page = await _listInvited();
      // Clamp skew correction — a wildly off server value would corrupt
      // countdown math; ±10 min is a generous sane bound.
      final measured =
          page.serverNowMs - _now().millisecondsSinceEpoch;
      if (page.serverNowMs > 0 && measured.abs() < 10 * 60 * 1000) {
        _serverOffsetMs = measured;
      }
      _applyItems(page.items);
      _ensureTicker();
    } catch (error, stack) {
      final failure = _failures.fromException(error, stack);
      if (state.items.isEmpty) {
        state = state.copyWith(
          phase: DriverInvitesPhase.fatalError,
          errorMessage: failure.userMessage,
        );
      } else {
        state = state.copyWith(errorMessage: failure.userMessage);
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  /// One countdown tick — drops ACTIVE items whose server deadline passed.
  /// Called by the internal 1s ticker; exposed for deterministic tests.
  void tickCountdown() {
    if (state.items.isEmpty) return;
    var changed = false;
    final kept = <DriverInvite>[];
    for (final item in state.items) {
      if (item.isActionable && isLocallyExpired(item)) {
        changed = true;
        continue; // auto-remove expired card
      }
      kept.add(item);
    }
    if (changed) {
      _applyItems(kept);
    } else {
      // Rebuild countdown labels with the current server-adjusted clock.
      state = state.copyWith(tickMs: _serverNowMs());
    }
    if (kept.every((i) => !i.isActionable)) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> accept(DriverInvite invite) async {
    if (!_beginResponse(invite)) return;
    try {
      final offerId = await _accept(
        rideId: invite.rideId,
        waveId: invite.waveId,
      );
      _removeItem(invite.waveId);
      state = state.copyWith(
        infoMessage: offerId.isNotEmpty
            ? 'Offer sent — the passenger will choose a driver.'
            : 'Invitation accepted.',
        clearError: true,
      );
      unawaited(refresh());
    } catch (error, stack) {
      await _handleResponseFailure(error, stack, invite, accepted: true);
    } finally {
      _endResponse(invite.waveId);
    }
  }

  Future<void> decline(DriverInvite invite) async {
    if (!_beginResponse(invite, allowExpired: true)) return;
    try {
      await _decline(rideId: invite.rideId, waveId: invite.waveId);
      _removeItem(invite.waveId);
      state = state.copyWith(clearError: true);
    } catch (error, stack) {
      await _handleResponseFailure(error, stack, invite, accepted: false);
    } finally {
      _endResponse(invite.waveId);
    }
  }

  bool _beginResponse(DriverInvite invite, {bool allowExpired = false}) {
    if (state.respondingWaveIds.contains(invite.waveId)) return false;
    if (!allowExpired && isLocallyExpired(invite)) {
      _removeItem(invite.waveId);
      state = state.copyWith(
        errorMessage: 'This offer expired.',
        clearInfo: true,
      );
      return false;
    }
    state = state.copyWith(
      respondingWaveIds: {...state.respondingWaveIds, invite.waveId},
      clearError: true,
      clearInfo: true,
    );
    return true;
  }

  void _endResponse(String waveId) {
    state = state.copyWith(
      respondingWaveIds: state.respondingWaveIds
          .where((id) => id != waveId)
          .toSet(),
    );
  }

  Future<void> _handleResponseFailure(
    Object error,
    StackTrace stack,
    DriverInvite invite, {
    required bool accepted,
  }) async {
    final failure = _failures.fromException(error, stack);
    final code = failure.maybeWhen(
      conflict: (message, code) => code,
      forbidden: (message) => 'FORBIDDEN',
      validation: (message, fieldErrors) => 'VALIDATION',
      orElse: () => null,
    );

    if (code == 'INVITE_EXPIRED' || code == 'INVITE_ALREADY_RESPONDED') {
      _removeItem(invite.waveId);
      state = state.copyWith(
        errorMessage:
            code == 'INVITE_EXPIRED'
                ? 'This offer expired.'
                : 'This invitation was already answered.',
        clearInfo: true,
      );
      unawaited(refresh());
      return;
    }

    // Stale ride state (assigned/cancelled/version mismatch) — drop the card
    // and resync; the list is authoritative.
    if (code == 'ALREADY_ASSIGNED' ||
        code == 'STATE_CONFLICT' ||
        code == 'VERSION_CONFLICT' ||
        code == 'VALIDATION') {
      _removeItem(invite.waveId);
      state = state.copyWith(
        errorMessage:
            'This ride request is no longer available. Refreshing invites.',
        clearInfo: true,
      );
      unawaited(refresh());
      return;
    }

    state = state.copyWith(
      errorMessage:
          accepted
              ? 'Could not accept the invitation: ${failure.userMessage}'
              : 'Could not decline the invitation: ${failure.userMessage}',
      clearInfo: true,
    );
  }

  void _removeItem(String waveId) {
    _applyItems(
      state.items.where((i) => i.waveId != waveId).toList(growable: false),
    );
  }

  void _applyItems(List<DriverInvite> items) {
    state = state.copyWith(
      phase: items.isEmpty
          ? DriverInvitesPhase.empty
          : DriverInvitesPhase.ready,
      items: items,
    );
    _ensureTicker();
  }

  void _ensureTicker() {
    final hasActive = state.items.any((i) => i.isActionable);
    if (hasActive && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => tickCountdown(),
      );
    } else if (!hasActive && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }
}

final driverInvitesViewModelProvider = NotifierProvider.autoDispose<
    DriverInvitesViewModel, DriverInvitesUiState>(
  DriverInvitesViewModel.new,
);
