import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/data/location/places_locality_label.dart';

void main() {
  group('localityLabelFromPlacesNearby', () {
    test('A — neighborhood/sublocality + city from addressComponents', () {
      final places = [
        {
          'displayName': {'text': 'Some Shop'},
          'formattedAddress':
              '9688+HR, Tarogil Road, Eden Park, Lahore, Pakistan',
          'addressComponents': [
            {
              'longText': 'Eden Park',
              'types': ['neighborhood', 'political'],
            },
            {
              'longText': 'Lahore',
              'types': ['locality', 'political'],
            },
            {
              'longText': 'Pakistan',
              'types': ['country', 'political'],
            },
          ],
        },
      ];
      expect(localityLabelFromPlacesNearby(places), 'Eden Park, Lahore');
    });

    test('A2 — prefer sublocality_level_1 over block neighborhood', () {
      final places = [
        {
          'displayName': {'text': 'MOUZAN\'S ZONE'},
          'formattedAddress':
              'G9C5+5F5, Block N Gulberg III, Lahore, Pakistan',
          'addressComponents': [
            {
              'longText': 'Block N',
              'types': ['sublocality_level_2', 'sublocality', 'political'],
            },
            {
              'longText': 'Block N',
              'types': ['neighborhood', 'political'],
            },
            {
              'longText': 'Gulberg III',
              'types': ['sublocality_level_1', 'sublocality', 'political'],
            },
            {
              'longText': 'Lahore',
              'types': ['locality', 'political'],
            },
          ],
        },
      ];
      expect(localityLabelFromPlacesNearby(places), 'Gulberg III, Lahore');
    });

    test('B — locality alone when no neighborhood', () {
      final places = [
        {
          'formattedAddress': 'Lahore, Punjab, Pakistan',
          'addressComponents': [
            {
              'longText': 'Lahore',
              'types': ['locality', 'political'],
            },
            {
              'longText': 'Punjab',
              'types': ['administrative_area_level_1', 'political'],
            },
          ],
        },
      ];
      expect(localityLabelFromPlacesNearby(places), 'Lahore');
    });

    test('C — formatted-address fallback when components missing', () {
      final places = [
        {
          'formattedAddress':
              'Nabi Park Rd, Ravi Park, Lahore, Pakistan',
          'addressComponents': <Object?>[],
        },
      ];
      expect(
        localityLabelFromPlacesNearby(places),
        'Ravi Park, Lahore',
      );
    });

    test('C2 — strips plus-code from formatted fallback', () {
      final places = [
        {
          'formattedAddress':
              '9688+HR, Eden Park, Lahore, Pakistan',
        },
      ];
      expect(localityLabelFromPlacesNearby(places), 'Eden Park, Lahore');
    });

    test('D — empty places → null', () {
      expect(localityLabelFromPlacesNearby(const []), isNull);
    });

    test('D2 — empty components and empty formatted → null', () {
      expect(
        localityLabelFromPlacesNearby([
          {'displayName': <String, Object?>{}},
        ]),
        isNull,
      );
    });

    test('supports Geocoding-style long_name fields', () {
      final places = [
        {
          'address_components': null,
          'addressComponents': [
            {
              'long_name': 'Shad Bagh',
              'types': ['sublocality_level_1', 'sublocality'],
            },
            {
              'long_name': 'Lahore',
              'types': ['locality'],
            },
          ],
        },
      ];
      expect(localityLabelFromPlacesNearby(places), 'Shad Bagh, Lahore');
    });
  });
}
