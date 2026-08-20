/// Pakistan mobile phone helpers (Ora is Pakistan-only for MVP).
///
/// Valid E.164 form: `+92` + exactly **10** digits starting with **3**
/// Example: `+923001234567`
///
/// Local forms like `03001234567` are normalized to E.164 when possible.
class PakistanPhoneNumber {
  const PakistanPhoneNumber._();

  static final RegExp _e164Mobile = RegExp(r'^\+923\d{9}$');

  /// Digits after country code for a valid PK mobile (no leading 0).
  static const int nationalMobileLength = 10;

  /// Full E.164 length including `+` (`+923XXXXXXXXX`).
  static const int e164Length = 13;

  /// Returns normalized E.164 or `null` if invalid.
  static String? normalize(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) return null;

    String candidate = cleaned;
    if (candidate.startsWith('0092')) {
      candidate = '+${candidate.substring(2)}';
    } else if (candidate.startsWith('92') && !candidate.startsWith('+')) {
      candidate = '+$candidate';
    } else if (candidate.startsWith('0') && candidate.length == 11) {
      // 03XXXXXXXXX → +923XXXXXXXXX
      candidate = '+92${candidate.substring(1)}';
    }

    if (!_e164Mobile.hasMatch(candidate)) return null;
    return candidate;
  }

  static bool isValid(String raw) => normalize(raw) != null;

  static String? validationError(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) {
      return 'Please enter your phone number';
    }
    if (normalize(cleaned) != null) return null;

    if (!cleaned.startsWith('+') &&
        !cleaned.startsWith('0') &&
        !cleaned.startsWith('92')) {
      return 'Use a Pakistan mobile number (+92… or 03…)';
    }

    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    // After stripping non-digits: 923XXXXXXXXX (12) or 03XXXXXXXXX (11)
    if (digitsOnly.startsWith('92') && digitsOnly.length != 12) {
      return 'Pakistan mobiles need exactly 10 digits after +92';
    }
    if (digitsOnly.startsWith('0') && digitsOnly.length != 11) {
      return 'Enter 11 digits starting with 03 (e.g. 03001234567)';
    }
    if (digitsOnly.startsWith('92') &&
        digitsOnly.length == 12 &&
        !digitsOnly.startsWith('923')) {
      return 'Pakistan mobile numbers must start with 3 after +92';
    }
    return 'Enter a valid Pakistan mobile (+923001234567)';
  }
}
