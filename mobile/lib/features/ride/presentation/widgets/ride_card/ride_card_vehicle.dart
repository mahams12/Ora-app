import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';

/// Vehicle strip — omitted entirely when no real vehicle fields exist.
class RideCardVehicleRow extends StatelessWidget {
  const RideCardVehicleRow({
    required this.vehicle,
    super.key,
  });

  final RideCardVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    if (!vehicle.hasAnyField) return const SizedBox.shrink();

    final parts = <String>[
      if (vehicle.makeModel != null && vehicle.makeModel!.trim().isNotEmpty)
        vehicle.makeModel!.trim(),
      if (vehicle.color != null && vehicle.color!.trim().isNotEmpty)
        vehicle.color!.trim(),
      if (vehicle.registration != null &&
          vehicle.registration!.trim().isNotEmpty)
        vehicle.registration!.trim(),
    ];

    final imageUrl = vehicle.imageUrl?.trim();

    return Container(
      padding: const EdgeInsets.all(OraSpacing.sm),
      decoration: BoxDecoration(
        color: OraColors.navy.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(OraRadius.sm),
        border: Border.all(color: OraColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.xs),
              child: Image.network(
                imageUrl,
                width: 48,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: OraSpacing.sm),
          ] else ...[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: OraColors.infoMuted,
                borderRadius: BorderRadius.circular(OraRadius.xs),
              ),
              child: const Icon(
                Icons.directions_car_filled_outlined,
                size: 18,
                color: OraColors.info,
              ),
            ),
            const SizedBox(width: OraSpacing.sm),
          ],
          Expanded(
            child: Text(
              parts.join(' · '),
              style: OraTypography.caption(OraColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
