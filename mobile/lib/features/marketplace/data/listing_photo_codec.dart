import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Compresses a picked photo to a JPEG data URL the backend accepts
/// (photos[] entries, bounded total per listing).
///
/// The backend stores images inline in the listing document — each photo is
/// downscaled to ≤1280px and quality-stepped until it fits under
/// [_targetBytes] so 6 photos stay well inside the 600KB document budget.
const _targetBytes = 120 * 1024;
const _maxEdge = 1280;

Future<String> encodeListingPhoto(XFile file) async {
  final bytes = await File(file.path).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image file.');
  }
  var resized = decoded;
  if (decoded.width > _maxEdge || decoded.height > _maxEdge) {
    resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? _maxEdge : null,
      height: decoded.height > decoded.width ? _maxEdge : null,
    );
  }
  for (final quality in [72, 60, 48, 36]) {
    final jpeg = img.encodeJpg(resized, quality: quality);
    if (jpeg.length <= _targetBytes || quality == 36) {
      return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    }
  }
  // Unreachable — loop always returns.
  throw const FormatException('Could not compress image.');
}

Future<List<String>> encodeListingPhotos(List<XFile> files) async {
  final out = <String>[];
  for (final file in files.take(6)) {
    out.add(await encodeListingPhoto(file));
  }
  return out;
}
