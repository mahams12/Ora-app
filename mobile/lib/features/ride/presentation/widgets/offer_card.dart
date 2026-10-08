import 'package:flutter/material.dart';

import '../../domain/entities/ride.dart';
import 'ride_card/ride_card.dart';

/// Offer card — shared RideCard system; server-backed fields only.
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
    return RideCard(
      model: RideCardAdapters.fromOffer(
        offer,
        onSelect: onSelect,
        isSelecting: isSelecting,
        enabled: enabled,
      ),
    );
  }
}
