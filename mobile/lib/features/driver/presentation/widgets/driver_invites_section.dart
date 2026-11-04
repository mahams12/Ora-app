import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/models/ride_map_preview_model.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../../../ride/presentation/widgets/ride_map_preview.dart';
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

/// Tap a request card → real map preview of pickup → destination with the
/// same Accept/Decline actions. One MapLibre surface at a time — keeps the
/// capped invite list cheap on low-end devices.
Future<void> _openInvitePreview(
  BuildContext context,
  WidgetRef ref,
  DriverInvite invite,
  DriverInvitesViewModel vm,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OraColors.surfaceElevated,
    builder: (context) => _InvitePreviewSheet(invite: invite, vm: vm),
  );
}

class _InvitePreviewSheet extends ConsumerWidget {
  const _InvitePreviewSheet({required this.invite, required this.vm});

  final DriverInvite invite;
  final DriverInvitesViewModel vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickup = gmaps.LatLng(invite.pickup.lat, invite.pickup.lng);
    final destination =
        gmaps.LatLng(invite.destination.lat, invite.destination.lng);
    final actionable = invite.isActionable;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ride request',
              style: OraTypography.headline(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.md),
              child: RideMapPreview(
                model: RideMapPreviewModel(
                  routeIdentity: RideMapPreviewModel.buildRouteIdentity(
                    pickup: pickup,
                    destination: destination,
                  ),
                  status: RideMapPreviewStatus.ready,
                  pickup: pickup,
                  destination: destination,
                  pickupLabel: rideCardLocationLabel(invite.pickup),
                  destinationLabel: rideCardLocationLabel(invite.destination),
                  distanceKm: invite.distanceKm,
                ),
                height: 220,
                enableMaps: ref.watch(activeRideMapsEnabledProvider),
              ),
            ),
            const SizedBox(height: OraSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OraButton(
                    label: 'Decline',
                    variant: OraButtonVariant.outline,
                    onPressed: actionable
                        ? () {
                            Navigator.of(context).pop();
                            vm.decline(invite);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: OraButton(
                    label: 'Accept',
                    onPressed: actionable
                        ? () {
                            Navigator.of(context).pop();
                            vm.accept(invite);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
                  onTap: () => _openInvitePreview(context, ref, invite, vm),
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
