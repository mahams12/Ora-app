import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/device_geocoder_port.dart';
import '../../domain/ports/place_search_port.dart';

/// Bounded-timeout place search with provider fallbacks.
///
/// Every provider call is wrapped in a hard [timeout] — a network or
/// platform-geocoder call that never completes can no longer leave the UI
/// stuck in a loading state. `autocomplete`/`resolvePlace`/`reverseGeocode`
/// first try [primary]; on error or timeout they try [secondary] (when
/// configured, e.g. the platform geocoder when Nominatim is primary).
/// `reverseGeocode` additionally falls back to the device-geocoder locality
/// label when both providers fail.
///
/// The error surfaced is always the PRIMARY failure — the most honest
/// description of why the preferred lookup failed.
class FallbackPlaceSearch implements PlaceSearchPort {
  const FallbackPlaceSearch({
    required PlaceSearchPort primary,
    required DeviceGeocoderPort deviceGeocoder,
    PlaceSearchPort? secondary,
    Duration timeout = const Duration(seconds: 10),
  })  : _primary = primary,
        _secondary = secondary,
        _device = deviceGeocoder,
        _timeout = timeout;

  final PlaceSearchPort _primary;
  final PlaceSearchPort? _secondary;
  final DeviceGeocoderPort _device;
  final Duration _timeout;

  static Never _timedOut() => throw const PlaceSearchException(
        PlaceSearchFailureKind.network,
        'Location lookup timed out.',
      );

  /// Run [call] against primary then secondary, each bounded by [_timeout].
  Future<T> _chain<T>(
    Future<T> Function(PlaceSearchPort port) call,
  ) async {
    Object? primaryError;
    try {
      return await call(_primary).timeout(_timeout, onTimeout: _timedOut);
    } catch (e) {
      primaryError = e;
      debugPrint(
        'place search primary failed '
        '(${e is PlaceSearchException ? e.kind : e.runtimeType})'
        '${_secondary != null ? ' — trying fallback' : ''}',
      );
    }
    final secondary = _secondary;
    if (secondary != null) {
      try {
        return await call(secondary).timeout(_timeout, onTimeout: _timedOut);
      } catch (e) {
        debugPrint(
          'place search fallback failed '
          '(${e is PlaceSearchException ? e.kind : e.runtimeType})',
        );
      }
    }
    if (primaryError is PlaceSearchException) throw primaryError;
    throw PlaceSearchException(
      PlaceSearchFailureKind.unavailable,
      '$primaryError',
    );
  }

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) =>
      _chain((p) => p.autocomplete(query: query, sessionToken: sessionToken));

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) =>
      _chain(
        (p) => p.resolvePlace(placeId: placeId, sessionToken: sessionToken),
      );

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    Object? primaryError;
    try {
      final result = await _primary
          .reverseGeocode(lat: lat, lng: lng)
          .timeout(_timeout, onTimeout: _timedOut);
      if (result.address?.trim().isNotEmpty == true) return result;
    } catch (e) {
      primaryError = e;
    }
    final secondary = _secondary;
    if (secondary != null) {
      try {
        final result = await secondary
            .reverseGeocode(lat: lat, lng: lng)
            .timeout(_timeout, onTimeout: _timedOut);
        if (result.address?.trim().isNotEmpty == true) return result;
      } catch (_) {
        // fall through to the device geocoder
      }
    }
    final label = await _device
        .localityLabel(lat: lat, lng: lng)
        .timeout(_timeout, onTimeout: () => null);
    if (label != null && label.trim().isNotEmpty) {
      return ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: label,
        source: PassengerLocationSource.gps,
      );
    }
    if (primaryError is PlaceSearchException) throw primaryError;
    if (primaryError != null) {
      throw PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        '$primaryError',
      );
    }
    throw const PlaceSearchException(
      PlaceSearchFailureKind.empty,
      'No locality available.',
    );
  }
}
