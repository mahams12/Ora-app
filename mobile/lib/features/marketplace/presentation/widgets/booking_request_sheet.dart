import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_bottom_sheet.dart';
import '../../../../app/theme/widgets/ora_button.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../data/marketplace_models.dart';
import '../../data/marketplace_providers.dart';

/// Customer request composer for service + rental listings. Logistics uses
/// its dedicated QuoteRequestForm — this sheet covers the two verticals
/// that book directly against a listing.
///
/// - service → preferred date/time + address + note
/// - rental  → check-in/check-out + guests + note (drives the backend's
///   confirmed-booking overlap guard)
Future<void> showBookingRequestSheet(
  BuildContext context,
  MarketplaceListing listing,
) {
  return showOraBottomSheet<void>(
    context: context,
    child: BookingRequestSheet(listing: listing),
  );
}

class BookingRequestSheet extends ConsumerStatefulWidget {
  const BookingRequestSheet({required this.listing, super.key});

  final MarketplaceListing listing;

  @override
  ConsumerState<BookingRequestSheet> createState() =>
      _BookingRequestSheetState();
}

class _BookingRequestSheetState extends ConsumerState<BookingRequestSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _guestsController = TextEditingController();
  final _messageController = TextEditingController();
  DateTime? _date;
  DateTime? _checkIn;
  DateTime? _checkOut;
  bool _busy = false;
  String? _error;

  bool get _isRental => widget.listing.type == 'rental';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(sessionUserProfileProvider);
    _nameController.text = profile?.displayName ?? '';
    _phoneController.text = profile?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _guestsController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pick(void Function(DateTime) assign) async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (value != null) setState(() => assign(value));
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_busy) return;
    final request = <String, dynamic>{
      'contactName': _nameController.text.trim(),
      'contactPhone': _phoneController.text.trim(),
    };
    final details = <String, dynamic>{};
    if (_isRental) {
      if (_checkIn == null || _checkOut == null) {
        setState(() => _error = 'Pick your check-in and check-out dates.');
        return;
      }
      if (!_checkOut!.isAfter(_checkIn!)) {
        setState(() => _error = 'Check-out must be after check-in.');
        return;
      }
      details['checkIn'] = _fmt(_checkIn!);
      details['checkOut'] = _fmt(_checkOut!);
      if (_guestsController.text.trim().isNotEmpty) {
        details['guests'] = _guestsController.text.trim();
      }
    } else {
      if (_date == null) {
        setState(() => _error = 'Pick a preferred date.');
        return;
      }
      details['date'] = _fmt(_date!);
      if (_addressController.text.trim().isNotEmpty) {
        details['address'] = _addressController.text.trim();
      }
    }
    if (_messageController.text.trim().isNotEmpty) {
      request['message'] = _messageController.text.trim();
    }
    if (details.isNotEmpty) request['details'] = details;
    if (_nameController.text.trim().length < 2 ||
        _phoneController.text.trim().length < 5) {
      setState(() => _error = 'Enter your contact name and phone.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingMutationsProvider)
          .createBooking(listingId: widget.listing.listingId, request: request);
      if (!mounted) return;
      Navigator.of(context).pop();
      await showOraBottomSheet<void>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OraSectionHeader(
              title: 'Request sent',
              description:
                  'The vendor will review your request. Track it under '
                  'My bookings — you will see their quote or answer there.',
            ),
            const SizedBox(height: OraSpacing.lg),
            OraButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
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
    final listing = widget.listing;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OraSectionHeader(
              title: _isRental ? 'Request to book' : 'Request service',
              description:
                  '${listing.title} · ${listing.priceLabel} · ${listing.location}',
            ),
            const SizedBox(height: OraSpacing.md),
            if (_isRental) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _pick((d) => _checkIn = d),
                      icon: const Icon(Icons.login_rounded),
                      label: Text(
                        _checkIn == null ? 'Check-in' : _fmt(_checkIn!),
                      ),
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _pick((d) => _checkOut = d),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(
                        _checkOut == null ? 'Check-out' : _fmt(_checkOut!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.sm),
              TextField(
                controller: _guestsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Guests'),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick((d) => _date = d),
                icon: const Icon(Icons.calendar_today),
                label: Text(_date == null ? 'Preferred date' : _fmt(_date!)),
              ),
              const SizedBox(height: OraSpacing.sm),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Service address'),
              ),
            ],
            const SizedBox(height: OraSpacing.sm),
            TextField(
              controller: _messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Message to the vendor (optional)',
              ),
            ),
            const SizedBox(height: OraSpacing.sm),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Contact name'),
            ),
            const SizedBox(height: OraSpacing.sm),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Contact phone'),
            ),
            if (_error != null) ...[
              const SizedBox(height: OraSpacing.sm),
              Text(_error!, style: OraTypography.caption(OraColors.danger)),
            ],
            const SizedBox(height: OraSpacing.md),
            OraButton(
              label: _busy ? 'Sending…' : 'Send request',
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: OraSpacing.sm),
          ],
        ),
      ),
    );
  }
}
