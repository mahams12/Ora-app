import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

/// Location surface header — not a live map (Maps SDK deferred past 4A).
class RideLocationPlaceholder extends StatelessWidget {
  const RideLocationPlaceholder({
    super.key,
    this.height = 168,
    this.onBack,
    this.pickupConfirmed = false,
    this.destinationConfirmed = false,
  });

  final double height;
  final VoidCallback? onBack;
  final bool pickupConfirmed;
  final bool destinationConfirmed;

  @override
  Widget build(BuildContext context) {
    final status = pickupConfirmed && destinationConfirmed
        ? 'Pickup & destination confirmed'
        : pickupConfirmed
            ? 'Pickup confirmed · destination needed'
            : destinationConfirmed
                ? 'Destination confirmed · pickup needed'
                : 'Confirm pickup & destination to continue';

    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OraColors.navy, OraColors.navyElevated, OraColors.surface],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 48,
              left: 0,
              right: 0,
              child: Container(height: 3, color: OraColors.border.withValues(alpha: 0.45)),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 110,
              child: Container(width: 3, color: OraColors.border.withValues(alpha: 0.35)),
            ),
            Positioned(
              top: 110,
              left: 0,
              right: 0,
              child: Container(height: 2, color: OraColors.border.withValues(alpha: 0.3)),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: OraSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      color: OraColors.primary.withValues(alpha: 0.85),
                      size: 28,
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Text(
                      'Map preview',
                      style: OraTypography.label(OraColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Interactive map pins open in a later build. '
                      'Search and GPS resolve your coordinates now.',
                      textAlign: TextAlign.center,
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            if (onBack != null)
              Positioned(
                top: OraSpacing.md,
                left: OraSpacing.md,
                child: Material(
                  color: OraColors.surfaceElevated.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    color: OraColors.textPrimary,
                  ),
                ),
              ),
            Positioned(
              left: OraSpacing.md,
              right: OraSpacing.md,
              bottom: OraSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: OraSpacing.sm,
                  vertical: OraSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: OraColors.surfaceElevated.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(OraRadius.pill),
                  border: Border.all(color: OraColors.border),
                ),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: OraTypography.caption(OraColors.goldSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
