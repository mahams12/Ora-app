import 'dart:math' as math;

/// Display-only driver marker interpolator (MAP-RT smoothness).
///
/// Server/RTDB fixes stay authoritative — this class only produces a rendered
/// position for the map marker. It never feeds back into location publishing,
/// ride state, camera identity, or freshness.
///
/// Semantics:
/// - [onFix] starts a short linear segment from the currently rendered position
///   to the new fix. Callers drive time via [rendered] (e.g. a Ticker).
/// - Snaps instantly (no segment) on: first fix, stream restart ([streamKey]
///   change), jumps beyond [snapDistanceMeters], or sub-jitter moves below
///   [minMoveMeters].
/// - [reset] clears everything — next fix snaps. Use on stale/expired data,
///   ride-state transitions, recenter/reinit, or screen detach.
class DriverMarkerInterpolator {
  DriverMarkerInterpolator({
    Duration segmentDuration = const Duration(milliseconds: 700),
    double snapDistanceMeters = 150,
    double minMoveMeters = 1.5,
    DateTime Function()? now,
  })  : _segmentDuration = segmentDuration,
        _snapDistanceMeters = snapDistanceMeters,
        _minMoveMeters = minMoveMeters,
        _now = now ?? DateTime.now;

  final Duration _segmentDuration;
  final double _snapDistanceMeters;
  final double _minMoveMeters;
  final DateTime Function() _now;

  ({double lat, double lng})? _rendered;
  ({double lat, double lng})? _target;
  ({double lat, double lng})? _from;
  DateTime? _segmentStart;
  String? _streamKey;
  int _lastSeq = -1;

  bool get isAnimating => _from != null;

  /// Latest rendered position, or null when nothing has been fed.
  ({double lat, double lng})? rendered() {
    _advance();
    return _rendered;
  }

  /// Feed a new authoritative fix. Returns whether the rendered position
  /// changed immediately (snap) or a segment is now running — callers use
  /// [isAnimating] to decide whether to keep a ticker alive.
  bool onFix({
    required double lat,
    required double lng,
    required String streamKey,
    required int seq,
  }) {
    if (!lat.isFinite || !lng.isFinite) return false;
    final fix = (lat: lat, lng: lng);
    final renderedNow = rendered();
    final target = _target;

    // Stream restart or out-of-order seq: snap to newest.
    final streamChanged = _streamKey != null && streamKey != _streamKey;
    if (streamChanged) {
      _streamKey = streamKey;
      _lastSeq = seq;
      return _snap(fix);
    }
    _streamKey ??= streamKey;

    // Older/duplicate fix on same stream — ignore (authoritative seq).
    if (seq <= _lastSeq) return renderedNow == null;
    _lastSeq = seq;

    if (renderedNow == null) {
      return _snap(fix);
    }

    final dist = _distanceMeters(renderedNow, fix);
    if (dist >= _snapDistanceMeters) {
      return _snap(fix);
    }
    if (target != null && _distanceMeters(fix, target) < _minMoveMeters) {
      // Sub-jitter: keep aiming at the same spot — no new segment, no snap.
      return false;
    }

    _from = renderedNow;
    _target = fix;
    _segmentStart = _now();
    _rendered = renderedNow;
    return true;
  }

  /// Clear rendered + segment state; next fix snaps.
  void reset() {
    _rendered = null;
    _target = null;
    _from = null;
    _segmentStart = null;
    _streamKey = null;
    _lastSeq = -1;
  }

  bool _snap(({double lat, double lng}) fix) {
    _rendered = fix;
    _target = fix;
    _from = null;
    _segmentStart = null;
    return true;
  }

  void _advance() {
    final from = _from;
    final to = _target;
    final start = _segmentStart;
    if (from == null || to == null || start == null) return;
    final elapsed = _now().difference(start).inMilliseconds;
    final total = _segmentDuration.inMilliseconds;
    if (total <= 0 || elapsed >= total) {
      _rendered = to;
      _from = null;
      _segmentStart = null;
      return;
    }
    final t = elapsed / total;
    _rendered = (
      lat: from.lat + (to.lat - from.lat) * t,
      lng: from.lng + (to.lng - from.lng) * t,
    );
  }

  /// Haversine meters — duplicated from the publisher's formula intentionally:
  /// this class must stay dependency-free (pure, unit-testable).
  static double _distanceMeters(
    ({double lat, double lng}) a,
    ({double lat, double lng}) b,
  ) {
    const earthRadiusM = 6371000.0;
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lng - a.lng) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusM * math.asin(math.sqrt(h));
  }
}
