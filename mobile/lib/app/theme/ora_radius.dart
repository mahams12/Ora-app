/// Corner radii aligned with the Ora HTML prototype.
class OraRadius {
  OraRadius._();

  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 18.0;
  static const xxl = 26.0;
  static const pill = 999.0;

  /// Semantic roles
  static const card = xl; // 18
  static const button = lg; // 16
  static const input = md; // 14
  static const sheet = xxl; // 26
  static const chip = sm; // 12
  static const avatar = pill;
  static const modal = xl;

  // Legacy aliases used by older call sites expecting sm/md/lg/xl numbers.
  // sm was 8 → now xs; callers using OraRadius.sm for 8px should migrate to xs.
  // Kept numeric progression for Material theme bridging:
  // Prefer semantic: card/button/input/sheet.
}
