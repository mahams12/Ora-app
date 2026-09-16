import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/ride.dart';
import '../active_ride/active_ride_display.dart';
import '../view_models/active_ride_view_model.dart';

/// Passenger active-ride screen — server-authoritative, no maps/GPS/driver controls.
class ActiveRideView extends ConsumerStatefulWidget {
  const ActiveRideView({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<ActiveRideView> createState() => _ActiveRideViewState();
}

class _ActiveRideViewState extends ConsumerState<ActiveRideView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vm = ref.read(activeRideViewModelProvider(widget.rideId).notifier);
    if (state == AppLifecycleState.resumed) {
      unawaited(vm.resumePolling());
      return;
    }
    vm.pausePolling();
  }

  Future<void> _confirmCancel(ActiveRideViewModel vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: OraColors.surfaceElevated,
          title: Text(
            'Cancel ride?',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          content: Text(
            'This asks Ora\'s servers to cancel the ride. The state will update '
            'only after the server confirms.',
            style: OraTypography.body(OraColors.textSecondary),
          ),
          actions: [
            OraButton(
              label: 'Keep ride',
              expand: false,
              variant: OraButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            OraButton(
              label: 'Cancel ride',
              expand: false,
              variant: OraButtonVariant.danger,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await vm.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final phase = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.phase),
    );
    final isRefreshing = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.isRefreshing),
    );
    final errorMessage = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.errorMessage),
    );
    final vm = ref.read(activeRideViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    ref.listen(activeRideViewModelProvider(rideId), (prev, next) {
      if (!mounted) return;
      final ride = next.ride;
      if (ride != null &&
          isMarketplaceRideState(ride.state) &&
          prev?.ride?.state != ride.state) {
        context.go(AppRoutes.offersInboxPath(ride.rideId));
      }
    });

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Active ride',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Home',
          onPressed: () => context.go(AppRoutes.home),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: isRefreshing ? null : () => vm.refresh(),
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (phase) {
          ActiveRidePhase.initialLoading => const Center(
              child: OraLoadingIndicator(message: 'Loading your ride…'),
            ),
          ActiveRidePhase.fatalError => OraErrorState(
              title: 'Ride unavailable',
              message: errorMessage ?? 'Something went wrong.',
              onRetry: () => vm.start(),
            ),
          ActiveRidePhase.active ||
          ActiveRidePhase.mutating ||
          ActiveRidePhase.ended =>
            _ActiveBody(
              rideId: rideId,
              padding: padding,
              onCancel: () => _confirmCancel(vm),
              onClose: () => vm.closeRide(),
              onRefresh: () => vm.refresh(),
              onHome: () => context.go(AppRoutes.home),
              onOffers: () => context.go(AppRoutes.offersInboxPath(rideId)),
              onRate: () => context.push(AppRoutes.rideRatingPath(rideId)),
            ),
        },
      ),
    );
  }
}

class _ActiveBody extends ConsumerWidget {
  const _ActiveBody({
    required this.rideId,
    required this.padding,
    required this.onCancel,
    required this.onClose,
    required this.onRefresh,
    required this.onHome,
    required this.onOffers,
    required this.onRate,
  });

