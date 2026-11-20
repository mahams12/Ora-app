import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';

/// Decorative warm map artwork extracted from the Ora design mockups —
/// pickup/drop-off pins, orange route and car are baked into the art.
const String _kMapArt = 'assets/driver_tiles/map_banner.png';

/// Compact map thumbnail — decorative artwork only (no map engine / no watermark).
///
/// Matches the warm Ora route-preview look: cream terrain, orange route,
/// green pickup pin, red drop pin and a small white car.
class RideCardMapThumb extends StatelessWidget {
  const RideCardMapThumb({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.width = 72,
    this.height = 96,
    this.showCar = false,
    this.carAssetPath,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final double width;
  final double height;
  final bool showCar;
  final String? carAssetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.md),
        border: Border.all(color: const Color(0x40FF8A3D), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: OraColors.goldSharp.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _kMapArt,
        width: width,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Wide banner map used on driver request sheets and ride cards.
class RideCardMapBanner extends StatelessWidget {
  const RideCardMapBanner({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.height = 132,
    this.carAssetPath,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final double height;
  final String? carAssetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.md),
        border: Border.all(color: const Color(0x40FF8A3D)),
        boxShadow: [
          BoxShadow(
            color: OraColors.goldSharp.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        _kMapArt,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
