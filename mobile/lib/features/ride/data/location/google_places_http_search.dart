import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/place_search_port.dart';

/// Google Places API (New) over HTTP — client Places key only (not Routes).
///
/// Requires `--dart-define=ORA_GOOGLE_PLACES_API_KEY=...` (Places API enabled).
/// Prefer API-restricted key; Android package restriction applies to native SDKs.
class GooglePlacesHttpSearch implements PlaceSearchPort {
  GooglePlacesHttpSearch({
    required String apiKey,
    Dio? dio,
    Uuid? uuid,
  })  : _apiKey = apiKey.trim(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://places.googleapis.com/',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 12),
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            ),
        _uuid = uuid ?? const Uuid();

  final String _apiKey;
  final Dio _dio;
  final Uuid _uuid;

  bool get isConfigured => _apiKey.isNotEmpty;

  String newSessionToken() => _uuid.v4();

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.notConfigured,
        'Places API key is not configured.',
      );
    }
  }

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    _ensureConfigured();
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'v1/places:autocomplete',
        data: <String, Object?>{
          'input': trimmed,
          'sessionToken': sessionToken,
          'includedRegionCodes': <String>['pk'],
          'languageCode': 'en',
        },
        options: Options(
          headers: <String, String>{
            'X-Goog-Api-Key': _apiKey,
            'X-Goog-FieldMask':
                'suggestions.placePrediction.placeId,'
                'suggestions.placePrediction.text,'
                'suggestions.placePrediction.structuredFormat',
          },
        ),
      );

      final suggestions = response.data?['suggestions'];
      if (suggestions is! List || suggestions.isEmpty) {
        return const [];
      }

      final out = <PlaceSuggestion>[];
      for (final raw in suggestions) {
        if (raw is! Map) continue;
        final prediction = raw['placePrediction'];
        if (prediction is! Map) continue;
        final placeId = prediction['placeId']?.toString();
        if (placeId == null || placeId.isEmpty) continue;

        final structured = prediction['structuredFormat'];
        String primary = '';
        String? secondary;
        if (structured is Map) {
          final main = structured['mainText'];
          final secondaryText = structured['secondaryText'];
          if (main is Map) primary = main['text']?.toString() ?? '';
          if (secondaryText is Map) {
            secondary = secondaryText['text']?.toString();
          }
        }
        if (primary.isEmpty) {
          final text = prediction['text'];
          if (text is Map) primary = text['text']?.toString() ?? '';
        }
        if (primary.isEmpty) continue;

        out.add(
          PlaceSuggestion(
            placeId: placeId,
            primaryText: primary,
            secondaryText: secondary,
          ),
        );
      }
      return out;
    } on PlaceSearchException {
      rethrow;
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
    _ensureConfigured();
    final id = placeId.trim();
    if (id.isEmpty) {
      throw const PlaceSearchException(
        PlaceSearchFailureKind.invalid,
        'Missing place id.',
      );
    }

    try {
      // Places API (New): resource name may already include "places/" prefix.
      final path = id.startsWith('places/') ? 'v1/$id' : 'v1/places/$id';
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: <String, Object?>{
          'sessionToken': sessionToken,
        },
        options: Options(
          headers: <String, String>{
            'X-Goog-Api-Key': _apiKey,
            'X-Goog-FieldMask':
                'id,formattedAddress,location,displayName',
          },
        ),
      );

      final data = response.data;
      if (data == null) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.invalid,
          'Empty place details.',
        );
      }

      final location = data['location'];
      if (location is! Map) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.invalid,
          'Place has no coordinates.',
        );
      }
      final lat = (location['latitude'] as num?)?.toDouble();
      final lng = (location['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.invalid,
          'Place has no coordinates.',
        );
      }

      String? address = data['formattedAddress']?.toString();
      if (address == null || address.trim().isEmpty) {
        final displayName = data['displayName'];
        if (displayName is Map) {
          address = displayName['text']?.toString();
        }
      }

      final resolved = ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        address: address,
        placeId: id.startsWith('places/') ? id.substring('places/'.length) : id,
        source: PassengerLocationSource.place,
      );
      if (!resolved.hasValidCoordinates) {
        throw const PlaceSearchException(
          PlaceSearchFailureKind.invalid,
          'We couldn\'t use that location. Pick another point.',
        );
      }
      return resolved;
    } on PlaceSearchException {
      rethrow;
    } on DioException catch (e) {
      throw PlaceSearchException(
        PlaceSearchFailureKind.network,
        e.message,
      );
    } catch (e) {
      if (e is PlaceSearchException) rethrow;
      throw const PlaceSearchException(
        PlaceSearchFailureKind.unavailable,
        'Location lookup isn\'t available right now. Try again.',
      );
    }
  }
}
