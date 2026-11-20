import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_bottom_sheet.dart';
import '../../../../app/theme/widgets/ora_button.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../core/utils/responsive.dart';
import '../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../data/marketplace_models.dart';
import '../../data/marketplace_providers.dart';
import '../widgets/marketplace_status.dart';

/// Customer "My bookings" — every request the signed-in user has made
/// across all three verticals, with quote-accept and cancel actions.
class MyBookingsView extends ConsumerWidget {
  const MyBookingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(
      bookingsProvider(const BookingsQuery(role: 'customer')),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      appBar: AppBar(title: const Text('My bookings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: bookings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ref
                        .read(failureMapperProvider)
                        .fromException(error)
                        .userMessage,
                    textAlign: TextAlign.center,
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
                  const SizedBox(height: OraSpacing.md),
                  OraButton(
                    label: 'Retry',
                    onPressed: () => ref.invalidate(bookingsProvider),
                  ),
                ],
              ),
            ),
            data: (items) => RefreshIndicator(
              color: OraColors.gold,
              onRefresh: () async => ref.invalidate(bookingsProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  OraSpacing.md,
                  Responsive.horizontalPadding(context),
                  OraSpacing.xl,
                ),
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: OraSpacing.xl,
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.event_busy_outlined,
                            size: 40,
                            color: OraColors.gold,
                          ),
                          const SizedBox(height: OraSpacing.sm),
                          Text(
                            'No bookings yet',
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: OraSpacing.xxs),
                          Text(
                            'Requests you send from Services, Rental and '
                            'Logistics listings appear here.',
                            textAlign: TextAlign.center,
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final booking in items) ...[
                      _CustomerBookingCard(booking: booking),
                      const SizedBox(height: OraSpacing.sm),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const OraModuleBottomBar(),
    );
  }
}

class _CustomerBookingCard extends ConsumerWidget {
  const _CustomerBookingCard({required this.booking});

  final MarketplaceBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeLabel = switch (booking.type) {
      'cargo' => 'Logistics',
      'rental' => 'Rental',
      _ => 'Service',
    };
    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.listingTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
              ),
              StatusPill(status: booking.status, booking: true),
            ],
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(typeLabel, style: OraTypography.caption(OraColors.goldDeep)),
          if (booking.quote != null) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Vendor quote: ${booking.quote!.label}'
              '${booking.quote!.note != null ? ' — ${booking.quote!.note}' : ''}',
              style: OraTypography.label(OraColors.textPrimary),
            ),
          ],
          if (!booking.isTerminal) ...[
            const SizedBox(height: OraSpacing.sm),
            OraButton(
              label: booking.status == 'quoted'
                  ? 'Review quote'
                  : 'Manage booking',
              onPressed: () => showOraBottomSheet<void>(
                context: context,
                child: CustomerBookingActionsSheet(booking: booking),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Customer decisions: accept the vendor's quote (→ confirmed) or cancel.
class CustomerBookingActionsSheet extends ConsumerStatefulWidget {
  const CustomerBookingActionsSheet({required this.booking, super.key});

  final MarketplaceBooking booking;

  @override
  ConsumerState<CustomerBookingActionsSheet> createState() =>
      _CustomerBookingActionsSheetState();
}

class _CustomerBookingActionsSheetState
    extends ConsumerState<CustomerBookingActionsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _act(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingMutationsProvider)
          .customerAction(widget.booking.bookingId, action);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ref
            .read(failureMapperProvider)
            .fromException(error)
            .userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OraSectionHeader(
          title: booking.listingTitle,
          description: booking.status == 'quoted'
              ? 'The vendor sent a quote of ${booking.quote!.label}'
                    '${booking.quote!.note != null ? ' — ${booking.quote!.note}' : ''}. '
                    'Accept it to confirm the booking.'
              : 'Your request is ${booking.status.replaceAll('_', ' ')}.',
        ),
        const SizedBox(height: OraSpacing.md),
        if (booking.status == 'quoted')
          OraButton(
            label: 'Accept quote — confirm booking',
            onPressed: _busy ? null : () => _act('accept'),
          ),
        if (booking.status != 'in_progress' && !booking.isTerminal) ...[
          if (booking.status == 'quoted') const SizedBox(height: OraSpacing.sm),
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: OraColors.danger),
            title: const Text(
              'Cancel booking',
              style: TextStyle(color: OraColors.danger),
            ),
            onTap: _busy ? null : () => _act('cancel'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: OraSpacing.sm),
          Text(_error!, style: OraTypography.caption(OraColors.danger)),
        ],
        if (_busy) ...[
          const SizedBox(height: OraSpacing.sm),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: OraSpacing.sm),
        OraButton(
          label: 'Close',
          variant: OraButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
