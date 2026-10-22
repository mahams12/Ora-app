import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/offers/offer_display.dart';
import '../view_models/driver_invites_view_model.dart';

/// Incoming dispatch invitations — countdown cards above the open-rides
/// list. Expired cards auto-remove; accept creates a fare offer (passenger
/// still selects).
class DriverInvitesSection extends ConsumerStatefulWidget {
  const DriverInvitesSection({super.key});

  @override
  ConsumerState<DriverInvitesSection> createState() =>
      _DriverInvitesSectionState();
}

class _DriverInvitesSectionState
    extends ConsumerState<DriverInvitesSection> {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.items.isNotEmpty) ...[
          Text(
            'Ride requests for you',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          for (final invite in state.items)
            Padding(
              key: ValueKey('invite_${invite.waveId}'),
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: _InviteCard(
                invite: invite,
                remaining: vm.remainingFor(invite),
                responding: state.isResponding(invite.waveId),
                onAccept: () => vm.accept(invite),
                onDecline: () => vm.decline(invite),
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

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.remaining,
    required this.responding,
    required this.onAccept,
    required this.onDecline,
  });

  final DriverInvite invite;
  final Duration remaining;
  final bool responding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = remaining.inSeconds;
    final actionable = invite.isActionable && secondsLeft > 0;

    return Container(
      decoration: BoxDecoration(
        color: OraColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: actionable ? OraColors.primary : OraColors.textMuted,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invite.pickup.address ?? 'Pickup',
                  style: OraTypography.label(OraColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.arrow_forward,
                size: 16,
                color: OraColors.textMuted,
              ),
              const SizedBox(width: OraSpacing.xs),
              Expanded(
                child: Text(
                  invite.destination.address ?? 'Drop-off',
                  style: OraTypography.label(OraColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            'Passenger offer: '
            '${formatOfferAmountMinor(invite.passengerOfferMinor, invite.currency)}'
            '${invite.distanceKm != null ? ' · ${invite.distanceKm!.toStringAsFixed(1)} km' : ''}',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.sm),
          if (actionable)
            Text(
              'Accept within ${secondsLeft}s',
              style: OraTypography.label(
                secondsLeft <= 5
                    ? OraColors.dangerForeground
                    : OraColors.primary,
              ),
            )
          else
            Text(
              'Offer expired',
              style: OraTypography.label(OraColors.textMuted),
            ),
          const SizedBox(height: OraSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OraButton(
                  label: 'Accept',
                  isLoading: responding,
                  onPressed:
                      actionable && !responding ? onAccept : null,
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: OraButton(
                  label: 'Decline',
                  variant: OraButtonVariant.outline,
                  onPressed:
                      actionable && !responding ? onDecline : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
