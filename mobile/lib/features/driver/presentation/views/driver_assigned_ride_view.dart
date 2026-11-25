import 'dart:async';
import 'dart:math' as math;

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
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_assets.dart';
import '../../domain/location/driver_location_lifecycle.dart';
import '../driver_display.dart';
import '../location/driver_location_session.dart';
import '../view_models/driver_assigned_ride_view_model.dart';
import '../widgets/driver_job_map.dart';
import '../widgets/driver_location_status_line.dart';
import '../widgets/driver_ui_kit.dart';

/// Driver assigned-job detail — progression + cancel/close.
///
/// Live job map (pickup/destination/driver marker) plus RTDB trip-location
/// publishing via [driverLocationSessionProvider].
class DriverAssignedRideView extends ConsumerStatefulWidget {
  const DriverAssignedRideView({
    required this.rideId,
    this.title = 'Active Ride',
    this.subtitle = 'Manage your current trip',
    this.homeRoute = AppRoutes.driverHome,
    super.key,
  });

  final String rideId;

  /// Header copy + fallback route — logistics partners get delivery wording
  /// and their own shell home.
  final String title;
  final String subtitle;
  final String homeRoute;

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
    final vm = ref.read(
      driverAssignedRideViewModelProvider(widget.rideId).notifier,
    );
    if (state == AppLifecycleState.resumed) {
      unawaited(vm.resumePolling());
    } else {
      vm.pausePolling();
    }
    _notifyLocationLifecycle(state);
  }

  void _notifyLocationLifecycle(AppLifecycleState state) {
    final provider = driverLocationSessionProvider(widget.rideId);
    if (!ref.exists(provider)) return;
    ref.read(provider.notifier).onAppLifecycle(state);
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
            'This will cancel the ride for you and the passenger.',
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

  // ── Ora Courier ──────────────────────────────────────────────────────────

  /// Courier OTP-gated transitions open a code-entry sheet; every other
  /// primary action delegates to the view model as before. Ora Courier v2
  /// is code-free — the stop checklist carries its actions instead.
  Future<void> _runPrimary(DriverAssignedRideViewModel vm) async {
    final ride = ref.read(
      driverAssignedRideViewModelProvider(widget.rideId).select((s) => s.ride),
    );
    if (ride == null) return;
    final s = ride.state.toUpperCase();
    if (!ride.isCourier || ride.isCourierV2) {
      await vm.runPrimaryAction();
      return;
    }
    final spec = switch (s) {
      'DRIVER_ARRIVED' => (
        'Confirm pickup',
        'Ask the sender for the pickup code, then take the parcel.',
        (String code) => vm.startRide(otp: code),
      ),
      'RIDE_STARTED' => (
        'Confirm delivery',
        'Ask the receiver for the delivery code.',
        (String code) => vm.completeRide(otp: code),
      ),
      'RETURNING' => (
        'Confirm return',
        'Ask the sender for the return code when handing the parcel back.',
        (String code) => vm.completeReturn(otp: code),
      ),
      _ => null,
    };
    if (spec == null) {
      await vm.runPrimaryAction();
      return;
    }
    final code = await _showOtpSheet(title: spec.$1, hint: spec.$2);
    if (code == null || !mounted) return;
    await spec.$3(code);
  }

  Future<String?> _showOtpSheet({required String title, required String hint}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      builder: (_) => _OtpEntrySheet(title: title, hint: hint),
    );
  }

  Future<void> _showFailureSheet(DriverAssignedRideViewModel vm) async {
    String reason = kCourierFailureReasons.first;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: OraColors.surfaceElevated,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(OraSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Delivery failed — why?',
                    style: OraTypography.title(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    'This is recorded on the server. The parcel stays with '
                    'you — retry delivery or start a return next.',
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
                  const SizedBox(height: OraSpacing.md),
                  Wrap(
                    spacing: OraSpacing.xs,
                    runSpacing: OraSpacing.xs,
                    children: [
                      for (final r in kCourierFailureReasons)
                        OraChip(
                          label: courierFailureReasonLabel(r),
                          selected: reason == r,
                          onTap: () => setSheetState(() => reason = r),
                        ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.md),
                  OraButton(
                    label: 'Record failed delivery',
                    variant: OraButtonVariant.danger,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  OraButton(
                    label: 'Back',
                    variant: OraButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (confirmed == true) {
      await vm.failDelivery(reason: reason);
    }
  }

  Future<void> _confirmReturnStart(DriverAssignedRideViewModel vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: OraColors.surfaceElevated,
          title: Text(
            'Return parcel to sender?',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          content: Text(
            'You will take the parcel back to the sender. Handover is '
            'confirmed with the sender\'s return code.',
            style: OraTypography.body(OraColors.textSecondary),
          ),
          actions: [
            OraButton(
              label: 'Keep delivering',
              expand: false,
              variant: OraButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            OraButton(
              label: 'Start return',
              expand: false,
              variant: OraButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await vm.startReturn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final phase = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.phase),
    );
    final errorMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.errorMessage),
    );
    final vm = ref.read(driverAssignedRideViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          DriverHeroArtHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            leadingIcon: context.canPop() ? Icons.arrow_back_rounded : null,
            leadingTooltip: 'Back',
            onLeading: context.canPop() ? () => context.pop() : null,
          ),
          Expanded(
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
              DriverAssignedRidePhase.ended => _JobBody(
                rideId: rideId,
                padding: padding,
                onPrimary: () => _runPrimary(vm),
                onCancel: () => _confirmCancel(vm),
                onClose: () => vm.closeRide(),
                onRefresh: () => vm.refresh(),
                onFailDelivery: () => _showFailureSheet(vm),
                onRetryDelivery: () => vm.retryDelivery(),
                onStartReturn: () => _confirmReturnStart(vm),
                onRate: () => context.push(AppRoutes.rideRatingPath(rideId)),
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(widget.homeRoute);
                  }
                },
              ),
            },
          ),
        ],
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
    required this.onFailDelivery,
    required this.onRetryDelivery,
    required this.onStartReturn,
    required this.onRate,
    required this.onBack,
  });

  final String rideId;
  final double padding;
  final VoidCallback onPrimary;
  final VoidCallback onCancel;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;
  final VoidCallback onFailDelivery;
  final VoidCallback onRetryDelivery;
  final VoidCallback onStartReturn;
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
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.activeMutation),
    );
    final canCancel = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.canCancel),
    );
    final canClose = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.canClose),
    );
    final canFailDelivery = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.canFailDelivery),
    );
    final canRetryDelivery = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.canRetryDelivery),
    );
    final canStartReturn = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.canStartReturn),
    );
    final canConfirmReturn = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.canConfirmReturn),
    );
    final primaryLabel = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.primaryActionLabel),
    );
    final connectivityDegraded = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.connectivityDegraded),
    );
    final infoMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.infoMessage),
    );
    final errorMessage = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.errorMessage),
    );

    if (ride == null) {
      return const Center(child: OraLoadingIndicator());
    }

    final status = ride.state.toUpperCase();
    final primaryLoading =
        isMutating &&
        activeMutation != DriverRideMutation.cancel &&
        activeMutation != DriverRideMutation.close &&
        activeMutation != DriverRideMutation.failDelivery &&
        activeMutation != DriverRideMutation.retryDelivery &&
        activeMutation != DriverRideMutation.startReturn;

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
            _StatusHeroCard(status: status, ride: ride),
            DriverLocationStatusLine(rideId: rideId),
            const SizedBox(height: OraSpacing.sm),
            _PassengerCard(ride: ride),
            const SizedBox(height: OraSpacing.md),
            _MapCard(ride: ride),
            const SizedBox(height: OraSpacing.md),
            _TripRouteCard(ride: ride),
            const SizedBox(height: OraSpacing.md),
            _ServiceFareCard(ride: ride),
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
            if (ride.cancellationReason != null &&
                ride.cancellationReason!.trim().isNotEmpty) ...[
              const SizedBox(height: OraSpacing.xs),
              Text(
                'Reason: ${ride.cancellationReason}',
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ],
            if (ride.deliveryFailedReason != null &&
                ride.deliveryFailedReason!.trim().isNotEmpty) ...[
              const SizedBox(height: OraSpacing.xs),
              Text(
                'Failure: '
                '${courierFailureReasonLabel(ride.deliveryFailedReason!)}',
                style: OraTypography.caption(OraColors.goldSoft),
              ),
            ],
            // Ora Courier — parcel manifest for the assigned driver.
            if (ride.isCourier && ride.parcel != null) ...[
              const SizedBox(height: OraSpacing.md),
              _DriverParcelCard(ride: ride),
            ],
            // Ora Courier v2 — per-stop checklist + B&D shopping + cash.
            if (ride.isCourierV2) ...[
              const SizedBox(height: OraSpacing.md),
              _DriverStopsCard(rideId: rideId, ride: ride),
            ],
            const SizedBox(height: OraSpacing.lg),
            if (isPolling)
              Text(
                'Updating ride…',
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.textMuted),
              ),
            const SizedBox(height: OraSpacing.md),
            if (primaryLabel != null)
              DriverActionButton(
                label: primaryLabel,
                isLoading: primaryLoading,
                onPressed: isMutating ? null : onPrimary,
                icon: Icons.send_rounded,
                trailingIcon: null,
              ),
            // Ora Courier — delivery exceptions + return-to-sender.
            if (canFailDelivery) ...[
              if (primaryLabel != null) const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Delivery failed',
                variant: OraButtonVariant.outline,
                isLoading: activeMutation == DriverRideMutation.failDelivery,
                onPressed: isMutating ? null : onFailDelivery,
              ),
            ],
            if (canRetryDelivery) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Retry delivery',
                isLoading: activeMutation == DriverRideMutation.retryDelivery,
                onPressed: isMutating ? null : onRetryDelivery,
              ),
            ],
            if (canStartReturn) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Return parcel to sender',
                variant: OraButtonVariant.outline,
                isLoading: activeMutation == DriverRideMutation.startReturn,
                onPressed: isMutating ? null : onStartReturn,
              ),
            ],
            // Ora Courier v2 — code-free return handover (v1 uses the
            // return-code sheet through the primary action instead).
            if (ride.isCourierV2 && canConfirmReturn) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Confirm parcel returned',
                isLoading: activeMutation == DriverRideMutation.completeReturn,
                onPressed: isMutating
                    ? null
                    : () => ref
                          .read(
                            driverAssignedRideViewModelProvider(
                              rideId,
                            ).notifier,
                          )
                          .completeReturn(),
              ),
            ],
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
                'After you close this ride, you can leave a rating.',
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
            const SizedBox(height: OraSpacing.md),
            _TripStepper(status: status),
          ],
        ),
      ),
    );
  }
}

