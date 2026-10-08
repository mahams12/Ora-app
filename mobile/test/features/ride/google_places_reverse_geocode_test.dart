import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/data/location/google_places_http_search.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';

class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

void main() {
  group('GooglePlacesHttpSearch.reverseGeocode', () {
    test('uses Places searchNearby and returns locality label', () async {
      final dio = Dio(
        BaseOptions(baseUrl: 'https://places.googleapis.com/'),
      );
      late RequestOptions seen;
      dio.httpClientAdapter = _FixtureAdapter((options) async {
        seen = options;
        return ResponseBody.fromString(
          '''
{
  "places": [
    {
      "displayName": {"text": "Shop"},
      "formattedAddress": "Block N Gulberg III, Lahore, Pakistan",
      "addressComponents": [
        {"longText": "Gulberg III", "types": ["sublocality_level_1", "sublocality"]},
        {"longText": "Lahore", "types": ["locality"]}
      ]
    }
  ]
}
''',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final search = GooglePlacesHttpSearch(apiKey: 'test-key', dio: dio);
      final resolved = await search.reverseGeocode(lat: 31.52, lng: 74.35);

      expect(seen.path, 'v1/places:searchNearby');
      expect(seen.method, 'POST');
      expect(resolved.address, 'Gulberg III, Lahore');
      expect(resolved.lat, 31.52);
      expect(resolved.lng, 74.35);
      expect(resolved.source, PassengerLocationSource.gps);
      // Coords authoritative — not replaced by place geometry.
      expect(resolved.displayLabel, isNot(contains('31.52')));
    });

    test('empty places → PlaceSearchException.empty', () async {
      final dio = Dio(
        BaseOptions(baseUrl: 'https://places.googleapis.com/'),
      );
      dio.httpClientAdapter = _FixtureAdapter((_) async {
        return ResponseBody.fromString(
          '{"places":[]}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });
      final search = GooglePlacesHttpSearch(apiKey: 'test-key', dio: dio);
      expect(
        () => search.reverseGeocode(lat: 31.5, lng: 74.3),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.kind,
            'kind',
            PlaceSearchFailureKind.empty,
          ),
        ),
      );
    });

    test('network failure → PlaceSearchException.network', () async {
      final dio = Dio(
        BaseOptions(baseUrl: 'https://places.googleapis.com/'),
      );
      dio.httpClientAdapter = _FixtureAdapter((_) async {
        throw DioException(
          requestOptions: RequestOptions(path: 'v1/places:searchNearby'),
          type: DioExceptionType.connectionTimeout,
          message: 'timeout',
        );
      });
      final search = GooglePlacesHttpSearch(apiKey: 'test-key', dio: dio);
      expect(
        () => search.reverseGeocode(lat: 31.5, lng: 74.3),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.kind,
            'kind',
            PlaceSearchFailureKind.network,
          ),
        ),
      );
    });
  });
}
