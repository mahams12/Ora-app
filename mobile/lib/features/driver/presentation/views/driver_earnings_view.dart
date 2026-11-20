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
import '../../domain/driver_earnings_summary.dart';
import '../view_models/driver_earnings_view_model.dart';

/// Driver "My Earnings" — Today / Week / Month tabs over the verified
/// trip-fare summary, breakdown card, withdraw CTA and a real earnings
/// trend chart computed from completed rides. Payout/commission are not
/// recorded by the backend yet; that is labelled, not faked.
class DriverEarningsView extends ConsumerStatefulWidget {
  const DriverEarningsView({
    super.key,
    this.active = false,
    this.ridePathFor = AppRoutes.driverRidePath,
    this.tripsLabel = 'Total Trips',
    this.tripsIcon = Icons.directions_car_filled_rounded,
    this.emptyTitle = 'No completed trips yet',
    this.emptyMessage =
        'Trips you complete will appear here with their agreed '
        'fare. Only finished rides count toward totals.',
  });

  final bool active;

  /// Copy overrides — logistics partners show delivery wording and route to
  /// their own shell-scoped detail page.
  final String Function(String rideId) ridePathFor;
  final String tripsLabel;
  final IconData tripsIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  ConsumerState<DriverEarningsView> createState() => _DriverEarningsViewState();
}

enum _EarningsTab { today, week, month }

class _DriverEarningsViewState extends ConsumerState<DriverEarningsView> {
  bool _initialLoadRequested = false;
  _EarningsTab _tab = _EarningsTab.month;

  @override
  void initState() {
    super.initState();
    _maybeLoadInitial();
  }

