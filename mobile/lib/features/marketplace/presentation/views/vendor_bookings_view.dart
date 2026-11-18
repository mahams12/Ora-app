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

/// Vendor booking inbox — requests on the vendor's own listings for one
/// vertical ('service' | 'rental' | 'cargo'). Route-gated by the same
/// per-role approval as the matching dashboard; every action additionally
/// re-verifies approval + ownership server-side.
class VendorBookingsView extends ConsumerWidget {
  const VendorBookingsView({required this.type, super.key});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(
      bookingsProvider(BookingsQuery(role: 'vendor', type: type)),
    );
    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      appBar: AppBar(title: const Text('Booking requests')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: bookings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorBody(
              message: ref
                  .read(failureMapperProvider)
                  .fromException(error)
                  .userMessage,
              onRetry: () => ref.invalidate(bookingsProvider),
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
                    const _EmptyInbox()
                  else
                    for (final booking in items) ...[
                      _VendorBookingCard(booking: booking),
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OraSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 40, color: OraColors.gold),
          const SizedBox(height: OraSpacing.sm),
          Text(
            'No requests yet',
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'Customer requests on your published listings appear here.',
            textAlign: TextAlign.center,
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: OraTypography.body(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.md),
          OraButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

/// One inbox row — summary line comes from the request's own fields so it
/// works for quote, rental-stay and service requests alike.
class _VendorBookingCard extends ConsumerWidget {
  const _VendorBookingCard({required this.booking});

  final MarketplaceBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Text(
            'From ${booking.customerName} · ${booking.requestString('contactPhone') ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.caption(OraColors.textSecondary),
          ),
          _requestSummary(booking),
          if (booking.quote != null) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Your quote: ${booking.quote!.label}',
              style: OraTypography.label(OraColors.goldDeep),
            ),
          ],
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Manage request',
            onPressed: () => showOraBottomSheet<void>(
              context: context,
              child: VendorBookingActionsSheet(booking: booking),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestSummary(MarketplaceBooking b) {
    final lines = <String>[];
    final d = b.requestDetails;
    for (final key in [
      'checkIn',
      'checkOut',
      'guests',
      'pickup',
      'destination',
      'date',
      'time',
      'address',
      'cargo',
    ]) {
      final v = d[key] ?? b.request[key];
      if (v is String && v.isNotEmpty) {
        lines.add('${_labelFor(key)}: $v');
      }
    }
    final message = b.requestString('message');
    if (message != null) lines.add('“$message”');
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: OraSpacing.xxs),
      child: Text(
        lines.join('  ·  '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: OraTypography.caption(OraColors.textMuted),
      ),
    );
  }

  String _labelFor(String key) => switch (key) {
    'checkIn' => 'Check-in',
    'checkOut' => 'Check-out',
    'guests' => 'Guests',
    'pickup' => 'Pickup',
    'destination' => 'Drop',
    'date' => 'Date',
    'time' => 'Time',
    'address' => 'Address',
    'cargo' => 'Cargo',
    _ => key,
  };
}

/// Vendor decision sheet — every action maps to a server-validated
/// transition; invalid moves surface the backend's conflict message.
class VendorBookingActionsSheet extends ConsumerStatefulWidget {
  const VendorBookingActionsSheet({required this.booking, super.key});

  final MarketplaceBooking booking;

  @override
  ConsumerState<VendorBookingActionsSheet> createState() =>
      _VendorBookingActionsSheetState();
}

class _VendorBookingActionsSheetState
    extends ConsumerState<VendorBookingActionsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _act(String action, {int? amount, String? note}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingMutationsProvider)
          .vendorAction(
            widget.booking.bookingId,
            action,
            amount: amount,
            note: note,
          );
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

  Future<void> _quoteDialog() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price (PKR)',
                prefixText: 'Rs ',
              ),
            ),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note for the customer (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final amount = int.tryParse(amountController.text.replaceAll(',', ''));
      await _act(
        'quote',
        amount: amount ?? 0,
        note: noteController.text.trim().isEmpty
            ? null
            : noteController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.booking.status;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OraSectionHeader(
          title: widget.booking.listingTitle,
          description:
              'Request from ${widget.booking.customerName} — currently '
              '${status.replaceAll('_', ' ')}.',
        ),
        const SizedBox(height: OraSpacing.md),
        if (status == 'requested' || status == 'quoted') ...[
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: Text(status == 'quoted' ? 'Revise quote' : 'Send a quote'),
            onTap: _busy ? null : _quoteDialog,
          ),
          if (status == 'requested')
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Accept booking'),
              onTap: _busy ? null : () => _act('accept'),
            ),
          ListTile(
            leading: const Icon(Icons.close_rounded),
            title: const Text('Decline request'),
            onTap: _busy ? null : () => _act('reject'),
          ),
        ],
        if (status == 'confirmed') ...[
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: const Text('Mark in progress'),
            onTap: _busy ? null : () => _act('start'),
          ),
          ListTile(
            leading: const Icon(Icons.done_all_rounded),
            title: const Text('Mark completed'),
            onTap: _busy ? null : () => _act('complete'),
          ),
          ListTile(
            leading: const Icon(Icons.cancel_outlined),
            title: const Text('Cancel booking'),
            onTap: _busy ? null : () => _act('cancel'),
          ),
        ],
        if (status == 'in_progress') ...[
          ListTile(
            leading: const Icon(Icons.done_all_rounded),
            title: const Text('Mark completed'),
            onTap: _busy ? null : () => _act('complete'),
          ),
          ListTile(
            leading: const Icon(Icons.cancel_outlined),
            title: const Text('Cancel booking'),
            onTap: _busy ? null : () => _act('cancel'),
          ),
        ],
        if (widget.booking.isTerminal)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: OraSpacing.sm),
            child: Text(
              'This booking is ${status.replaceAll('_', ' ')} — no further actions.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ),
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
