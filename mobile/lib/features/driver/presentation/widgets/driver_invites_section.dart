import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_assets.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_map_thumb.dart';
import '../open_ride_display.dart';
import '../view_models/driver_invites_view_model.dart';
import 'driver_ui_kit.dart';

/// Incoming dispatch invitations — countdown cards above the open-rides
/// list. Renders the same epic [RideCard] as open rides, with an animated
/// perimeter countdown on Accept driven by the server deadline. Expired
/// cards auto-remove; accept creates a fare offer (passenger still selects).
class DriverInvitesSection extends ConsumerStatefulWidget {
  const DriverInvitesSection({
    super.key,
    this.sectionLabel = 'Ride requests for you',
    this.sheetTitle = 'New Ride Request',
    this.offerLabel = 'Passenger Offer',
  });

  /// Copy overrides — logistics partners show delivery wording.
  final String sectionLabel;
  final String sheetTitle;
  final String offerLabel;

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
  DriverInvitesViewModel vm, {
  required String sheetTitle,
  required String offerLabel,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: OraColors.surfaceElevated,
    builder: (context) => _InvitePreviewSheet(
      invite: invite,
      vm: vm,
      sheetTitle: sheetTitle,
      offerLabel: offerLabel,
    ),
  );
}

class _InvitePreviewSheet extends ConsumerWidget {
  const _InvitePreviewSheet({
    required this.invite,
    required this.vm,
    required this.sheetTitle,
    required this.offerLabel,
  });

  final DriverInvite invite;
  final DriverInvitesViewModel vm;
  final String sheetTitle;
  final String offerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ticks every ~1s so the countdown ring and caption stay live.
    ref.watch(driverInvitesViewModelProvider.select((s) => s.tickMs));
    final remaining = vm.remainingFor(invite);
    final actionable = invite.isActionable && remaining > Duration.zero;
    final responding = ref.watch(
      driverInvitesViewModelProvider.select(
        (s) => s.respondingWaveIds.contains(invite.waveId),
      ),
    );
    final distanceLabel = invite.distanceKm == null
        ? null
        : '${invite.distanceKm!.toStringAsFixed(1)} km';
    final offerAmountLabel = formatOpenRideFareMinor(
      invite.passengerOfferMinor,
    );
    final seconds = remaining.inSeconds;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DriverRequestSheetHeader(
              title: sheetTitle,
              onBack: () => Navigator.of(context).pop(),
              trailing: DriverCountdownRing(
                remaining: remaining,
                total: driverInviteWindow,
                bright: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.lg,
                OraSpacing.sm,
                OraSpacing.lg,
                OraSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RideCardMapBanner(
                    pickupLat: invite.pickup.lat,
                    pickupLng: invite.pickup.lng,
                    destinationLat: invite.destination.lat,
                    destinationLng: invite.destination.lng,
                    height: 118,
                    carAssetPath: RideCardAssets.carWhite,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  DriverRouteCard(
                    pickupLabel: rideCardLocationLabel(invite.pickup),
                    destinationLabel: rideCardLocationLabel(invite.destination),
                    pickupCaption: distanceLabel != null
                        ? 'Pickup ($distanceLabel)'
                        : 'Pickup',
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Row(
                    children: [
                      if (distanceLabel != null)
                        DriverStatPill(
                          icon: Icons.route_rounded,
                          label: distanceLabel,
                        ),
                      if (distanceLabel != null)
                        const SizedBox(width: OraSpacing.xs),
                      DriverStatPill(
                        icon: Icons.directions_car_rounded,
                        label: invite.serviceType,
                      ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  DriverOfferCard(
                    label: offerLabel,
                    amountLabel: offerAmountLabel,
                    trailing: Image.asset(
                      'assets/driver_tiles/wallet_3d.png',
                      width: 56,
                      height: 56,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: DriverActionButton.accept(
                          label: 'Accept',
                          isLoading: responding,
                          onPressed: actionable && !responding
                              ? () {
                                  Navigator.of(context).pop();
                                  vm.accept(invite);
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: OraSpacing.sm),
                      Expanded(
                        child: DriverActionButton.decline(
                          label: 'Decline',
                          onPressed: actionable && !responding
                              ? () {
                                  Navigator.of(context).pop();
                                  vm.decline(invite);
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  if (actionable) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: OraColors.goldDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Auto decline in $seconds seconds',
                          textAlign: TextAlign.center,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverInvitesSectionState extends ConsumerState<DriverInvitesSection> {
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
            widget.sectionLabel,
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
                  onTap: () => _openInvitePreview(
                    context,
                    ref,
                    invite,
                    vm,
                    sheetTitle: widget.sheetTitle,
                    offerLabel: widget.offerLabel,
                  ),
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
