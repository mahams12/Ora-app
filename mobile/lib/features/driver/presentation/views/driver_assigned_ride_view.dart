import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/presentation/active_ride/active_ride_display.dart';
import '../driver_display.dart';
import '../view_models/driver_assigned_ride_view_model.dart';

/// Driver assigned-job detail — progression + cancel/close, no maps/GPS.
class DriverAssignedRideView extends ConsumerStatefulWidget {
  const DriverAssignedRideView({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<DriverAssignedRideView> createState() =>
      _DriverAssignedRideViewState();
}

class _DriverAssignedRideViewState extends ConsumerState<DriverAssignedRideView>
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
    final vm =
        ref.read(driverAssignedRideViewModelProvider(widget.rideId).notifier);
    if (state == AppLifecycleState.resumed) {
      unawaited(vm.resumePolling());
      return;
    }
    vm.pausePolling();
  }

  Future<void> _confirmCancel(DriverAssignedRideViewModel vm) async {
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
      driverAssignedRideViewModelProvider(rideId).select((s) => s.phase),
    );
    final isRefreshing = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.isRefreshing),
    );
    final errorMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.errorMessage),
    );
    final vm = ref.read(driverAssignedRideViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Assigned ride',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.driverHome);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
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
          DriverAssignedRidePhase.initialLoading => const Center(
              child: OraLoadingIndicator(message: 'Loading job…'),
            ),
          DriverAssignedRidePhase.fatalError => OraErrorState(
              title: 'Ride unavailable',
              message: errorMessage ?? 'Something went wrong.',
              onRetry: () => vm.start(),
            ),
          DriverAssignedRidePhase.active ||
          DriverAssignedRidePhase.mutating ||
          DriverAssignedRidePhase.ended =>
            _JobBody(
              rideId: rideId,
              padding: padding,
              onPrimary: () => vm.runPrimaryAction(),
              onCancel: () => _confirmCancel(vm),
              onClose: () => vm.closeRide(),
              onRefresh: () => vm.refresh(),
              onRate: () => context.push(AppRoutes.rideRatingPath(rideId)),
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.driverHome);
                }
              },
            ),
        },
      ),
    );
  }
}

class _JobBody extends ConsumerWidget {
  const _JobBody({
    required this.rideId,
    required this.padding,
    required this.onPrimary,
    required this.onCancel,
    required this.onClose,
    required this.onRefresh,
    required this.onRate,
    required this.onBack,
  });

  final String rideId;
  final double padding;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;
  final VoidCallback onRate;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ride = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.ride),
    );
    final isPolling = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.isPolling),
    );
    final isMutating = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.isMutating),
    );
    final activeMutation = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.activeMutation),
    );
    final canCancel = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.canCancel),
    );
    final canClose = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.canClose),
    );
    final primaryLabel = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.primaryActionLabel),
    );
    final connectivityDegraded = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.connectivityDegraded),
    );
    final infoMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.infoMessage),
    );
    final errorMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId)
          .select((s) => s.errorMessage),
    );

    if (ride == null) {
      return const Center(child: OraLoadingIndicator());
    }

    final status = ride.state.toUpperCase();
    final fare = formatAgreedFare(ride);
    final primaryLoading = isMutating &&
        activeMutation != DriverRideMutation.cancel &&
        activeMutation != DriverRideMutation.close;

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
            OraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OraChip(
                    label: status,
                    selected: !isDriverJobTerminalState(status),
                    variant: OraChipVariant.status,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    driverJobTitle(status),
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    driverJobMessage(status),
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
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
            if (primaryLabel != null)
              OraButton(
                label: primaryLabel,
                isLoading: primaryLoading,
                onPressed: isMutating ? null : onPrimary,
              ),
            if (canCancel) ...[
              if (primaryLabel != null) const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Cancel ride',
                variant: OraButtonVariant.outline,
                isLoading: activeMutation == DriverRideMutation.cancel,
                onPressed: isMutating ? null : onCancel,
              ),
            ],
            if (canClose) ...[
              if (primaryLabel != null || canCancel)
                const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Close ride',
                isLoading: activeMutation == DriverRideMutation.close,
                onPressed: isMutating ? null : onClose,
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
            if (isDriverJobTerminalState(status)) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Back to assigned rides',
                variant: OraButtonVariant.ghost,
                onPressed: onBack,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
