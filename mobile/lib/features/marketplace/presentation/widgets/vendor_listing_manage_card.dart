import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_bottom_sheet.dart';
import '../../../../app/theme/widgets/ora_button.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../app/di/providers.dart';
import '../../data/marketplace_models.dart';
import '../../data/marketplace_providers.dart';
import 'marketplace_status.dart';

/// Vendor-side listing row: thumbnail, title, status pill, subtitle, price —
/// plus a manage affordance (edit / pause-publish / delete) that calls the
/// marketplace API. Shared by all three vendor dashboards.
class VendorListingManageCard extends ConsumerWidget {
  const VendorListingManageCard({
    required this.listing,
    required this.icon,
    this.subtitle,
    this.onEdit,
    super.key,
  });

  final MarketplaceListing listing;
  final IconData icon;
  final String? subtitle;
  final void Function(MarketplaceListing listing)? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusLabel, statusBg, statusFg) = listingStatusStyle(
      listing.status,
    );
    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(OraRadius.sm),
            child: SizedBox(
              width: 72,
              height: 72,
              child: listing.photos.isNotEmpty
                  ? Image(
                      image: MarketplaceListing.photoProvider(
                        listing.photos.first,
                      ),
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: OraColors.surfaceElevated,
                      alignment: Alignment.center,
                      child: Icon(icon, color: OraColors.gold),
                    ),
            ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.bodyEmphasis(
                          OraColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OraSpacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(OraRadius.pill),
                      ),
                      child: Text(
                        statusLabel,
                        style: OraTypography.caption(
                          statusFg,
                        ).copyWith(fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.goldDeep),
                  ),
                Text(
                  listing.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
                const SizedBox(height: OraSpacing.xxs),
                Text(
                  listing.priceLabel,
                  style: OraTypography.label(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Manage listing',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showActions(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    await showOraBottomSheet<void>(
      context: context,
      child: _ManageActionsSheet(listing: listing, onEdit: onEdit),
    );
  }
}

class _ManageActionsSheet extends ConsumerStatefulWidget {
  const _ManageActionsSheet({required this.listing, this.onEdit});

  final MarketplaceListing listing;
  final void Function(MarketplaceListing listing)? onEdit;

  @override
  ConsumerState<_ManageActionsSheet> createState() =>
      _ManageActionsSheetState();
}

class _ManageActionsSheetState extends ConsumerState<_ManageActionsSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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
    final listing = widget.listing;
    final mutations = ref.read(listingMutationsProvider);
    final isPublished = listing.status == 'published';
    final isPaused = listing.status == 'paused';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OraSectionHeader(
          title: listing.title,
          description: 'Manage this listing — changes apply immediately.',
        ),
        const SizedBox(height: OraSpacing.md),
        if (widget.onEdit != null)
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit listing'),
            onTap: _busy
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onEdit!(listing);
                  },
          ),
        ListTile(
          leading: Icon(
            isPublished
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
          ),
          title: Text(
            isPublished
                ? 'Pause (hide from customers)'
                : isPaused
                ? 'Publish again'
                : 'Publish',
          ),
          onTap: _busy
              ? null
              : () => _run(
                  () => mutations.update(listing, {
                    'status': isPublished ? 'paused' : 'published',
                  }),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: OraColors.danger),
          title: const Text(
            'Delete listing',
            style: TextStyle(color: OraColors.danger),
          ),
          onTap: _busy ? null : () => _run(() => mutations.delete(listing)),
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