  @override
  void didUpdateWidget(DriverEarningsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _maybeLoadInitial();
    }
  }

  void _maybeLoadInitial() {
    if (!widget.active || _initialLoadRequested) return;
    _initialLoadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(driverEarningsViewModelProvider.notifier).loadInitial();
    });
  }

  static const _periodLabels = {
    _EarningsTab.today: 'Today',
    _EarningsTab.week: 'This Week',
    _EarningsTab.month: 'This Month',
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_initialLoadRequested) {
      return const SizedBox.expand();
    }
    final state = ref.watch(driverEarningsViewModelProvider);
    final padding = Responsive.horizontalPadding(context);

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: () =>
          ref.read(driverEarningsViewModelProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        children: [
          if (state.phase == DriverEarningsPhase.initialLoading)
            const Padding(
              padding: EdgeInsets.only(top: OraSpacing.xxl),
              child: Center(
                child: OraLoadingIndicator(message: 'Loading earnings…'),
              ),
            )
          else if (state.phase == DriverEarningsPhase.fatalError)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.14,
              ),
              child: OraErrorState(
                title: 'Couldn’t load earnings',
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () =>
                    ref.read(driverEarningsViewModelProvider.notifier).retry(),
              ),
            )
          else ...[
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: OraSpacing.sm),
                child: Text(
                  state.errorMessage!,
                  style: OraTypography.caption(OraColors.dangerForeground),
                ),
              ),
            _TotalEarningsCard(
              state: state,
              tab: _tab,
              periodLabels: _periodLabels,
              onSelectPeriod: (t) => setState(() => _tab = t),
            ),
            const SizedBox(height: OraSpacing.md),
            _EarningsStatRow(
              state: state,
              tripsLabel: widget.tripsLabel,
              tripsIcon: widget.tripsIcon,
            ),
            const SizedBox(height: OraSpacing.md),
            _EarningsTrendCard(rides: state.rides),
            const SizedBox(height: OraSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent Earnings',
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                ),
                if (state.hasMore)
                  GestureDetector(
                    onTap: () => ref
                        .read(driverEarningsViewModelProvider.notifier)
                        .loadMore(),
                    child: Text(
                      'See All',
                      style: OraTypography.label(
                        OraColors.goldSharp,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: OraSpacing.sm),
            if (state.phase == DriverEarningsPhase.empty)
              OraEmptyState(
                title: widget.emptyTitle,
                message: widget.emptyMessage,
                icon: Icons.receipt_long_outlined,
              )
            else ...[
              for (final ride in state.rides)
                Padding(
                  padding: const EdgeInsets.only(bottom: OraSpacing.sm),
                  child: _RecentEarningTile(
                    ride: ride,
                    onTap: () =>
                        context.push(widget.ridePathFor(ride.rideId)),
                  ),
                ),
              _PaginationFooter(
                state: state,
                onLoadMore: () => ref
                    .read(driverEarningsViewModelProvider.notifier)
                    .loadMore(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

DriverEarningsPeriod? _periodFor(
  DriverEarningsUiState state,
  _EarningsTab tab,
) {
  final summary = state.summary;
  if (summary == null) return null;
  return switch (tab) {
    _EarningsTab.today => summary.today,
    _EarningsTab.week => summary.last7Days,
    _EarningsTab.month => summary.allTime,
  };
}

/// Big orange gradient "Total Earnings" hero — 3D wallet artwork extracted
/// from the reference design, real period total and the period dropdown.
class _TotalEarningsCard extends StatelessWidget {
  const _TotalEarningsCard({
    required this.state,
    required this.tab,
    required this.periodLabels,
    required this.onSelectPeriod,
  });

  final DriverEarningsUiState state;
  final _EarningsTab tab;
  final Map<_EarningsTab, String> periodLabels;
  final ValueChanged<_EarningsTab> onSelectPeriod;

  @override
  Widget build(BuildContext context) {
    final period = _periodFor(state, tab);
    final total = period == null
        ? '—'
        : formatMinorFare(period.faresMinor, period.currency) ?? '—';

    return OraFloaty(
      amplitude: 7,
      period: const Duration(seconds: 4),
      child: Container(
        width: double.infinity,
        height: 132,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
          ),
          borderRadius: BorderRadius.circular(OraRadius.card),
          border: Border.all(color: const Color(0x59FFFFFF), width: 1.2),
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
              right: -8,
              top: 0,
              bottom: 0,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white],
                  stops: [0.0, 0.4],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: Image.asset(
                  'assets/driver_tiles/earnings_wallet.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(OraSpacing.md),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Text(
                    'Total Earnings',
                    style: OraTypography.caption(
                      const Color(0xE6FFFFFF),
                    ).copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    total,
                    style: OraTypography.display(
                      Colors.white,
                    ).copyWith(fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  PopupMenuButton<_EarningsTab>(
                    onSelected: onSelectPeriod,
                    offset: const Offset(0, 28),
                    itemBuilder: (context) => [
                      for (final t in _EarningsTab.values)
                        PopupMenuItem(value: t, child: Text(periodLabels[t]!)),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OraSpacing.xs,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(OraRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            periodLabels[tab]!,
                            style: OraTypography.caption(
                              Colors.white,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
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

/// Three mockup stat cards — completed trips, real on-trip driving time
/// (startedAt→completedAt), and straight-line trip distance. A stat shows
/// '—' when the data does not exist rather than inventing a figure.
class _EarningsStatRow extends StatelessWidget {
  const _EarningsStatRow({
    required this.state,
    required this.tripsLabel,
    required this.tripsIcon,
  });

  final DriverEarningsUiState state;
  final String tripsLabel;
  final IconData tripsIcon;

  static String? _drivingTime(List<Ride> rides) {
    var minutes = 0;
    var counted = 0;
    for (final ride in rides) {
      if (!isDriverEarningsCompletedState(ride.state)) continue;
      final start = DateTime.tryParse(ride.startedAt ?? '');
      final end = DateTime.tryParse(ride.completedAt ?? '');
      if (start == null || end == null) continue;
      final diff = end.difference(start).inMinutes;
      if (diff <= 0) continue;
      minutes += diff;
      counted++;
    }
    if (counted == 0) return null;
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  static String? _totalDistance(List<Ride> rides) {
    var km = 0.0;
    var counted = 0;
    for (final ride in rides) {
      if (!isDriverEarningsCompletedState(ride.state)) continue;
      final d = _straightKm(ride.pickup, ride.destination);
      if (d <= 0) continue;
      km += d;
      counted++;
    }
    if (counted == 0) return null;
    return '${km.toStringAsFixed(0)} km';
  }

  static double _straightKm(LatLngPoint a, LatLngPoint b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  @override
  Widget build(BuildContext context) {
    final trips = state.summary?.completedRideCount ?? state.rides.length;
    final driving = _drivingTime(state.rides);
    final distance = _totalDistance(state.rides);

    return Row(
      children: [
        _StatCard(
          icon: tripsIcon,
          value: '$trips',
          label: tripsLabel,
        ),
        const SizedBox(width: OraSpacing.sm),
        _StatCard(
          icon: Icons.schedule_rounded,
          value: driving ?? '—',
          label: 'Driving Time',
        ),
        const SizedBox(width: OraSpacing.sm),
        _StatCard(
          icon: Icons.route_rounded,
          value: distance ?? '—',
          label: 'Total Distance',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OraCard(
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.xs,
          vertical: OraSpacing.sm,
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: OraColors.goldSharp),
            const SizedBox(height: 4),
            Text(
              value,
              style: OraTypography.bodyEmphasis(
                OraColors.textPrimary,
              ).copyWith(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OraTypography.caption(
                OraColors.textMuted,
              ).copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recent Earnings" row — car thumb, pickup → drop-off, completion time,
/// green fare and chevron, like the reference list.
class _RecentEarningTile extends StatelessWidget {
  const _RecentEarningTile({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  static String _when(String? iso) {
    final at = DateTime.tryParse(iso ?? '')?.toLocal();
    if (at == null) return '';
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        at.year == yesterday.year &&
        at.month == yesterday.month &&
        at.day == yesterday.day;
    final h24 = at.hour;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final time = '$h12:${at.minute.toString().padLeft(2, '0')} $ampm';
    if (sameDay) return 'Today, $time';
    if (isYesterday) return 'Yesterday, $time';
    return '${at.day}/${at.month}/${at.year}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final fare = formatMinorFare(
      ride.agreedFareMinor ?? ride.driverPayoutMinor,
      ride.agreedFareCurrency ?? ride.payoutCurrency,
    );

    return OraTapScale(
      child: OraCard(
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.sm,
          vertical: OraSpacing.xs,
        ),
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
                  ),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${rideCardLocationLabel(ride.pickup)} → '
                      '${rideCardLocationLabel(ride.destination)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.bodyEmphasis(
                        OraColors.textPrimary,
                      ).copyWith(fontSize: 13),
                    ),
                    Text(
                      _when(ride.completedAt),
                      style: OraTypography.caption(
                        OraColors.textMuted,
                      ).copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OraSpacing.xs),
              Text(
                fare ?? '—',
                style: OraTypography.bodyEmphasis(
                  OraColors.success,
                ).copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: OraColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EarningsTrendCard extends StatelessWidget {
  const _EarningsTrendCard({required this.rides});

  final List<Ride> rides;

  List<int> _dailyTotals() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final buckets = List<int>.filled(7, 0);
    for (final ride in rides) {
      if (!isDriverEarningsCompletedState(ride.state)) continue;
      final at = driverEarningsCompletionTime(ride);
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      final idx = day.difference(start).inDays;
      if (idx < 0 || idx > 6) continue;
      buckets[idx] += ride.driverPayoutMinor ?? ride.agreedFareMinor ?? 0;
    }
    return buckets;
  }

  List<String> _dayLabels() {
    final now = DateTime.now();
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return [
      for (var i = 6; i >= 0; i--)
        names[now.subtract(Duration(days: i)).weekday - 1],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final totals = _dailyTotals();
    final days = _dayLabels();
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Earnings Overview',
                  style: OraTypography.bodyEmphasis(
                    OraColors.textPrimary,
                  ).copyWith(fontFamily: OraTypography.displayFamily),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: OraSpacing.xs,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: OraColors.surface,
                  borderRadius: BorderRadius.circular(OraRadius.pill),
                  border: Border.all(color: OraColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'This Week',
                      style: OraTypography.caption(
                        OraColors.textPrimary,
                      ).copyWith(fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: OraColors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _TrendBarsPainter(totals, days),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendBarsPainter extends CustomPainter {
  const _TrendBarsPainter(this.totals, this.dayLabels);

  /// Minor-unit totals per day, oldest → newest (7 entries).
  final List<int> totals;
  final List<String> dayLabels;

  static String _labelFor(int minor) {
    if (minor <= 0) return '';
    final rupees = minor / 100;
    if (rupees >= 1000) {
      final k = rupees / 1000;
      return 'Rs ${k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return 'Rs ${rupees.toStringAsFixed(0)}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (totals.isEmpty) return;
    final maxValue = totals.fold<int>(0, (a, b) => a > b ? a : b);
    const gap = 8.0;
    const labelH = 14.0;
    const dayH = 14.0;
    final count = totals.length;
    final barWidth = (size.width - gap * (count - 1)) / count;
    final chartH = size.height - labelH - dayH;
    const minBar = 6.0;
    final maxIndex = totals.indexOf(maxValue);

    for (var i = 0; i < count; i++) {
      final left = i * (barWidth + gap);
      final cx = left + barWidth / 2;

      // Value label above the bar.
      final label = _labelFor(totals[i]);
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: OraColors.textSecondary,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, 0));
      }

      final fraction = maxValue <= 0 ? 0.0 : totals[i] / maxValue;
      final height = maxValue <= 0
          ? minBar
          : (minBar + fraction * (chartH - minBar));
      final top = labelH + chartH - height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, height),
        const Radius.circular(7),
      );
      final isMax = i == maxIndex && maxValue > 0;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isMax
              ? const [OraColors.goldSharp, Color(0xFFE05A00)]
              : const [Color(0xFFFFA14A), Color(0xFFF88733)],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33FFFFFF),
      );

      // Day label under the bar.
      if (i < dayLabels.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: dayLabels[i],
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: OraColors.textMuted,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, labelH + chartH + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_TrendBarsPainter oldDelegate) =>
      oldDelegate.totals != totals || oldDelegate.dayLabels != dayLabels;
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.state, required this.onLoadMore});

  final DriverEarningsUiState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.paginationError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
        child: Column(
          children: [
            Text(
              state.paginationError!,
              textAlign: TextAlign.center,
              style: OraTypography.caption(OraColors.dangerForeground),
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(
              label: 'Retry load more',
              variant: OraButtonVariant.outline,
              onPressed: onLoadMore,
            ),
          ],
        ),
      );
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: OraSpacing.lg),
        child: Center(child: OraLoadingIndicator()),
      );
    }
    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
        child: OraButton(
          label: 'Load more',
          variant: OraButtonVariant.outline,
          onPressed: state.canLoadMore ? onLoadMore : null,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
      child: Text(
        'End of history',
        textAlign: TextAlign.center,
        style: OraTypography.caption(OraColors.textMuted),
      ),
    );
  }
}
