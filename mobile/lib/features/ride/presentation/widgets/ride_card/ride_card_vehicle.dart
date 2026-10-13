import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_assets.dart';
import 'ride_card_model.dart';

/// Vehicle strip — always keeps epic slots (car + text + plate pill).
///
/// Missing make/color/plate → blank text / empty plate outline.
/// Never invents vehicle identity.
class RideCardVehicleRow extends StatelessWidget {
  const RideCardVehicleRow({
    super.key,
    this.vehicle,
    this.fallbackAssetPath,
    this.showPlateSlot = true,
  });

  final RideCardVehicle? vehicle;
  final String? fallbackAssetPath;
  final bool showPlateSlot;

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    final titleParts = <String>[
      if (v?.makeModel != null && v!.makeModel!.trim().isNotEmpty)
        v.makeModel!.trim(),
      if (v?.color != null && v!.color!.trim().isNotEmpty) v.color!.trim(),
    ];
    final plate = v?.registration?.trim();
    final imageUrl = v?.imageUrl?.trim();

    return Row(
      children: [
        if (imageUrl != null && imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(OraRadius.xs),
            child: Image.network(
              imageUrl,
              width: 56,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _AssetOrIcon(fallbackAssetPath),
            ),
          )
        else
          _AssetOrIcon(fallbackAssetPath),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: SizedBox(
            height: 18,
            child: titleParts.isEmpty
                ? const SizedBox.shrink()
                : Text(
                    titleParts.join(' · '),
                    style: OraTypography.caption(OraColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ),
        if (showPlateSlot) ...[
          const SizedBox(width: OraSpacing.sm),
          Container(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 28),
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.sm,
              vertical: 4,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF151C2E),
              borderRadius: BorderRadius.circular(OraRadius.xs),
              border: Border.all(color: OraColors.border),
            ),
            child: Text(
              (plate == null || plate.isEmpty) ? '' : plate,
              style: OraTypography.label(OraColors.textPrimary).copyWith(
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AssetOrIcon extends StatelessWidget {
  const _AssetOrIcon(this.assetPath);

  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    if (assetPath != null) {
      return RideCardAssetImage(
        assetPath: assetPath!,
        width: 56,
        height: 36,
      );
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OraColors.infoMuted,
        borderRadius: BorderRadius.circular(OraRadius.xs),
      ),
      child: Icon(
        Icons.directions_car_filled_outlined,
        size: 18,
        color: OraColors.info.withValues(alpha: 0.7),
      ),
    );
  }
}
