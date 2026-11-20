import 'package:flutter/material.dart';

/// Bundled epic ride-card assets (user-provided PNGs).
///
/// Filenames match visual content after the Open Rides asset remap.
/// Prefer [RideCardAssetImage] so decode size matches display size.
class RideCardAssets {
  RideCardAssets._();

  static const carWhite = 'assets/branding/ride_card/car_white.png';
  static const carSilver = 'assets/branding/ride_card/car_silver.png';
  static const carBlack = 'assets/branding/ride_card/car_black.png';

  static const pinBlue = 'assets/branding/ride_card/icons/pin_blue.png';
  static const pinWhite = 'assets/branding/ride_card/icons/pin_white.png';
  static const clock = 'assets/branding/ride_card/icons/clock.png';
  static const route = 'assets/branding/ride_card/icons/route.png';
  static const phone = 'assets/branding/ride_card/icons/phone.png';
  static const steering = 'assets/branding/ride_card/icons/steering.png';
  static const parcel = 'assets/branding/ride_card/icons/parcel.png';
  static const avatarEmpty = 'assets/branding/ride_card/icons/avatar_empty.png';
  static const avatar3d = 'assets/branding/ride_card/icons/avatar_3d.png';
  static const shieldCheck = 'assets/branding/ride_card/icons/shield_check.png';
  static const declineX = 'assets/branding/ride_card/icons/decline_x.png';
}

/// Decodes [assetPath] at display size to avoid full-resolution image memory.
class RideCardAssetImage extends StatelessWidget {
  const RideCardAssetImage({
    required this.assetPath,
    required this.width,
    required this.height,
    super.key,
    this.fit = BoxFit.contain,
    this.opacity = 1,
  });

  final String assetPath;
  final double width;
  final double height;
  final BoxFit fit;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final image = Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      cacheWidth: (width * dpr).round().clamp(1, 2048),
      cacheHeight: (height * dpr).round().clamp(1, 2048),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
    );
    if (opacity >= 1) return image;
    return Opacity(opacity: opacity, child: image);
  }
}