  final String rideId;
  final double padding;
  final VoidCallback onCancel;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;
  final VoidCallback onHome;
  final VoidCallback onOffers;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ride = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.ride),
    );
    final isPolling = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.isPolling),
    );
    final isCancelling = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.isCancelling),
    );
    final isClosing = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.isClosing),
    );
    final canCancel = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.canCancel),
    );
    final canClose = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.canClose),
    );
    final connectivityDegraded = ref.watch(
      activeRideViewModelProvider(rideId)
          .select((s) => s.connectivityDegraded),
    );
    final infoMessage = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.infoMessage),
    );
    final errorMessage = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.errorMessage),
    );

    if (ride == null) {
      return const Center(child: OraLoadingIndicator());
    }

    final status = ride.state.toUpperCase();
    final fare = formatAgreedFare(ride);

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MapPlaceholder(),
            const SizedBox(height: OraSpacing.md),
            OraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OraChip(
                    label: status,
                    selected: !isActiveRideTerminalState(status),
                    variant: OraChipVariant.status,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    activeRideTitle(status),
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    activeRideMessage(status),
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
                  if (status == 'DRIVER_ARRIVED' && ride.arrivedAt != null)
                    _ArrivedWaitLabel(rideId: rideId, ride: ride),
                ],
              ),
            ),
            if (connectivityDegraded || infoMessage != null) ...[
              const SizedBox(height: OraSpacing.sm),
              Text(
                infoMessage ??
                    'Connection interrupted — updating when connection returns.',
                style: OraTypography.caption(OraColors.goldSoft),
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: OraSpacing.sm),
              Text(
                errorMessage,
                style: OraTypography.caption(OraColors.dangerForeground),
              ),
            ],
            const SizedBox(height: OraSpacing.md),
            OraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trip',
                    style: OraTypography.label(OraColors.textSecondary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    '${ride.pickup.address ?? 'Pickup'} → '
                    '${ride.destination.address ?? 'Destination'}',
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                  Text(
                    'Category ${ride.category}',
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                  if (fare != null) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'Agreed fare $fare',
                      style: OraTypography.body(OraColors.textPrimary),
                    ),
                  ],
                  if (ride.cancellationReason != null &&
                      ride.cancellationReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'Reason: ${ride.cancellationReason}',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: OraSpacing.lg),
            if (isPolling)
              Text(
                'Checking for server updates…',
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.textMuted),
              ),
            const SizedBox(height: OraSpacing.md),
            if (canCancel)
              OraButton(
                label: 'Cancel ride',
                variant: OraButtonVariant.outline,
                isLoading: isCancelling,
                onPressed: isCancelling ? null : onCancel,
              ),
            if (canClose) ...[
              OraButton(
                label: 'Close ride',
                isLoading: isClosing,
                onPressed: isClosing ? null : onClose,
              ),
              const SizedBox(height: OraSpacing.xs),
              Text(
                'After the ride is closed on the server, you can rate it.',
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ],
            if (status == 'RIDE_COMPLETED' || status == 'RIDE_CLOSED') ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Rate ride',
                variant: status == 'RIDE_CLOSED'
                    ? OraButtonVariant.primary
                    : OraButtonVariant.outline,
                onPressed: onRate,
              ),
            ],
            if (isActiveRideTerminalState(status) ||
                status == 'RIDE_CLOSED') ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Back to Home',
                variant: OraButtonVariant.ghost,
                onPressed: onHome,
              ),
            ],
            if (isMarketplaceRideState(status)) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'View offers',
                onPressed: onOffers,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rebuilds only when [ActiveRideViewModel.arrivedNow] ticks — not on poll.
class _ArrivedWaitLabel extends ConsumerWidget {
  const _ArrivedWaitLabel({required this.rideId, required this.ride});

  final String rideId;
  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock =
        ref.read(activeRideViewModelProvider(rideId).notifier).arrivedNow;
    return ValueListenableBuilder<DateTime>(
      valueListenable: clock,
      builder: (context, now, _) {
        final wait = arrivedWaitLabel(ride, now);
        if (wait == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: OraSpacing.md),
          child: Text(
            wait,
            style: OraTypography.bodyEmphasis(OraColors.primary),
          ),
        );
      },
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.xxl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OraColors.navy, OraColors.navyElevated],
        ),
        border: Border.all(color: OraColors.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(OraSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: OraColors.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: OraSpacing.xs),
              Text(
                'Map preview',
                style: OraTypography.label(OraColors.textPrimary),
              ),
              Text(
                'Live maps, GPS, and driver markers are not in this build. '
                'This is not your location.',
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
