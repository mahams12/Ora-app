import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/widgets/ora_floaty.dart';

void main() {
  setUp(() => OraFloaty.debugSkipRepeat = false);
  tearDown(() => OraFloaty.debugSkipRepeat = true);

  testWidgets('OraFloaty moves its child continuously', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OraFloaty(
          child: SizedBox(key: Key('k'), width: 50, height: 50),
        ),
      ),
    ));
    final samples = <Offset>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      samples.add(tester.getTopLeft(find.byKey(const Key('k'))));
    }
    expect(samples.toSet().length, greaterThan(2));
  });
}
