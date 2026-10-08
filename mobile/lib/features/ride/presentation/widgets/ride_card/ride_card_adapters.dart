import 'package:flutter/foundation.dart';

import '../../../../driver/presentation/driver_display.dart';
import '../../../../driver/presentation/open_ride_display.dart';
import '../../../domain/entities/ride.dart';
import '../../history/ride_history_display.dart';
import '../../offers/offer_display.dart';
import 'ride_card_location_label.dart';
import 'ride_card_model.dart';

/// Maps domain DTOs → [RideCardModel]. Presentation only; no business rules.
class RideCardAdapters {
  RideCardAdapters._();

  /// Ultra-compact marketplace card — decision fields only.
  ///
  /// Omits passenger identity, vehicle, category badges, recommended-fare
  /// duplication, passenger count, and painter route preview.
  static RideCardModel fromOpenRide(
    OpenRide ride, {
    required bool offering,
    required bool offerDisabled,
    required VoidCallback onRespond,
  }) {
    final distance = _formatDistanceKm(ride.distanceKm);
    final duration = _formatDurationMin(ride.estimatedDurationMin);
    final active = !_isTerminalOpenState(ride.state);

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.openRequest,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: openRideStateLabel(ride.state),
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      // No passenger identity on open discovery — do not invent.
      participant: null,
      fareLabel: formatOpenRideFareMinor(ride.passengerOfferMinor),
      distanceLabel: distance,
      durationLabel: duration,
      paymentLabel: _paymentLabel(ride.paymentMethod),
      // Short age / expiry for header trailing — not a second fare block.
      expiresLabel: _compactOpenRideAge(
        createdAt: ride.createdAt,
        expiresAt: ride.expiresAt,
      ),
      showRoutePreview: false,
      actions: [
        RideCardActionSpec(
          label: offering ? 'Submitting…' : 'Respond',
          semanticLabel: 'Respond to ride request',
          isLoading: offering,
          onPressed: offerDisabled ? null : onRespond,
          isPrimary: true,
        ),
      ],
      semanticsLabel: 'Ride id ${ride.rideId}',
    );
  }

  /// Compact driver job / my-rides card.
  static RideCardModel fromDriverJob(
    Ride ride, {
    VoidCallback? onTap,
  }) {
    final fare = formatMinorFare(ride.agreedFareMinor, ride.agreedFareCurrency);
    final active = !isDriverJobTerminalState(ride.state);

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.driverJob,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: _statusBadge(ride.state),
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      // Assigned list has passengerId only — omit placeholder participant row.
      // Ride history DTO has no distance/duration — omit rather than invent.
      participant: null,
      fareLabel: fare,
      paymentLabel: _paymentLabel(ride.paymentMethod),
      timestampLabel: formatHistoryTimestamp(ride.createdAt),
      showRoutePreview: false,
      onTap: onTap,
      semanticsLabel: 'Assigned ride ${ride.rideId}',
    );
  }

  /// Compact passenger history card — no driver profile required.
  static RideCardModel fromPassengerHistory(
    Ride ride, {
    VoidCallback? onTap,
  }) {
    final fare = formatMinorFare(
      ride.agreedFareMinor ?? ride.passengerOfferMinor,
      ride.agreedFareCurrency,
    );
    final active = !isHistoryTerminalState(ride.state) &&
        ride.state.toUpperCase() != 'RIDE_CLOSED';

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.passengerHistory,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: _statusBadge(ride.state),
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      // History DTO has assignedDriverId only — identity belongs in detail.
      // No distance/duration on Ride — omit rather than invent.
      participant: null,
      fareLabel: fare,
      paymentLabel: _paymentLabel(ride.paymentMethod),
      timestampLabel: formatHistoryTimestamp(ride.createdAt),
      showRoutePreview: false,
      onTap: onTap,
      semanticsLabel: 'Ride ${ride.rideId}',
    );
  }

  /// Offer inbox — slightly richer; only real API fields.
  static RideCardModel fromOffer(
    RideOffer offer, {
    required VoidCallback? onSelect,
    required bool isSelecting,
    required bool enabled,
  }) {
    final selectable = enabled && isOfferSelectable(offer) && !isSelecting;
    final amount = formatOfferAmountMinor(offer.amountMinor, offer.currency);
    final driverName = offerDriverLabel(offer);
    final snapshotName = _snapshotDisplayName(offer.driverSnapshot);

    return RideCardModel(
      rideId: offer.rideId,
      variant: RideCardVariant.offer,
      tone: offer.status.toUpperCase() == 'PENDING'
          ? RideCardTone.active
          : RideCardTone.standard,
      title: driverName,
      statusLabel: offer.status.toUpperCase(),
      pickupLabel: '',
      destinationLabel: '',
      showRoutePreview: false,
      // Only attach participant when API provides a real display name.
      participant: snapshotName == null
          ? null
          : RideCardParticipant(
              roleLabel: 'Driver',
              displayName: snapshotName,
            ),
      fareLabel: amount,
      serviceLabel: offer.type.trim().isEmpty ? null : offer.type.trim(),
      expiresLabel: offer.expiresAt.trim().isEmpty
          ? null
          : 'Expires ${_shortIso(offer.expiresAt)}',
      actions: [
        if (isSelecting)
          const RideCardActionSpec(
            label: 'Selecting…',
            isLoading: true,
          )
        else if (selectable)
          RideCardActionSpec(
            label: 'Select',
            semanticLabel: 'Select offer',
            onPressed: onSelect,
            isPrimary: true,
          ),
      ],
      semanticsLabel: '$driverName, $amount, ${offer.status}',
    );
  }

  /// Prefer short request age; fall back to compact expiry.
  static String? _compactOpenRideAge({
    required String createdAt,
    required String expiresAt,
  }) {
    final created = DateTime.tryParse(createdAt);
    if (created != null) {
      final age = DateTime.now().difference(created.toLocal());
      if (!age.isNegative) {
        if (age.inMinutes < 1) return '<1m';
        if (age.inMinutes < 60) return '${age.inMinutes}m';
        if (age.inHours < 24) return '${age.inHours}h';
        return '${age.inDays}d';
      }
    }
    final expires = DateTime.tryParse(expiresAt);
    if (expires == null) return null;
    final delta = expires.difference(DateTime.now());
    if (delta.isNegative) return 'Expired';
    if (delta.inMinutes < 1) return '<1m left';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m left';
    return openRideExpiresLabel(expiresAt);
  }

  static String? _snapshotDisplayName(Map<String, Object?>? snapshot) {
    if (snapshot == null) return null;
    final raw = snapshot['displayName'];
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _shortIso(String iso) {
    if (iso.length >= 16) return iso.substring(11, 16);
    return iso;
  }

  static String? _formatDistanceKm(double? km) {
    if (km == null) return null;
    final whole = km == km.roundToDouble()
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(1);
    return '$whole km';
  }

  static String? _formatDurationMin(int? minutes) {
    if (minutes == null) return null;
    return '$minutes min';
  }

  static String? _paymentLabel(String? method) {
    final trimmed = method?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    switch (trimmed.toUpperCase()) {
      case 'CASH':
        return 'Cash';
      case 'CARD':
        return 'Card';
      case 'WALLET':
        return 'Wallet';
      default:
        return trimmed;
    }
  }

  static String _statusBadge(String state) {
    return switch (state.toUpperCase()) {
      'SEARCHING' => 'Searching',
      'OFFERS_AVAILABLE' => 'Offers',
      'DRIVER_ASSIGNED' => 'Assigned',
      'DRIVER_EN_ROUTE' => 'En route',
      'DRIVER_ARRIVED' => 'Arrived',
      'RIDE_STARTED' => 'In progress',
      'RIDE_COMPLETED' => 'Completed',
      'RIDE_CLOSED' => 'Closed',
      'CANCELLED' => 'Cancelled',
      'EXPIRED' => 'Expired',
      'NO_SHOW' => 'No-show',
      _ => state,
    };
  }

  static bool _isTerminalOpenState(String state) {
    final s = state.toUpperCase();
    return s == 'CANCELLED' || s == 'EXPIRED' || s == 'NO_SHOW';
  }
}