// ── Ora Courier ─────────────────────────────────────────────────────────────

/// Driver-facing parcel manifest — includes sender/receiver contacts since
/// the assigned driver legitimately needs them for handover. Only the
/// assigned driver sees this projection (server-enforced).
class _DriverParcelCard extends StatelessWidget {
  const _DriverParcelCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final parcel = ride.parcel!;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parcel', style: OraTypography.label(OraColors.textSecondary)),
          const SizedBox(height: OraSpacing.xs),
          Text(
            '${parcel['description'] ?? 'Parcel'} — '
            '${(parcel['size'] ?? '').toString().toLowerCase()} · '
            '${parcel['weightKg'] ?? '?'} kg × ${parcel['quantity'] ?? 1} · '
            '${parcel['parcelCategory'] ?? 'other'}',
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
          if ((parcel['handlingInstructions'] as String?)?.trim().isNotEmpty ==
              true) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Handling: ${parcel['handlingInstructions']}',
              style: OraTypography.caption(OraColors.goldSoft),
            ),
          ],
          const SizedBox(height: OraSpacing.sm),
          Text(
            'Sender: ${parcel['senderName'] ?? '—'} '
            '(${parcel['senderPhone'] ?? '—'})',
            style: OraTypography.body(OraColors.textSecondary),
          ),
          Text(
            'Receiver: ${parcel['receiverName'] ?? '—'} '
            '(${parcel['receiverPhone'] ?? '—'})',
            style: OraTypography.body(OraColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _OtpEntrySheet extends StatefulWidget {
  const _OtpEntrySheet({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_OtpEntrySheet> createState() => _OtpEntrySheetState();
}

class _OtpEntrySheetState extends State<_OtpEntrySheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OraSpacing.lg,
        OraSpacing.lg,
        OraSpacing.lg,
        OraSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: OraTypography.title(OraColors.textPrimary)),
          const SizedBox(height: OraSpacing.xs),
          Text(widget.hint, style: OraTypography.body(OraColors.textSecondary)),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            controller: _controller,
            label: 'Confirmation code',
            hint: '6-digit code',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: OraSpacing.md),
          OraButton(
            label: widget.title,
            onPressed: () {
              final code = _controller.text.trim();
              if (code.isEmpty) return;
              Navigator.of(context).pop(code);
            },
          ),
        ],
      ),
    );
  }
}

