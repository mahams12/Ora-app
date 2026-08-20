import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/utils/pakistan_phone_number.dart';

void main() {
  group('PakistanPhoneNumber', () {
    test('accepts exact E.164 mobile length', () {
      expect(PakistanPhoneNumber.normalize('+923001234567'), '+923001234567');
      expect(PakistanPhoneNumber.isValid('+923096557185'), isTrue);
    });

    test('normalizes local 03… form', () {
      expect(PakistanPhoneNumber.normalize('03001234567'), '+923001234567');
    });

    test('rejects wrong digit counts', () {
      expect(PakistanPhoneNumber.normalize('+92300123456'), isNull); // 9 after 3
      expect(PakistanPhoneNumber.normalize('+9230012345678'), isNull); // 11
      expect(PakistanPhoneNumber.normalize('+9203001234567'), isNull); // leading 0
      expect(PakistanPhoneNumber.normalize('+924001234567'), isNull); // not mobile 3
    });

    test('validationError mentions exact length', () {
      final err = PakistanPhoneNumber.validationError('+92300123456');
      expect(err, contains('10 digits after +92'));
    });
  });
}
