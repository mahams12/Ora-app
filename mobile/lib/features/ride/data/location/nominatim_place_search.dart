import 'package:dio/dio.dart';

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/place_search_port.dart';

/// OpenStreetMap Nominatim place search — free, no API key, no billing.
/// Used as the primary [PlaceSearchPort] when no Google Places key is
/// configured (local/test builds), so search + reverse geocode work on
/// devices without an Android Geocoder backend (e.g. some MIUI ROMs).
///
/// Nominatim usage policy: identifiable User-Agent, ~1 req/s — fine for
/// test fleets, not for production scale.
class NominatimPlaceSearch implements PlaceSearchPort {
  NominatimPlaceSearch({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://nominatim.openstreetmap.org',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent': 'OraApp-TestBuild/1.0 (dev testing)',
                'Accept': 'application/json',
              },
            ));

  final Dio _dio;

  /// Coordinates ride inside the placeId so `resolvePlace` needs no second
  /// network call: `osm:<lat>:<lng>:<name>`.
  static const _idPrefix = 'osm:';

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final res = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: {
          'format': 'jsonv2',
          'q': q,
          'countrycodes': 'pk',
          'limit': 6,
          'addressdetails': 1,
          'accept-language': 'en',
        },
      );
      final out = <PlaceSuggestion>[];
      for (final item in res.data ?? const []) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lng = double.tryParse('${item['lon']}');
        final name = item['display_name']?.toString();
        if (lat == null || lng == null || name == null || name.isEmpty) {
          continue;
        }
        final parts = name.split(',');
        out.add(PlaceSuggestion(
          placeId: '$_idPrefix$lat:$lng:${parts.first.trim()}',
          primaryText: parts.first.trim(),
          secondaryText:
              parts.length > 1 ? parts.sublist(1).join(',').trim() : null,
        ));
      }
      return out;
    } on DioException catch (e) {
      throw PlaceSearchException(
        PlaceSearchFailureKind.network,
        e.message,
      );
    } catch (_) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        'Location lookup isn\'t available right now.',
      );
    }
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    final id = placeId.trim();
    if (!id.startsWith(_idPrefix)) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Unknown place reference.',
      );
    }
    final rest = id.substring(_idPrefix.length);
    final firstColon = rest.indexOf(':');
    final secondColon = firstColon < 0 ? -1 : rest.indexOf(':', firstColon + 1);
    final lat = firstColon < 0 ? null : double.tryParse(rest.substring(0, firstColon));
    final lng = secondColon < 0
        ? null
        : double.tryParse(rest.substring(firstColon + 1, secondColon));
    final name = secondColon < 0 ? '' : rest.substring(secondColon + 1);
    if (lat == null || lng == null) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Malformed place reference.',
      );
    }
    return ResolvedPassengerLocation(
      lat: lat,
      lng: lng,
      address: name.isEmpty ? null : name,
      placeId: id,
      source: PassengerLocationSource.place,
    );
  }

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Invalid coordinates.',
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': lat,
          'lon': lng,
          'zoom': 16,
          'addressdetails': 1,
          'accept-language': 'en',
        },
      );
      final data = res.data;
      final name = data?['display_name']?.toString();
      if (name == null || name.trim().isEmpty) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.empty,
          'No place found for coordinates.',
        );
      }
      return ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: name,
        source: PassengerLocationSource.gps,
      );
    } on PlaceSearchException {
      rethrow;
    } on DioException catch (e) {
      throw PlaceSearchException(
        PlaceSearchFailureKind.network,
        '${e.message ?? 'DioException ${e.type.name}'}'
        '${e.response?.statusCode != null ? ' (HTTP ${e.response!.statusCode})' : ''}',
      );
    } catch (_) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        'Location lookup isn\'t available right now.',
      );
    }
  }
}