// ── Ora Courier v2 — driver stop checklist ───────────────────────────────────

/// Per-stop progression for code-free deliveries: arrive → confirm per stop,
/// itemized shop quotes, purchase totals, failure reasons, and the
/// driver-reported cash settlement after the last drop-off.
class _DriverStopsCard extends ConsumerWidget {
  const _DriverStopsCard({required this.rideId, required this.ride});

  final String rideId;
  final Ride ride;

  static const _failReasons = <String, String>{
    'SENDER_UNAVAILABLE': 'Sender not available',
    'SHOP_CLOSED': 'Shop is closed',
    'ITEM_UNAVAILABLE': 'Items unavailable',
    'PRICE_REJECTED': 'Customer rejected prices',
    'BUDGET_EXCEEDED': 'Over the shopping budget',
    'RECEIVER_UNREACHABLE': 'Receiver unreachable',
    'ADDRESS_INCORRECT': 'Address incorrect',
    'RECEIVER_REJECTED': 'Receiver refused items',
    'PAYMENT_REFUSED': 'Cash payment refused',
    'PARCEL_DAMAGED': 'Parcel damaged',
    'OTHER': 'Other',
  };

  IconData _iconFor(RideStop s) => switch (s.type) {
    'SHOP' => Icons.storefront_outlined,
    'DROPOFF' => Icons.flag_outlined,
    _ => Icons.inventory_2_outlined,
  };

