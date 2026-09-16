import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/utils/display_name.dart';

void main() {
  test('trims and collapses whitespace', () {
    expect(DisplayName.normalize('  Ada   Khan  '), 'Ada Khan');
  });

  test('rejects empty and whitespace-only names', () {
    expect(DisplayName.validationError(''), isNotNull);
    expect(DisplayName.validationError('   '), isNotNull);
  });

  test('rejects too-short and too-long names', () {
    expect(DisplayName.validationError('A'), isNotNull);
    expect(DisplayName.validationError('A' * 51), isNotNull);
  });

  test('rejects control characters and digit-only input', () {
    expect(DisplayName.validationError('Ada\u0007Khan'), isNotNull);
    expect(DisplayName.validationError('12'), isNotNull);
  });

  test('accepts a valid two-letter name', () {
    expect(DisplayName.validationError('Li'), isNull);
    expect(DisplayName.normalize('Li'), 'Li');
  });
}
