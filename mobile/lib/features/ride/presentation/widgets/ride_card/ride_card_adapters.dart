import 'dart:math' as math;

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

  /// Open-rides marketplace card — epic layout; empty slots when unknown.
  static RideCardModel fromOpenRide(
    OpenRide ride, {
    required bool offering,
    required bool offerDisabled,
    required VoidCallback onAccept,
    VoidCallback? onDecline,
    VoidCallback? onTap,
  }) {
    final distance = _formatDistanceKm(ride.distanceKm);
    final duration = _formatDurationMin(ride.estimatedDurationMin);
    final active = !_isTerminalOpenState(ride.state);
    final category = _category(ride.category);

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.openRequest,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: switch (ride.state.toUpperCase()) {
        'SEARCHING' => 'Searching',
        'OFFERS_AVAILABLE' => 'Offers',
        _ => openRideStateLabel(ride.state),
      },
      statusKind:
          active ? RideCardStatusKind.active : RideCardStatusKind.neutral,
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      // Privacy: open DTO has no passenger identity — leave empty slots.
      participant: null,
      // passengerOfferMinor is the gross fare offered — not driver payout.
      fareLabel: formatOpenRideFareMinor(ride.passengerOfferMinor),
      fareCaption: 'Trip fare',
      distanceLabel: distance,
      durationLabel: duration,
      // Ora Courier — non-contact parcel summary on the service slot.
      serviceLabel: _openRideServiceLabel(ride),
      paymentLabel: _paymentLabel(ride.paymentMethod),
      categoryLabel: category.$1,
      categoryTone: category.$2,
      carAsset: _carAssetFor(ride.rideId),
      expiresLabel: _relativeAge(
        createdAt: ride.createdAt,
        expiresAt: ride.expiresAt,
      ),
      showRoutePreview: true,
      showMapThumb: true,
      showCarAccent: true,
      actions: [
        RideCardActionSpec(
          label: 'Decline',
          semanticLabel: 'Decline ride request',
          isPrimary: false,
          onPressed: offerDisabled ? null : onDecline,
        ),
        RideCardActionSpec(
          label: offering ? 'Submitting…' : 'Accept',
          semanticLabel: 'Accept ride request',
          isLoading: offering,
          onPressed: offerDisabled ? null : onAccept,
          isPrimary: true,
        ),
      ],
      onTap: onTap,
      semanticsLabel: 'Ride id ${ride.rideId}',
    );
  }

  /// Dispatch invitation — same epic card as open rides, plus the animated
  /// Accept countdown driven by the server-authoritative invite deadline.
  /// [remaining] is the live server-adjusted remaining duration (ticks ~1s);
  /// [windowTotal] is the full invite TTL so late-arriving invites show the
  /// true remaining fraction instead of restarting the ring.
  static RideCardModel fromDriverInvite(
    DriverInvite invite, {
    required Duration remaining,
    required Duration windowTotal,
    required bool responding,
    required VoidCallback onAccept,
    required VoidCallback onDecline,
    VoidCallback? onTap,
  }) {
    final secondsLeft = remaining.inSeconds.clamp(0, 1 << 30);
    final actionable = invite.isActionable && secondsLeft > 0;
    final distance = _formatDistanceKm(invite.distanceKm);
    final category = _category(invite.category);
    final progress = windowTotal.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / windowTotal.inMilliseconds)
            .clamp(0.0, 1.0);

    return RideCardModel(
      rideId: invite.rideId,
      variant: RideCardVariant.openRequest,
      tone: actionable ? RideCardTone.active : RideCardTone.standard,
      statusLabel: actionable ? 'Invitation' : 'Expired',
      statusKind:
          actionable ? RideCardStatusKind.active : RideCardStatusKind.neutral,
      pickupLabel: rideCardLocationLabel(invite.pickup),
      destinationLabel: rideCardLocationLabel(invite.destination),
      pickupLat: invite.pickup.lat,
      pickupLng: invite.pickup.lng,
      destinationLat: invite.destination.lat,
      destinationLng: invite.destination.lng,
      participant: null,
      // passengerOfferMinor is the gross fare offered — not driver payout.
      fareLabel:
          formatOfferAmountMinor(invite.passengerOfferMinor, invite.currency),
      fareCaption: 'Trip fare',
      distanceLabel: distance,
      // Ora Courier — invite surfaces the parcel summary in the service
      // slot: "Courier · small · 2 kg × 1". Contacts stay hidden until the
      // driver is actually assigned (server-side projection rule).
      serviceLabel: _inviteServiceLabel(invite),
      categoryLabel: category.$1,
      categoryTone: category.$2,
      carAsset: _carAssetFor(invite.rideId),
      expiresLabel:
          actionable ? 'Respond within ${secondsLeft}s' : 'Offer expired',
      showRoutePreview: true,
      showMapThumb: true,
      showCarAccent: true,
      actions: [
        RideCardActionSpec(
          label: 'Decline',
          semanticLabel: 'Decline invitation',
          isPrimary: false,
          onPressed: actionable && !responding ? onDecline : null,
        ),
        RideCardActionSpec(
          label: responding
              ? 'Sending…'
              : (actionable ? 'Accept · ${secondsLeft}s' : 'Expired'),
          semanticLabel: actionable
              ? 'Accept invitation, $secondsLeft seconds remaining'
              : 'Invitation expired',
          isLoading: responding,
          onPressed: actionable && !responding ? onAccept : null,
          isPrimary: true,
          progress: actionable ? progress : null,
        ),
      ],
      onTap: onTap,
      semanticsLabel:
          'Dispatch invitation ${invite.rideId}, ${actionable ? '$secondsLeft seconds left' : 'expired'}',
    );
  }

  /// Driver job / my-rides card — empty passenger/vehicle slots when unknown.
  static RideCardModel fromDriverJob(
    Ride ride, {
    VoidCallback? onTap,
  }) {
    final fare = formatMinorFare(ride.agreedFareMinor, ride.agreedFareCurrency);
    final active = !isDriverJobTerminalState(ride.state);
    final kind = _statusKind(ride.state);
    final secondary = active ? ride.state.toUpperCase() : null;
    // History/job APIs omit distanceKm — derive display-only km from coords.
    final distance = _formatDistanceFromPoints(ride.pickup, ride.destination);

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.driverJob,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: _statusBadge(ride.state),
      secondaryStatusLabel: secondary,
      statusKind: kind,
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      participant: null,
      vehicle: null,
      fareLabel: fare,
      // agreedFareMinor is the gross trip fare — not a driver payout.
      fareCaption: kind == RideCardStatusKind.danger
          ? 'Cancelled'
          : active
              ? 'Agreed fare'
              : 'Trip fare',
      distanceLabel: distance,
      // Duration is not on Ride DTO — leave null (grid shows "—").
      durationLabel: null,
      paymentLabel: _paymentLabel(ride.paymentMethod),
      timestampLabel: active
          ? _startedRelative(ride.startedAt ?? ride.assignedAt ?? ride.createdAt)
          : formatHistoryTimestamp(ride.createdAt),
      carAsset: _carAssetFor(ride.rideId),
      showRoutePreview: true,
      showMapThumb: true,
      showCarAccent: true,
      onTap: onTap,
      semanticsLabel: 'Assigned ride ${ride.rideId}',
    );
  }

  /// Passenger history — empty driver/vehicle slots when unknown.
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
    final kind = _statusKind(ride.state);
    final distance = _formatDistanceFromPoints(ride.pickup, ride.destination);

    return RideCardModel(
      rideId: ride.rideId,
      variant: RideCardVariant.passengerHistory,
      tone: active ? RideCardTone.active : RideCardTone.standard,
      statusLabel: _statusBadge(ride.state),
      statusKind: kind,
      pickupLabel: rideCardLocationLabel(ride.pickup),
      destinationLabel: rideCardLocationLabel(ride.destination),
      pickupLat: ride.pickup.lat,
      pickupLng: ride.pickup.lng,
      destinationLat: ride.destination.lat,
      destinationLng: ride.destination.lng,
      participant: null,
      vehicle: null,
      fareLabel: fare,
      fareCaption: kind == RideCardStatusKind.danger
          ? 'Cancelled'
          : kind == RideCardStatusKind.success
              ? _settlementCaption(ride)
              : null,
      distanceLabel: distance,
      durationLabel: null,
      paymentLabel: _paymentLabel(ride.paymentMethod),
      timestampLabel: formatHistoryTimestamp(ride.createdAt),
      carAsset: _carAssetFor(ride.rideId),
      showRoutePreview: true,
      showMapThumb: false,
      showCarAccent: true,
      onTap: onTap,
      semanticsLabel: 'Ride ${ride.rideId}',
    );
  }

  /// Offer inbox — empty driver slot when snapshot has no displayName.
  static RideCardModel fromOffer(
    RideOffer offer, {
    required VoidCallback? onSelect,
    required bool isSelecting,
    required bool enabled,
  }) {
    final selectable = enabled && isOfferSelectable(offer) && !isSelecting;
    final amount = formatOfferAmountMinor(offer.amountMinor, offer.currency);
    final snapshotName = _snapshotDisplayName(offer.driverSnapshot);
    final pending = offer.status.toUpperCase() == 'PENDING';

    return RideCardModel(
      rideId: offer.rideId,
      variant: RideCardVariant.offer,
      tone: pending ? RideCardTone.active : RideCardTone.standard,
      statusLabel: offer.status.toUpperCase(),
      statusKind:
          pending ? RideCardStatusKind.active : RideCardStatusKind.neutral,
      pickupLabel: '',
      destinationLabel: '',
      showRoutePreview: false,
      showMapThumb: false,
      showCarAccent: true,
      carAsset: _carAssetFor(offer.offerId),
      participant: snapshotName == null
          ? null
          : RideCardParticipant(
              roleLabel: 'Driver',
              displayName: snapshotName,
            ),
      fareLabel: amount,
      fareCaption: 'Driver offer',
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
      semanticsLabel: '${snapshotName ?? 'Driver offer'}, $amount, ${offer.status}',
    );
  }

  static List<String> _courierParcelParts(Map<String, Object?> p) {
    final size = (p['size'] ?? '').toString().toLowerCase();
    final weight = p['weightKg']?.toString();
    final qty = p['quantity']?.toString();
    return <String>[
      if (size.isNotEmpty) size,
      if (weight != null) '${weight}kg',
      if (qty != null && qty != '1') '×$qty',
    ];
  }

  /// Ora Courier v2 — stop count + per-shop budget hints so the driver can
  /// judge the job before accepting/offering.
  static List<String> _v2Parts({
    required List<RideStop>? stops,
    required Map<String, Object?>? shopping,
  }) {
    final parts = <String>[];
    if (stops != null && stops.length > 2) {
      parts.add('${stops.length} stops');
    }
    final budget = shopping?['totalBudgetMinor'];
    if (budget is int && budget > 0) {
      parts.add('budget Rs ${budget ~/ 100}');
    }
    if (stops != null && shopping != null) {
      final shopCount = stops.where((s) => s.type == 'SHOP').length;
      if (shopCount > 0) parts.add('$shopCount shops');
    }
    return parts;
  }

  static String? _openRideServiceLabel(OpenRide ride) {
    final base = ride.serviceType.trim().isEmpty
        ? null
        : historyServiceTypeLabel(ride.serviceType);
    final parts = <String>[
      if (base != null) base,
      ..._v2Parts(stops: ride.stops, shopping: ride.shopping),
      if (ride.parcel != null) ..._courierParcelParts(ride.parcel!),
    ];
    return parts.isEmpty ? base : parts.join(' · ');
  }

  static String? _inviteServiceLabel(DriverInvite invite) {
    final base = invite.serviceType.trim().isEmpty
        ? null
        : historyServiceTypeLabel(invite.serviceType);
    final parts = <String>[
      if (base != null) base,
      ..._v2Parts(stops: invite.stops, shopping: invite.shopping),
      if (invite.parcel != null) ..._courierParcelParts(invite.parcel!),
    ];
    return parts.isEmpty ? base : parts.join(' · ');
  }

  static String? _relativeAge({
    required String createdAt,
    required String expiresAt,
  }) {
    final created = DateTime.tryParse(createdAt);
    if (created != null) {
      final age = DateTime.now().difference(created.toLocal());
      if (!age.isNegative) {
        if (age.inMinutes < 1) return 'just now';
        if (age.inMinutes < 60) return '${age.inMinutes} min ago';
        if (age.inHours < 24) return '${age.inHours}h ago';
        return '${age.inDays}d ago';
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

  static String? _startedRelative(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return formatHistoryTimestamp(iso);
    final age = DateTime.now().difference(parsed.toLocal());
    if (age.isNegative) return formatHistoryTimestamp(iso);
    if (age.inMinutes < 1) return 'Started · just now';
    if (age.inMinutes < 60) return 'Started · ${age.inMinutes} min ago';
    if (age.inHours < 24) return 'Started · ${age.inHours}h ago';
    return 'Started · ${formatHistoryTimestamp(iso) ?? iso}';
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

  /// Display-only great-circle distance from authoritative pickup/destination.
  /// Used when history/job DTOs omit distanceKm (no invented route geometry).
  static String? _formatDistanceFromPoints(LatLngPoint a, LatLngPoint b) {
    final km = _haversineKm(a.lat, a.lng, b.lat, b.lng);
    if (km.isNaN || km <= 0) return null;
    return _formatDistanceKm(km);
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthKm * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  static String? _formatDurationMin(int? minutes) {
    if (minutes == null) return null;
    return '$minutes min';
  }

  /// Settlement-aware fare caption — never claims "Paid" unless the server
  /// settlement says SETTLED. Rides with no settlement block keep the old
  /// payment-method caption.
  static String? _settlementCaption(Ride ride) {
    final settlement = ride.settlement;
    final status = settlement == null
        ? null
        : (settlement['status'] as String?)?.toUpperCase();
    final method = _paymentLabel(ride.paymentMethod);
    if (status == 'DISPUTED') return 'Payment disputed';
    if (status == 'SETTLED') {
      return method == null ? 'Paid' : 'Paid ($method)';
    }
    if (status == 'PENDING') {
      return method == null ? 'Payment pending' : 'Pending ($method)';
    }
    return method == null ? null : 'Paid ($method)';
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

  static (String?, RideCardCategoryTone) _category(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'easy':
        return ('Easy', RideCardCategoryTone.easy);
      case 'medium':
        return ('Medium', RideCardCategoryTone.medium);
      case 'hard':
        return ('Hard', RideCardCategoryTone.hard);
      default:
        final t = raw.trim();
        if (t.isEmpty) return (null, RideCardCategoryTone.none);
        return (
          '${t[0].toUpperCase()}${t.substring(1)}',
          RideCardCategoryTone.none,
        );
    }
  }

  static RideCardCarAsset _carAssetFor(String seed) {
    final h = seed.hashCode.abs() % 3;
    return switch (h) {
      0 => RideCardCarAsset.white,
      1 => RideCardCarAsset.silver,
      _ => RideCardCarAsset.black,
    };
  }

  static RideCardStatusKind _statusKind(String state) {
    return switch (state.toUpperCase()) {
      'RIDE_COMPLETED' || 'RIDE_CLOSED' => RideCardStatusKind.success,
      'CANCELLED' || 'EXPIRED' || 'NO_SHOW' => RideCardStatusKind.danger,
      'RIDE_STARTED' ||
      'DRIVER_EN_ROUTE' ||
      'DRIVER_ARRIVED' ||
      'DRIVER_ASSIGNED' =>
        RideCardStatusKind.active,
      'SEARCHING' || 'OFFERS_AVAILABLE' => RideCardStatusKind.active,
      _ => RideCardStatusKind.neutral,
    };
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
      'RIDE_CLOSED' => 'Completed',
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
