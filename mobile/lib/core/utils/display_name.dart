/// Passenger display-name rules (must match auth-service `display_name.ts`).
///
/// Server remains authoritative; this is fail-fast UX only.
class DisplayName {
  DisplayName._();

  static const minLength = 2;
  static const maxLength = 50;

  static final _controlChars = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
  static final _letters = RegExp(r'\p{L}', unicode: true);

  /// Returns a normalized name, or a user-facing error string.
  static String? validationError(String raw) {
    try {
      normalize(raw);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  static String normalize(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      throw const FormatException('Please enter your name.');
    }
    if (_controlChars.hasMatch(normalized)) {
      throw const FormatException('Name contains invalid characters.');
    }
    if (normalized.length < minLength) {
      throw const FormatException('Name must be at least 2 characters.');
    }
    if (normalized.length > maxLength) {
      throw const FormatException('Name must be at most 50 characters.');
    }
    final letterCount = _letters.allMatches(normalized).length;
    if (letterCount < minLength) {
      throw const FormatException('Name must contain at least two letters.');
    }
    return normalized;
  }
}
