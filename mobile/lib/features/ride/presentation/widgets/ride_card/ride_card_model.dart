import 'package:flutter/foundation.dart';

/// Presentation-only ride card view model. No business logic.
@immutable
class RideCardModel {
  const RideCardModel({
    required this.rideId,
    required this.variant,
    required this.pickupLabel,
    required this.destinationLabel,
    this.tone = RideCardTone.standard,
    this.statusLabel,
    this.title,
    this.participant,
    this.vehicle,
    this.fareLabel,
    this.fareCaption,
    this.secondaryFareLabel,
    this.distanceLabel,
    this.durationLabel,
    this.paymentLabel,
    this.passengerCountLabel,
    this.serviceLabel,
    this.timestampLabel,
    this.expiresLabel,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.actions = const [],
    this.onTap,
    this.semanticsLabel,
    this.showRoutePreview = true,
  });

  final String rideId;
  final RideCardVariant variant;
  final RideCardTone tone;
  final String? statusLabel;
  final String? title;
  final String pickupLabel;
  final String destinationLabel;
  final RideCardParticipant? participant;
  final RideCardVehicle? vehicle;
  final String? fareLabel;
  final String? fareCaption;
  final String? secondaryFareLabel;
  final String? distanceLabel;
  final String? durationLabel;
  final String? paymentLabel;
  final String? passengerCountLabel;
  final String? serviceLabel;
  final String? timestampLabel;
  final String? expiresLabel;
  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final List<RideCardActionSpec> actions;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool showRoutePreview;

  bool get hasRouteCoords =>
      pickupLat != null &&
      pickupLng != null &&
      destinationLat != null &&
      destinationLng != null;

  bool get isActiveTone => tone == RideCardTone.active;
}

enum RideCardVariant {
  openRequest,
  driverJob,
  passengerHistory,
  offer,
}

enum RideCardTone { standard, active }

@immutable
class RideCardParticipant {
  const RideCardParticipant({
    required this.roleLabel,
    this.displayName,
    this.photoUrl,
    this.rating,
    this.tripCount,
  });

  final String roleLabel;
  final String? displayName;
  final String? photoUrl;
  final double? rating;
  final int? tripCount;

  bool get hasIdentity =>
      (displayName != null && displayName!.trim().isNotEmpty) ||
      (photoUrl != null && photoUrl!.trim().isNotEmpty);

  bool get hasStats => rating != null || tripCount != null;

  String get resolvedName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return roleLabel;
  }

  String get initials {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) {
      return roleLabel.isNotEmpty ? roleLabel[0].toUpperCase() : '?';
    }
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final chars = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return chars.isEmpty ? '?' : chars;
  }
}

@immutable
class RideCardVehicle {
  const RideCardVehicle({
    this.makeModel,
    this.color,
    this.registration,
    this.imageUrl,
  });

  final String? makeModel;
  final String? color;
  final String? registration;
  final String? imageUrl;

  bool get hasAnyField =>
      (makeModel != null && makeModel!.trim().isNotEmpty) ||
      (color != null && color!.trim().isNotEmpty) ||
      (registration != null && registration!.trim().isNotEmpty) ||
      (imageUrl != null && imageUrl!.trim().isNotEmpty);
}

@immutable
class RideCardActionSpec {
  const RideCardActionSpec({
    required this.label,
    this.onPressed,
    this.semanticLabel,
    this.isLoading = false,
    this.isPrimary = true,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool isLoading;
  final bool isPrimary;
  final bool isDestructive;
}