  String _stopTitle(RideStop s) =>
      s.label ?? s.location.address ?? 'Stop ${s.seq + 1}';

  Future<void> _openQuoteSheet(
    BuildContext context,
    WidgetRef ref,
    RideStop stop,
  ) async {
    final items = await showModalBottomSheet<List<Map<String, Object?>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.xxl),
        ),
      ),
      builder: (_) => _QuoteEntrySheet(stop: stop),
    );
    if (items == null) return;
    await ref
        .read(driverAssignedRideViewModelProvider(rideId).notifier)
        .submitStopQuote(stop.seq, items);
  }

  Future<void> _openPurchaseSheet(
    BuildContext context,
    WidgetRef ref,
    RideStop stop,
  ) async {
    final approved = stop.quote?['totalMinor'] as int? ?? 0;
    final total = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.xxl),
        ),
      ),
      builder: (_) => _PurchaseTotalSheet(approvedMinor: approved),
    );
    if (total == null) return;
    await ref
        .read(driverAssignedRideViewModelProvider(rideId).notifier)
        .confirmStop(stop.seq, purchaseTotalMinor: total);
  }

  Future<void> _openFailSheet(
    BuildContext context,
    WidgetRef ref,
    RideStop stop,
  ) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.xxl),
        ),
      ),
      builder: (_) =>
          const _StopFailSheet(reasons: _DriverStopsCard._failReasons),
    );
    if (reason == null) return;
    await ref
        .read(driverAssignedRideViewModelProvider(rideId).notifier)
        .failStop(stop.seq, reason: reason);
  }

  Future<void> _openSettlementSheet(BuildContext context, WidgetRef ref) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.xxl),
        ),
      ),
      builder: (_) => const _SettlementReportSheet(),
    );
    if (status == null) return;
    await ref
        .read(driverAssignedRideViewModelProvider(rideId).notifier)
        .reportSettlement(status);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(driverAssignedRideViewModelProvider(rideId).notifier);
    final isMutating = ref.watch(
      driverAssignedRideViewModelProvider(rideId).select((s) => s.isMutating),
    );
    final activeMutation = ref.watch(
      driverAssignedRideViewModelProvider(
        rideId,
      ).select((s) => s.activeMutation),
    );
    final stops = ride.stops ?? const <RideStop>[];
    final current = ride.currentStop;
    final settlement = ride.settlement;
    final shopping = ride.shopping;
    String fmt(Object? minor) => minor is int ? 'Rs ${minor ~/ 100}' : '—';
    final canReportCash =
        settlement != null &&
        settlement['driverReportedStatus'] == null &&
        ride.state == 'RIDE_COMPLETED';
    final alreadyReported = settlement?['driverReportedStatus'] as String?;

    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ride.isBuyDeliver ? 'Shops & stops' : 'Stops',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          for (final s in stops) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconFor(s),
                  size: 18,
                  color: s.isDone
                      ? OraColors.tealBright
                      : s.isFailed
                      ? OraColors.danger
                      : (current?.seq == s.seq
                            ? OraColors.primary
                            : OraColors.textMuted),
                ),
                const SizedBox(width: OraSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stopTitle(s),
                        style: OraTypography.body(OraColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.items != null && s.items!.isNotEmpty)
                        Text(
                          s.items!
                              .map(
                                (i) =>
                                    '${i['qty'] ?? 1}× ${i['name'] ?? 'item'}',
                              )
                              .join(', '),
                          style: OraTypography.caption(OraColors.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (s.shopBudgetMinor != null)
                        Text(
                          'Shop budget: ${fmt(s.shopBudgetMinor)}',
                          style: OraTypography.caption(OraColors.goldSoft),
                        ),
                      if (s.instructions != null && s.instructions!.isNotEmpty)
                        Text(
                          s.instructions!,
                          style: OraTypography.caption(OraColors.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (s.status == 'WAITING_APPROVAL')
                        Text(
                          'Quote sent — waiting for customer approval '
                          '(${fmt(s.quote?['totalMinor'])})',
                          style: OraTypography.caption(OraColors.goldSoft),
                        ),
                      if (s.quote?['rejectedAt'] != null)
                        Text(
                          'Customer rejected the prices — send a new quote.',
                          style: OraTypography.caption(OraColors.danger),
                        ),
                      if (s.purchase != null)
                        Text(
                          'Purchased for ${fmt(s.purchase?['totalMinor'])}',
                          style: OraTypography.caption(OraColors.tealBright),
                        ),
                      if (s.failureReason != null)
                        Text(
                          'Failed: '
                          '${_failReasons[s.failureReason] ?? s.failureReason}',
                          style: OraTypography.caption(OraColors.danger),
                        ),
                    ],
                  ),
                ),
                Text(
                  s.status == 'DONE'
                      ? 'Done'
                      : s.status == 'ARRIVED'
                      ? 'Arrived'
                      : s.isFailed
                      ? 'Failed'
                      : current?.seq == s.seq
                      ? 'Next'
                      : 'Pending',
                  style: OraTypography.caption(
                    s.isDone
                        ? OraColors.tealBright
                        : s.isFailed
                        ? OraColors.danger
                        : OraColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: OraSpacing.xs),
          ],
          // Current-stop actions.
          if (current != null && !isDriverJobTerminalState(ride.state)) ...[
            const Divider(height: OraSpacing.lg),
            if (current.status == 'PENDING')
              OraButton(
                label: 'Arrived at ${_stopTitle(current)}',
                isLoading: activeMutation == DriverRideMutation.stopArrive,
                onPressed: isMutating ? null : () => vm.arriveStop(current.seq),
              ),
            if (current.status == 'ARRIVED') ...[
              if (current.type == 'SHOP' &&
                  (current.quote == null ||
                      current.quote!['rejectedAt'] != null))
                OraButton(
                  label: 'Enter item prices',
                  isLoading: activeMutation == DriverRideMutation.stopQuote,
                  onPressed: isMutating
                      ? null
                      : () => _openQuoteSheet(context, ref, current),
                )
              else if (current.type == 'SHOP' &&
                  current.quote?['approvedAt'] != null)
                OraButton(
                  label:
                      'Confirm purchase '
                      '(${fmt(current.quote?['totalMinor'])})',
                  isLoading: activeMutation == DriverRideMutation.stopConfirm,
                  onPressed: isMutating
                      ? null
                      : () => _openPurchaseSheet(context, ref, current),
                )
              else if (current.type != 'SHOP')
                OraButton(
                  label: current.type == 'DROPOFF'
                      ? 'Confirm delivered'
                      : 'Confirm collected',
                  isLoading: activeMutation == DriverRideMutation.stopConfirm,
                  onPressed: isMutating
                      ? null
                      : () => vm.confirmStop(current.seq),
                ),
              const SizedBox(height: OraSpacing.xs),
            ],
            if (current.status == 'WAITING_APPROVAL') ...[
              OraButton(
                label: 'Update prices',
                variant: OraButtonVariant.outline,
                onPressed: isMutating
                    ? null
                    : () => _openQuoteSheet(context, ref, current),
              ),
              const SizedBox(height: OraSpacing.xs),
            ],
            if (current.status == 'PENDING' ||
                current.status == 'ARRIVED' ||
                current.status == 'WAITING_APPROVAL')
              Center(
                child: TextButton(
                  onPressed: isMutating
                      ? null
                      : () => _openFailSheet(context, ref, current),
                  child: Text(
                    "Can't complete this stop",
                    style: OraTypography.label(OraColors.danger),
                  ),
                ),
              ),
          ],
          // buy_deliver — budget tracking.
          if (shopping != null) ...[
            const Divider(height: OraSpacing.lg),
            _SettleLine(
              label: 'Shopping budget',
              value: fmt(shopping['totalBudgetMinor']),
            ),
            if ((shopping['approvedTotalMinor'] as int? ?? 0) > 0)
              _SettleLine(
                label: 'Approved',
                value: fmt(shopping['approvedTotalMinor']),
              ),
            if ((shopping['spentMinor'] as int? ?? 0) > 0)
              _SettleLine(label: 'Spent', value: fmt(shopping['spentMinor'])),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Collect the shopping cost plus the delivery fare in cash '
              'from the customer.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          // Cash settlement — driver-reported, never platform-verified.
          if (settlement != null) ...[
            const Divider(height: OraSpacing.lg),
            _SettleLine(
              label: 'Total cash due',
              value: fmt(settlement['totalDueMinor']),
              emphasize: true,
            ),
            if (alreadyReported != null)
              Padding(
                padding: const EdgeInsets.only(top: OraSpacing.xxs),
                child: Text(
                  'You reported: $alreadyReported',
                  style: OraTypography.caption(
                    alreadyReported == 'PAID'
                        ? OraColors.tealBright
                        : OraColors.goldSoft,
                  ),
                ),
              ),
            if (canReportCash) ...[
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Report cash collection',
                isLoading: activeMutation == DriverRideMutation.settle,
                onPressed: isMutating
                    ? null
                    : () => _openSettlementSheet(context, ref),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SettleLine extends StatelessWidget {
  const _SettleLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: OraTypography.body(OraColors.textSecondary)),
          Text(
            value,
            style: emphasize
                ? OraTypography.bodyEmphasis(OraColors.primary)
                : OraTypography.body(OraColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// buy_deliver — driver enters the actual shelf price per item; the list is
/// seeded from the customer's requested items and sent for approval.
class _QuoteEntrySheet extends StatefulWidget {
  const _QuoteEntrySheet({required this.stop});

  final RideStop stop;

  @override
  State<_QuoteEntrySheet> createState() => _QuoteEntrySheetState();
}

class _QuoteEntrySheetState extends State<_QuoteEntrySheet> {
  late final List<TextEditingController> _priceControllers;

  List<Map<String, Object?>> get _requested =>
      widget.stop.items ?? const <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    _priceControllers = [for (final _ in _requested) TextEditingController()];
  }

  @override
  void dispose() {
    for (final c in _priceControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, Object?>>? _buildItems() {
    final items = <Map<String, Object?>>[];
    for (var i = 0; i < _requested.length; i++) {
      final rupees = int.tryParse(_priceControllers[i].text.trim());
      if (rupees == null || rupees < 0) return null;
      final req = _requested[i];
      items.add(<String, Object?>{
        'name': req['name'],
        'qty': req['qty'] ?? 1,
        if (req['note'] != null) 'note': req['note'],
        'priceMinor': rupees * 100,
      });
    }
    return items.isEmpty ? null : items;
  }

  int get _totalMinor =>
      _buildItems()?.fold<int>(
        0,
        (sum, i) => sum + ((i['priceMinor'] as int) * (i['qty'] as int)),
      ) ??
      0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item prices',
              style: OraTypography.title(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Enter the actual shelf price for each item — the customer '
              'approves this total before you buy.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.md),
            for (var i = 0; i < _requested.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: OraSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${_requested[i]['qty'] ?? 1}× '
                        '${_requested[i]['name'] ?? 'item'}',
                        style: OraTypography.body(OraColors.textPrimary),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: OraTextField(
                        controller: _priceControllers[i],
                        hint: 'Rs',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: OraSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
                Text(
                  'Rs ${_totalMinor ~/ 100}',
                  style: OraTypography.bodyEmphasis(OraColors.primary),
                ),
              ],
            ),
            const SizedBox(height: OraSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OraButton(
                label: 'Send for approval',
                onPressed: _buildItems() == null
                    ? null
                    : () => Navigator.of(context).pop(_buildItems()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// buy_deliver — driver confirms what they actually paid at the till
/// (≤ the customer-approved quote).
class _PurchaseTotalSheet extends StatefulWidget {
  const _PurchaseTotalSheet({required this.approvedMinor});

  final int approvedMinor;

  @override
  State<_PurchaseTotalSheet> createState() => _PurchaseTotalSheetState();
}

class _PurchaseTotalSheetState extends State<_PurchaseTotalSheet> {
  late final TextEditingController _total;

  @override
  void initState() {
    super.initState();
    _total = TextEditingController(text: '${widget.approvedMinor ~/ 100}');
  }

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  int? get _minor {
    final rupees = int.tryParse(_total.text.trim());
    if (rupees == null || rupees < 0) return null;
    return rupees * 100;
  }

  @override
  Widget build(BuildContext context) {
    final minor = _minor;
    final over = minor != null && minor > widget.approvedMinor;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm purchase',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'Approved: Rs ${widget.approvedMinor ~/ 100}. Enter what you '
            'actually paid — it can\'t exceed the approved total.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            controller: _total,
            label: 'Amount paid — Rs',
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: OraSpacing.xs),
              child: Text(
                'Can\'t exceed the approved amount.',
                style: OraTypography.caption(OraColors.danger),
              ),
            ),
          const SizedBox(height: OraSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Items purchased',
              onPressed: minor == null || over
                  ? null
                  : () => Navigator.of(context).pop(minor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-stop failure reasons — the server enum, presented readably.
class _StopFailSheet extends StatefulWidget {
  const _StopFailSheet({required this.reasons});

  final Map<String, String> reasons;

  @override
  State<_StopFailSheet> createState() => _StopFailSheetState();
}

class _StopFailSheetState extends State<_StopFailSheet> {
  late String _reason = widget.reasons.keys.first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stop failed — why?',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'The rest of the itinerary continues where possible.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.sm),
          Wrap(
            spacing: OraSpacing.xs,
            runSpacing: OraSpacing.xs,
            children: [
              for (final entry in widget.reasons.entries)
                OraChip(
                  label: entry.value,
                  selected: _reason == entry.key,
                  onTap: () => setState(() => _reason = entry.key),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Record failed stop',
              variant: OraButtonVariant.danger,
              onPressed: () => Navigator.of(context).pop(_reason),
            ),
          ),
        ],
      ),
    );
  }
}

/// Driver-reported cash outcome — never presented as platform-verified.
class _SettlementReportSheet extends StatelessWidget {
  const _SettlementReportSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cash collection',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'This records your report of what the customer paid — Ora does '
            'not verify cash payments.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Paid in full',
              onPressed: () => Navigator.of(context).pop('PAID'),
            ),
          ),
          const SizedBox(height: OraSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Partially paid',
              variant: OraButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop('PARTIAL'),
            ),
          ),
          const SizedBox(height: OraSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Not paid',
              variant: OraButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop('UNPAID'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Passenger header card — 3D avatar + role label + call/chat slots.
/// The job API exposes no passenger profile fields to the driver, so the
/// avatar falls back to the bundled 3D asset and no name/rating is shown.
class _PassengerCard extends StatelessWidget {
  const _PassengerCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final contactName = ride.isCourier
        ? (ride.parcel?['senderName'] as String?)?.trim()
        : null;
    final role = ride.isDelivery ? 'Sender' : 'Passenger';
    final name = (contactName != null && contactName.isNotEmpty)
        ? contactName
        : role;

    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: OraColors.info.withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: OraColors.info.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: const RideCardAssetImage(
              assetPath: RideCardAssets.avatar3d,
              width: 46,
              height: 46,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.bodyEmphasis(
                    OraColors.textPrimary,
                  ).copyWith(fontSize: 15),
                ),
                if (name != role)
                  Text(
                    role,
                    style: OraTypography.caption(
                      OraColors.textMuted,
                    ).copyWith(fontSize: 11.5),
                  ),
              ],
            ),
          ),
          _RoundContactButton(
            assetPath: RideCardAssets.phone,
            semanticLabel: 'Call $role',
            enabled: false,
          ),
          const SizedBox(width: OraSpacing.xs),
          _RoundContactButton(
            icon: Icons.near_me_rounded,
            semanticLabel: 'Navigate to $role',
            enabled: false,
          ),
        ],
      ),
    );
  }
}

class _RoundContactButton extends StatelessWidget {
  const _RoundContactButton({
    this.icon,
    this.assetPath,
    required this.semanticLabel,
    this.enabled = false,
  });

  final IconData? icon;
  final String? assetPath;
  final String semanticLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: enabled,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: OraColors.surfaceElevated,
          border: Border.all(color: OraColors.border),
          boxShadow: const [
            BoxShadow(
              color: OraColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: assetPath != null
              ? RideCardAssetImage(assetPath: assetPath!, width: 20, height: 20)
              : Icon(icon, size: 18, color: OraColors.textPrimary),
        ),
      ),
    );
  }
}

/// Orange status hero — pill chip + title + guidance over the winding-road
/// artwork extracted from the reference design.
class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({required this.status, required this.ride});

  final String status;
  final Ride ride;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
        ),
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59FF6A0D),
            blurRadius: 20,
            offset: Offset(0, 9),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Color(0x332A211D),
            blurRadius: 30,
            offset: Offset(0, 16),
            spreadRadius: -11,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.white],
                stops: [0.0, 0.45],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Image.asset(
                'assets/driver_tiles/status_road.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(OraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OraSpacing.xs,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x38FFFFFF),
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                    border: Border.all(color: const Color(0x52FFFFFF)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.directions_car_filled_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status.replaceAll('_', ' '),
                        style: OraTypography.caption(Colors.white).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OraSpacing.sm),
                Text(
                  driverJobTitle(status, courier: ride.isDelivery),
                  style: OraTypography.headline(Colors.white).copyWith(
                    fontWeight: FontWeight.w900,
                    shadows: const [
                      Shadow(
                        color: Color(0x33000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OraSpacing.xxs),
                SizedBox(
                  width: 230,
                  child: Text(
                    driverJobMessage(
                      status,
                      courier: ride.isDelivery,
                      courierV2: ride.isCourierV2,
                    ),
                    style: OraTypography.caption(
                      const Color(0xE6FFFFFF),
                    ).copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live job map in a rounded card with an honest distance pill — the
/// straight-line pickup→destination distance, shown when it is positive.
/// While GPS is still acquiring, a quiet placeholder holds the slot so no
/// preview chrome or coordinates leak before the driver's fix exists.
class _MapCard extends ConsumerWidget {
  const _MapCard({required this.ride});

  final Ride ride;

  static String? _straightLineKm(LatLngPoint a, LatLngPoint b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final km = r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    if (km <= 0) return null;
    return km >= 10
        ? '${km.toStringAsFixed(0)} km'
        : '${km.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!driverLocationShouldWatch(ride.state)) {
      return const SizedBox.shrink();
    }
    final fix = ref.watch(driverTripLatestFixProvider(ride.rideId));
    final distance = _straightLineKm(ride.pickup, ride.destination);

    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OraRadius.md),
        child: Stack(
          children: [
            if (fix == null)
              Container(
                height: 220,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF9EDE6), Color(0xFFF3E0CE)],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.route_rounded,
                        size: 26,
                        color: OraColors.goldSoft,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Locating you…',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              DriverJobMap(ride: ride, height: 220),
            if (distance != null)
              Positioned(
                top: OraSpacing.xs,
                left: OraSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OraSpacing.xs,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: OraColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                    boxShadow: const [
                      BoxShadow(
                        color: OraColors.shadow,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: OraColors.goldSharp,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Est. $distance',
                        style: OraTypography.caption(
                          OraColors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w700, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pickup + drop-off rows — green/orange pins, real addresses, trip
/// distance + agreed fare on the destination row.
class _TripRouteCard extends StatelessWidget {
  const _TripRouteCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final fare = formatMinorFare(
      ride.agreedFareMinor ?? ride.driverPayoutMinor,
      ride.agreedFareCurrency ?? ride.payoutCurrency,
    );

    return OraCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm,
      ),
      child: Column(
        children: [
          _RouteRow(
            pinColor: const Color(0xFF22C55E),
            title: 'Pickup',
            subtitle: rideCardLocationLabel(ride.pickup),
          ),
          const Divider(height: OraSpacing.lg, color: OraColors.border),
          _RouteRow(
            pinColor: OraColors.goldSharp,
            title: 'Drop-off',
            subtitle: rideCardLocationLabel(ride.destination),
            trailingTop: _MapCard._straightLineKm(
              ride.pickup,
              ride.destination,
            ),
            trailingBottom: fare ?? ride.paymentMethod,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.pinColor,
    required this.title,
    required this.subtitle,
    this.trailingTop,
    this.trailingBottom,
  });

  final Color pinColor;
  final String title;
  final String subtitle;
  final String? trailingTop;
  final String? trailingBottom;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.location_on_rounded, size: 22, color: pinColor),
        const SizedBox(width: OraSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: OraTypography.bodyEmphasis(
                  OraColors.textPrimary,
                ).copyWith(fontSize: 14),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OraTypography.caption(
                  OraColors.textMuted,
                ).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        if (trailingTop != null || trailingBottom != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (trailingTop != null)
                Text(
                  trailingTop!,
                  style: OraTypography.bodyEmphasis(
                    OraColors.textPrimary,
                  ).copyWith(fontSize: 13),
                ),
              if (trailingBottom != null)
                Text(
                  trailingBottom!,
                  style: OraTypography.caption(
                    OraColors.goldSharp,
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 12),
                ),
            ],
          ),
        const SizedBox(width: OraSpacing.xxs),
        const Icon(
          Icons.chevron_right_rounded,
          size: 20,
          color: OraColors.textMuted,
        ),
      ],
    );
  }
}

/// "Ride · Economy" service strip with the agreed fare.
class _ServiceFareCard extends StatelessWidget {
  const _ServiceFareCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final fare = formatMinorFare(
      ride.agreedFareMinor ?? ride.driverPayoutMinor,
      ride.agreedFareCurrency ?? ride.payoutCurrency,
    );

    return OraCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.directions_car_filled_rounded,
            size: 18,
            color: OraColors.goldSharp,
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Text(
              '${historyServiceTypeLabel(ride.serviceType)} · '
              '${ride.category}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OraTypography.bodyEmphasis(
                OraColors.textPrimary,
              ).copyWith(fontSize: 13.5),
            ),
          ),
          if (fare != null)
            Text(
              fare,
              style: OraTypography.title(
                OraColors.goldSharp,
              ).copyWith(fontWeight: FontWeight.w900, fontSize: 17),
            ),
        ],
      ),
    );
  }
}

/// Trip progress stepper — Assigned → En Route → Pick Up → Complete.
class _TripStepper extends StatelessWidget {
  const _TripStepper({required this.status});

  final String status;

  static const _labels = ['Assigned', 'En Route', 'Pick Up', 'Complete'];
  static const _icons = [
    Icons.check_rounded,
    Icons.send_rounded,
    Icons.person_rounded,
    Icons.flag_rounded,
  ];

  int get _activeIndex => switch (status.toUpperCase()) {
    'DRIVER_ASSIGNED' => 0,
    'DRIVER_EN_ROUTE' => 1,
    'DRIVER_ARRIVED' => 2,
    'RIDE_STARTED' || 'RIDE_COMPLETED' || 'RIDE_CLOSED' => 3,
    _ => 0,
  };

  bool get _finished =>
      const {'RIDE_COMPLETED', 'RIDE_CLOSED'}.contains(status.toUpperCase());

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return OraCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.md,
        vertical: OraSpacing.sm,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 1.4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: i <= active
                        ? OraColors.goldSharp.withValues(alpha: 0.55)
                        : OraColors.border,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= active || _finished
                        ? OraColors.goldSharp
                        : OraColors.surfaceElevated,
                    border: Border.all(
                      color: i <= active
                          ? OraColors.goldSharp
                          : OraColors.border,
                    ),
                    boxShadow: i == active
                        ? [
                            const BoxShadow(
                              color: Color(0x59FF6A0D),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    i < active || _finished ? Icons.check_rounded : _icons[i],
                    size: 15,
                    color: i <= active || _finished
                        ? Colors.white
                        : OraColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[i],
                  style:
                      OraTypography.caption(
                        i <= active ? OraColors.goldSharp : OraColors.textMuted,
                      ).copyWith(
                        fontSize: 10.5,
                        fontWeight: i == active
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
