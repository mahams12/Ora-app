import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/ride.dart';
import '../active_ride/active_ride_display.dart';
import '../history/ride_history_display.dart';
import '../offers/offer_display.dart';
import '../location/trip_location_session.dart';
import '../view_models/active_ride_view_model.dart';
import '../widgets/active_ride_map.dart';

/// Passenger active-ride screen — HTTP ride state authoritative; RTDB display-only.
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
    final tripSession =
        ref.read(tripLocationSessionProvider(widget.rideId).notifier);
    tripSession.onAppLifecycle(state);
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
    final tripLocation = ref.watch(tripLocationSessionProvider(rideId));

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
            ActiveRideMap(
              ride: ride,
              locationSession: tripLocation,
              enableMaps: ref.watch(activeRideMapsEnabledProvider),
            ),
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
                    '${historyServiceTypeLabel(ride.serviceType)} · '
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
                  if (ride.deliveryFailedReason != null &&
                      ride.deliveryFailedReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'Failure reason: ${ride.deliveryFailedReason}',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            // Ora Courier — parcel manifest + confirmation codes.
            if (ride.isCourier) ...[
              const SizedBox(height: OraSpacing.md),
              _CourierParcelCard(ride: ride),
            ],
            // Ora Courier v2 — stop progress, quote approval, cash breakdown,
            // acknowledgement and dispute reporting.
            if (ride.isCourierV2) ...[
              const SizedBox(height: OraSpacing.md),
              _DeliveryProgressCard(rideId: rideId, ride: ride),
            ],
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
            if (status == 'RIDE_COMPLETED' ||
                status == 'RIDE_CLOSED' ||
                status == 'RETURNED') ...[
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


// ── Ora Courier ─────────────────────────────────────────────────────────────

/// Passenger-facing parcel card — manifest summary plus the confirmation
/// codes the sender/receiver hand to the courier. Codes come from the
/// server projection only; nothing is generated client-side.
class _CourierParcelCard extends StatelessWidget {
  const _CourierParcelCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final parcel = ride.parcel;
    final otps = ride.otpCodes;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parcel',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          if (parcel != null) ...[
            Text(
              '${parcel['description'] ?? 'Parcel'} — '
              '${(parcel['size'] ?? '').toString().toLowerCase()} · '
              '${parcel['weightKg'] ?? '?'} kg × ${parcel['quantity'] ?? 1}',
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            ),
            Text(
              '${parcel['senderName'] ?? 'Sender'} → '
              '${parcel['receiverName'] ?? 'Receiver'}',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          if (ride.pickupPhotoUrl != null) ...[
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Pickup condition photo recorded by courier.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          if (otps != null) ...[
            const SizedBox(height: OraSpacing.md),
            _OtpCodeRow(
              label: 'Pickup code',
              code: otps['pickup']?.toString(),
              used: otps['pickupUsedAt'] != null,
              hint: 'Share with the courier only when handing over the parcel.',
            ),
            _OtpCodeRow(
              label: 'Delivery code',
              code: otps['delivery']?.toString(),
              used: otps['deliveryUsedAt'] != null,
              hint: 'Receiver shares this with the courier on delivery.',
            ),
            if (otps['return'] != null || ride.state == 'RETURNING')
              _OtpCodeRow(
                label: 'Return code',
                code: otps['return']?.toString(),
                used: otps['returnUsedAt'] != null,
                hint: 'Share only when taking the parcel back.',
              ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Each code works once and expires automatically.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _OtpCodeRow extends StatelessWidget {
  const _OtpCodeRow({
    required this.label,
    required this.code,
    required this.used,
    this.hint,
  });

  final String label;
  final String? code;
  final bool used;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    if (code == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: OraSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: OraTypography.body(OraColors.textSecondary),
              ),
              const Spacer(),
              Text(
                used ? 'used' : code!,
                style: used
                    ? OraTypography.caption(OraColors.textMuted)
                    : OraTypography.headline(OraColors.primary),
              ),
            ],
          ),
          if (hint != null && !used)
            Text(
              hint!,
              style: OraTypography.caption(OraColors.textMuted),
            ),
        ],
      ),
    );
  }
}

// ── Ora Courier v2 — code-free delivery progress ─────────────────────────────

/// Passenger-facing multi-stop progress: ordered checklist, pending shop
/// quotes for approval, the server cash breakdown, acknowledgement, and
/// dispute reporting. Driver-side stop actions live on the driver screens.
class _DeliveryProgressCard extends ConsumerWidget {
  const _DeliveryProgressCard({required this.rideId, required this.ride});

  final String rideId;
  final Ride ride;

  static const _disputeCategories = <String, String>{
    'NOT_DELIVERED': 'Items were not delivered',
    'PAYMENT_REFUSED': 'Payment disagreement',
    'ITEM_MISMATCH': 'Wrong or missing items',
    'DAMAGED': 'Items arrived damaged',
    'OVERCHARGE': 'Charged more than agreed',
    'DRIVER_BEHAVIOR': 'Driver conduct',
    'OTHER': 'Something else',
  };

  IconData _iconFor(RideStop s) => switch (s.type) {
        'SHOP' => Icons.storefront_outlined,
        'DROPOFF' => Icons.flag_outlined,
        _ => Icons.inventory_2_outlined,
      };

  String _statusLabel(RideStop s) => switch (s.status) {
        'ARRIVED' => 'Driver at stop',
        'WAITING_APPROVAL' => 'Waiting on you',
        'DONE' => 'Done',
        'FAILED' => 'Failed',
        'SKIPPED' => 'Skipped',
        _ => 'Pending',
      };

  Future<void> _openDisputeSheet(BuildContext context, WidgetRef ref) async {
    final vm = ref.read(activeRideViewModelProvider(rideId).notifier);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(OraRadius.xxl)),
      ),
      builder: (_) => _DisputeSheet(onSubmit: vm.reportIssue),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(activeRideViewModelProvider(rideId).notifier);
    final isActing = ref.watch(
      activeRideViewModelProvider(rideId).select((s) => s.isActing),
    );
    final stops = ride.stops ?? const <RideStop>[];
    final shopping = ride.shopping;
    final settlement = ride.settlement;
    final currency = settlement?['currency'] as String? ?? 'PKR';
    String fmt(Object? minor) => minor is int
        ? formatOfferAmountMinor(minor, currency)
        : '—';
    final concluded = ride.state == 'RIDE_COMPLETED' ||
        ride.state == 'RETURNED' ||
        ride.state == 'RIDE_CLOSED';
    final acked = ride.evidence?['customerAckAt'] != null ||
        settlement?['customerAckAt'] != null;
    final pendingQuote = stops
        .where((s) => s.status == 'WAITING_APPROVAL' && s.quote != null)
        .firstOrNull;

    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ride.isBuyDeliver ? 'Delivery stops' : 'Parcel stops',
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
                          : OraColors.textMuted,
                ),
                const SizedBox(width: OraSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label ?? s.location.address ?? 'Stop ${s.seq + 1}',
                        style: OraTypography.body(OraColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.failureReason != null)
                        Text(
                          'Failed: ${s.failureReason}',
                          style: OraTypography.caption(OraColors.danger),
                        ),
                      if (s.items != null && s.items!.isNotEmpty)
                        Text(
                          s.items!
                              .map((i) =>
                                  '${i['qty'] ?? 1}× ${i['name'] ?? 'item'}')
                              .join(', '),
                          style: OraTypography.caption(OraColors.textMuted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Text(
                  _statusLabel(s),
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
          // buy_deliver — pending itemized quote needs the customer's call.
          if (pendingQuote != null) ...[
            const Divider(height: OraSpacing.lg),
            Text(
              'Approve this purchase?',
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xs),
            for (final item
                in (pendingQuote.quote!['items'] as List? ?? const [])) ...[
              if (item is Map)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${item['qty'] ?? 1}× ${item['name'] ?? 'item'}',
                        style:
                            OraTypography.body(OraColors.textSecondary),
                      ),
                    ),
                    Text(
                      fmt(item['priceMinor']),
                      style: OraTypography.body(OraColors.textPrimary),
                    ),
                  ],
                ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
                Text(
                  fmt(pendingQuote.quote!['totalMinor']),
                  style:
                      OraTypography.bodyEmphasis(OraColors.primary),
                ),
              ],
            ),
            const SizedBox(height: OraSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OraButton(
                    label: 'Approve',
                    isLoading: isActing,
                    onPressed: isActing
                        ? null
                        : () => vm.respondToStopQuote(
                              pendingQuote.seq,
                              approve: true,
                            ),
                  ),
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: OraButton(
                    label: 'Reject',
                    variant: OraButtonVariant.outline,
                    onPressed: isActing
                        ? null
                        : () => vm.respondToStopQuote(
                              pendingQuote.seq,
                              approve: false,
                            ),
                  ),
                ),
              ],
            ),
          ],
          // buy_deliver — shopping bookkeeping summary.
          if (shopping != null) ...[
            const Divider(height: OraSpacing.lg),
            _SettleRow(
              label: 'Shopping budget',
              value: fmt(shopping['totalBudgetMinor']),
            ),
            if ((shopping['approvedTotalMinor'] as int? ?? 0) > 0)
              _SettleRow(
                label: 'Approved so far',
                value: fmt(shopping['approvedTotalMinor']),
              ),
            if ((shopping['spentMinor'] as int? ?? 0) > 0)
              _SettleRow(
                label: 'Spent',
                value: fmt(shopping['spentMinor']),
              ),
          ],
          // Cash breakdown — server-computed at assignment.
          if (settlement != null) ...[
            const Divider(height: OraSpacing.lg),
            Text(
              'Pay the driver in cash',
              style: OraTypography.label(OraColors.textSecondary),
            ),
            const SizedBox(height: OraSpacing.xs),
            if (settlement['deliveryFareMinor'] != null) ...[
              // The agreed fare already includes serviceFee + stopFees;
              // decompose so the rows sum exactly to totalDueMinor.
              Builder(builder: (context) {
                final fare = settlement['deliveryFareMinor'] as int;
                final fee = settlement['serviceFeeMinor'] as int? ?? 0;
                final stops = settlement['stopFeesMinor'] as int? ?? 0;
                final base = fare - fee - stops;
                return Column(
                  children: [
                    _SettleRow(
                      label: 'Delivery fare',
                      value: fmt(base >= 0 ? base : fare),
                    ),
                    if (base >= 0 && fee > 0)
                      _SettleRow(label: 'Service fee', value: fmt(fee)),
                    if (base >= 0 && stops > 0)
                      _SettleRow(label: 'Extra stops', value: fmt(stops)),
                  ],
                );
              }),
            ],
            if ((settlement['shoppingTotalMinor'] as int? ?? 0) > 0)
              _SettleRow(
                label: 'Shopping',
                value: fmt(settlement['shoppingTotalMinor']),
              ),
            _SettleRow(
              label: 'Total due',
              value: fmt(settlement['totalDueMinor']),
              emphasize: true,
            ),
            if (settlement['driverReportedStatus'] != null)
              Padding(
                padding: const EdgeInsets.only(top: OraSpacing.xxs),
                child: Text(
                  'Driver reported: ${settlement['driverReportedStatus']}',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ),
            if (settlement['status'] == 'DISPUTED')
              Padding(
                padding: const EdgeInsets.only(top: OraSpacing.xxs),
                child: Text(
                  'This payment is under dispute.',
                  style: OraTypography.caption(OraColors.danger),
                ),
              ),
          ],
          if (ride.partialFulfillment == true)
            Padding(
              padding: const EdgeInsets.only(top: OraSpacing.xs),
              child: Text(
                'Some stops could not be completed — you are only charged '
                'the agreed fare plus approved purchases.',
                style: OraTypography.caption(OraColors.goldSoft),
              ),
            ),
          if (ride.disputeStatus == 'OPEN')
            Padding(
              padding: const EdgeInsets.only(top: OraSpacing.xs),
              child: Text(
                'A dispute is open on this delivery.',
                style: OraTypography.caption(OraColors.danger),
              ),
            ),
          if (concluded) ...[
            const SizedBox(height: OraSpacing.sm),
            if (!acked)
              OraButton(
                label: 'Got it — confirm receipt',
                variant: OraButtonVariant.outline,
                isLoading: isActing,
                onPressed: isActing ? null : vm.acknowledgeDelivery,
              )
            else
              Text(
                'Receipt acknowledged.',
                style: OraTypography.caption(OraColors.tealBright),
              ),
            if (ride.disputeStatus != 'OPEN') ...[
              const SizedBox(height: OraSpacing.xs),
              Center(
                child: TextButton(
                  onPressed: isActing
                      ? null
                      : () => _openDisputeSheet(context, ref),
                  child: Text(
                    'Report an issue',
                    style: OraTypography.label(OraColors.danger),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SettleRow extends StatelessWidget {
  const _SettleRow({
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

/// Category + free-text dispute — stays a bottom sheet so the passenger sees
/// the submission land on the same ride card.
class _DisputeSheet extends StatefulWidget {
  const _DisputeSheet({required this.onSubmit});

  final Future<void> Function({
    required String category,
    required String message,
  }) onSubmit;

  @override
  State<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<_DisputeSheet> {
  String _category = 'OTHER';
  final TextEditingController _message = TextEditingController();
  bool _submitting = false;

  static const _categories = _DeliveryProgressCard._disputeCategories;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _message.text.trim();
    if (message.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(category: _category, message: message);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            'Report an issue',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.sm),
          Wrap(
            spacing: OraSpacing.xs,
            runSpacing: OraSpacing.xs,
            children: [
              for (final entry in _categories.entries)
                OraChip(
                  label: entry.value,
                  selected: _category == entry.key,
                  onTap: () => setState(() => _category = entry.key),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            controller: _message,
            label: 'What happened?',
            hint: 'Describe the issue for support review',
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: OraSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OraButton(
              label: 'Submit report',
              isLoading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ),
        ],
      ),
    );
  }
}
