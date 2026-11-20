import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Saves the PNG bytes captured via `binding.takeScreenshot` in
/// integration_test/driver_screenshots_test.dart to
/// test_outputs/driver_shots/<name>.png on the host.
Future<void> _saveShots(Map<String, dynamic>? data) async {
  final dir = Directory('test_outputs/driver_shots');
  await dir.create(recursive: true);
  final shots = data?['screenshots'] as List<dynamic>? ?? const [];
  for (final shot in shots) {
    final name = shot['screenshotName'] as String;
    final bytes = (shot['bytes'] as List<dynamic>).cast<int>();
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
    stdout.writeln('saved ${dir.path}/$name.png (${bytes.length} bytes)');
  }
}

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: _saveShots,
    writeResponseOnFailure: true,
  );
}
