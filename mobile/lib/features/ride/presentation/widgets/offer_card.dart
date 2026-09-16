import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../domain/entities/ride.dart';
import '../offers/offer_display.dart';

/// Offer card — renders only server-backed fields (no fake ETA/vehicle/rating).
class OfferCard extends StatelessWidget {
  const OfferCard({
    required this.offer,
    required this.onSelect,
    super.key,
    this.isSelecting = false,
    this.enabled = true,
  });

  final RideOffer offer;
  final VoidCallback? onSelect;
  final bool isSelecting;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selectable = enabled && isOfferSelectable(offer) && !isSelecting;
    final amount = formatOfferAmountMinor(offer.amountMinor, offer.currency);
    final status = offer.status.toUpperCase();

    return Semantics(
      button: selectable,
      label: '${offerDriverLabel(offer)}, $amount, $status',
      child: AnimatedScale(
        scale: isSelecting ? 0.98 : 1,
        duration: OraMotion.select,
        child: OraCard(
          selected: isSelecting,
          onTap: null,
          padding: const EdgeInsets.all(OraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: OraColors.primaryMuted,
                      borderRadius: BorderRadius.circular(OraRadius.sm),
                    ),
                    child: const Icon(
                      Icons.local_offer_outlined,
                      color: OraColors.primary,
                    ),
                  ),
                  const SizedBox(width: OraSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offerDriverLabel(offer),
                          style: OraTypography.bodyEmphasis(
                            OraColors.textPrimary,
                          ),
                        ),
                        Text(
                          _subtitle(offer),
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    amount,
                    style: OraTypography.title(OraColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.sm),
              Row(
                children: [
                  OraChip(
                    label: status,
                    selected: status == 'PENDING',
                    variant: OraChipVariant.status,
                  ),
                  const Spacer(),
                  if (isSelecting)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (selectable)
                    TextButton(
                      onPressed: onSelect,
                      child: Text(
                        'Select',
                        style: OraTypography.label(OraColors.primary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(RideOffer offer) {
    final parts = <String>[];
    final type = offer.type.trim();
    if (type.isNotEmpty) parts.add(type);
    final expires = offer.expiresAt.trim();
    if (expires.isNotEmpty) {
      parts.add('Expires ${_shortIso(expires)}');
    }
    if (parts.isEmpty) {
      return 'Live offer from Ora drivers';
    }
    return parts.join(' · ');
  }

  String _shortIso(String iso) {
    // Keep user-facing; avoid dumping full internal timestamps when long.
    if (iso.length >= 16) return iso.substring(11, 16);
    return iso;
  }
}
