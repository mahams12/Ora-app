import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/presentation/utils/driver_marker_interpolator.dart';

void main() {
  final t0 = DateTime(2026, 1, 1);
  var now = t0;
  void advance(Duration d) => now = now.add(d);

  DriverMarkerInterpolator make() => DriverMarkerInterpolator(
        segmentDuration: const Duration(milliseconds: 700),
        snapDistanceMeters: 150,
        minMoveMeters: 1.5,
        now: () => now,
      );

  setUp(() {
    now = t0;
  });

  test('first fix snaps immediately (no segment)', () {
    final i = make();
    expect(i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1), isTrue);
    expect(i.isAnimating, isFalse);
    final r = i.rendered()!;
    expect(r.lat, 31.5);
    expect(r.lng, 74.3);
  });

  test('second nearby fix starts a segment and renders in between', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1);

    // ~50 m east — under the snap threshold.
    i.onFix(lat: 31.5, lng: 74.3005, streamKey: 's1', seq: 2);
    expect(i.isAnimating, isTrue);

    advance(const Duration(milliseconds: 350));
    final mid = i.rendered()!;
    expect(mid.lat, closeTo(31.5, 1e-9));
    expect(mid.lng, greaterThan(74.3));
    expect(mid.lng, lessThan(74.3005));

    advance(const Duration(milliseconds: 350));
    final done = i.rendered()!;
    expect(done.lng, closeTo(74.3005, 1e-9));
    expect(i.isAnimating, isFalse);
  });

  test('large discontinuity snaps instead of animating', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1);
    // ~2 km away — teleport, not a glide.
    i.onFix(lat: 31.52, lng: 74.3, streamKey: 's1', seq: 2);
    expect(i.isAnimating, isFalse);
    expect(i.rendered()!.lat, 31.52);
  });

  test('sub-jitter fix keeps existing target (no segment churn)', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1);
    // ~0.5 m move — below jitter floor.
    i.onFix(lat: 31.500005, lng: 74.3, streamKey: 's1', seq: 2);
    expect(i.isAnimating, isFalse);
    expect(i.rendered()!.lat, 31.5);
  });

  test('out-of-order and duplicate seq are ignored', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 5);
    // Older seq for a different position must not move the marker.
    i.onFix(lat: 31.9, lng: 74.9, streamKey: 's1', seq: 3);
    expect(i.isAnimating, isFalse);
    expect(i.rendered()!.lat, 31.5);
    i.onFix(lat: 31.9, lng: 74.9, streamKey: 's1', seq: 5);
    expect(i.rendered()!.lat, 31.5);
  });

  test('stream restart (new streamKey) snaps to newest fix', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 9);
    // New stream starts seq at 1 — must not be discarded as "old".
    i.onFix(lat: 31.51, lng: 74.31, streamKey: 's2', seq: 1);
    expect(i.isAnimating, isFalse);
    expect(i.rendered()!.lat, 31.51);
    expect(i.rendered()!.lng, 74.31);
  });

  test('reset clears state so the next fix snaps fresh', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1);
    i.onFix(lat: 31.5, lng: 74.3005, streamKey: 's1', seq: 2);
    i.reset();
    expect(i.isAnimating, isFalse);
    expect(i.rendered(), isNull);
    i.onFix(lat: 31.9, lng: 74.9, streamKey: 's1', seq: 3);
    expect(i.isAnimating, isFalse);
    expect(i.rendered()!.lat, 31.9);
  });

  test('non-finite coordinates are rejected', () {
    final i = make();
    expect(
      i.onFix(lat: double.nan, lng: 74.3, streamKey: 's1', seq: 1),
      isFalse,
    );
    expect(i.rendered(), isNull);
    expect(
      i.onFix(
          lat: 31.5, lng: double.infinity, streamKey: 's1', seq: 1),
      isFalse,
    );
    expect(i.rendered(), isNull);
  });

  test('rendered position never leaves the authoritative segment', () {
    final i = make();
    i.onFix(lat: 31.5, lng: 74.3, streamKey: 's1', seq: 1);
    i.onFix(lat: 31.501, lng: 74.3005, streamKey: 's1', seq: 2);
    for (var k = 0; k <= 10; k++) {
      final r = i.rendered()!;
      expect(r.lat, inInclusiveRange(31.5, 31.501));
      expect(r.lng, inInclusiveRange(74.3, 74.3005));
      advance(const Duration(milliseconds: 100));
    }
  });
}
