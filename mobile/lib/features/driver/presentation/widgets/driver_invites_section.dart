import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../view_models/driver_invites_view_model.dart';

/// Incoming dispatch invitations — countdown cards above the open-rides
/// list. Renders the same epic [RideCard] as open rides, with an animated
/// perimeter countdown on Accept driven by the server deadline. Expired
/// cards auto-remove; accept creates a fare offer (passenger still selects).
class DriverInvitesSection extends ConsumerStatefulWidget {
  const DriverInvitesSection({super.key});

  @override
  ConsumerState<DriverInvitesSection> createState() =>
      _DriverInvitesSectionState();
}

class _DriverInvitesSectionState
    extends ConsumerState<DriverInvitesSection> {
  static const int _maxRenderedInvites = 8;

  bool _loadRequested = false;

  @override
  void initState() {
    super.initState();
    if (!_loadRequested) {
      _loadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(driverInvitesViewModelProvider.notifier).refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverInvitesViewModelProvider);
    final vm = ref.read(driverInvitesViewModelProvider.notifier);

    if (state.phase == DriverInvitesPhase.initialLoading ||
        (state.phase == DriverInvitesPhase.empty &&
            state.errorMessage == null)) {
      return const SizedBox.shrink();
    }

    // Cap rendered invites — each card is a full RideCard (asset image +
    // painters); an unbounded stack of historical waves causes UI-thread
    // jank on low-end devices (observed ANR on SM-A325F with ~24 stale
    // invites). Actionable invites always fit; newest-first order is kept.
    final items = state.items.take(_maxRenderedInvites).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isNotEmpty) ...[
          Text(
            'Ride requests for you',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          for (final invite in items)
            Padding(
              key: ValueKey('invite_${invite.waveId}'),
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: RideCard(
                model: RideCardAdapters.fromDriverInvite(
                  invite,
                  remaining: vm.remainingFor(invite),
                  windowTotal: driverInviteWindow,
                  responding: state.isResponding(invite.waveId),
                  onAccept: () => vm.accept(invite),
                  onDecline: () => vm.decline(invite),
                ),
              ),
            ),
          const SizedBox(height: OraSpacing.xs),
        ],
        if (state.infoMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: OraSpacing.sm),
            child: Text(
              state.infoMessage!,
              style: OraTypography.caption(OraColors.textPrimary),
            ),
          ),
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: OraSpacing.sm),
            child: Text(
              state.errorMessage!,
              style: OraTypography.caption(OraColors.dangerForeground),
            ),
          ),
      ],
    );
  }
}
