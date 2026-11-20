import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/ride.dart';
import '../history/ride_history_display.dart';
import '../ratings/rating_display.dart';
import '../view_models/ride_history_detail_view_model.dart';

/// Terminal ride detail — GET /rides/:id once; redirects if still active.
class RideHistoryDetailView extends ConsumerStatefulWidget {
  const RideHistoryDetailView({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<RideHistoryDetailView> createState() =>
      _RideHistoryDetailViewState();
}

class _RideHistoryDetailViewState
    extends ConsumerState<RideHistoryDetailView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(rideHistoryDetailViewModelProvider(widget.rideId).notifier)
          .load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final state = ref.watch(rideHistoryDetailViewModelProvider(rideId));
    final vm = ref.read(rideHistoryDetailViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    ref.listen(rideHistoryDetailViewModelProvider(rideId), (prev, next) {
      if (!mounted) return;
      if (prev?.phase == next.phase) return;
      if (next.phase == RideHistoryDetailPhase.redirectOffers) {
        context.go(AppRoutes.offersInboxPath(rideId));
      } else if (next.phase == RideHistoryDetailPhase.redirectActive) {
        context.go(AppRoutes.activeRidePath(rideId));
      }
    });

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Ride details',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: switch (state.phase) {
          RideHistoryDetailPhase.loading ||
          RideHistoryDetailPhase.redirectOffers ||
          RideHistoryDetailPhase.redirectActive =>
            const Center(
              child: OraLoadingIndicator(message: 'Loading ride…'),
            ),
          RideHistoryDetailPhase.fatalError => OraErrorState(
              title: 'Ride unavailable',
              message: state.errorMessage ?? 'Something went wrong.',
              onRetry: vm.retry,
            ),
          RideHistoryDetailPhase.ready => _DetailBody(
              ride: state.ride!,
              padding: padding,
            ),
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.ride, required this.padding});

  final Ride ride;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final fare = formatMinorFare(ride.agreedFareMinor, ride.agreedFareCurrency);

    return SingleChildScrollView(
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
                  label: ride.state,
                  selected: false,
                  variant: OraChipVariant.status,
                ),
                const SizedBox(height: OraSpacing.sm),
                Text(
                  historyRideTitle(ride.state),
                  style: OraTypography.headline(OraColors.textPrimary),
                ),
                const SizedBox(height: OraSpacing.xs),
                Text(
                  'Server state only. Maps and payments are not shown here.',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ),
          ),
          if (isPassengerRatingSoftEligible(ride.state)) ...[
            const SizedBox(height: OraSpacing.md),
            OraButton(
              label: 'Rate ride',
              onPressed: () =>
                  context.push(AppRoutes.rideRatingPath(ride.rideId)),
            ),
          ],
          const SizedBox(height: OraSpacing.md),
          OraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trip', style: OraTypography.label(OraColors.textSecondary)),
                const SizedBox(height: OraSpacing.xs),
                _Line(
                  label: 'Pickup',
                  value: ride.pickup.address ??
                      '${ride.pickup.lat}, ${ride.pickup.lng}',
                ),
                _Line(
                  label: 'Destination',
                  value: ride.destination.address ??
                      '${ride.destination.lat}, ${ride.destination.lng}',
                ),
                _Line(label: 'Category', value: ride.category),
                _Line(
                  label: 'Service',
                  value: historyServiceTypeLabel(ride.serviceType),
                ),
                if (ride.paymentMethod.isNotEmpty)
                  _Line(label: 'Payment method', value: ride.paymentMethod),
                if (fare != null) _Line(label: 'Agreed fare', value: fare),
                if (ride.cancelledBy != null &&
                    ride.cancelledBy!.isNotEmpty)
                  _Line(label: 'Cancelled by', value: ride.cancelledBy!),
                if (ride.cancellationReason != null &&
                    ride.cancellationReason!.trim().isNotEmpty)
                  _Line(
                    label: 'Reason',
                    value: ride.cancellationReason!.trim(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: OraSpacing.md),
          OraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Timestamps',
                  style: OraTypography.label(OraColors.textSecondary),
                ),
                const SizedBox(height: OraSpacing.xs),
                for (final entry in _timestamps(ride))
                  _Line(label: entry.$1, value: entry.$2),
              ],
            ),
          ),
          const SizedBox(height: OraSpacing.md),
          Text(
            'Ride ID ${ride.rideId}',
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }

  List<(String, String)> _timestamps(Ride ride) {
    final out = <(String, String)>[];
    void add(String label, String? iso) {
      final formatted = formatHistoryTimestamp(iso);
      if (formatted != null) out.add((label, formatted));
    }

    add('Created', ride.createdAt);
    add('Updated', ride.updatedAt);
    add('Assigned', ride.assignedAt);
    add('Arrived', ride.arrivedAt);
    add('Started', ride.startedAt);
    add('Completed', ride.completedAt);
    add('Closed', ride.closedAt);
    return out;
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: OraTypography.body(OraColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
