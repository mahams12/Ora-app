import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../maps/preview/map_preview_config.dart';
import '../../../maps/preview/map_preview_style_loader.dart';
import '../../domain/location/driver_location_fix.dart';
import '../../domain/location/driver_location_source.dart';
import '../view_models/driver_availability_view_model.dart';
import '../../../../app/di/providers.dart';

/// Driver home map — live MapLibre surface centered on the driver's own GPS
/// position. While online it consumes the presence publisher's fix stream (no
/// second GPS watch); offline it runs a bounded one-shot acquisition and stops
/// the GPS again. Soft-fails to an honest shell when tiles or location are
/// unavailable — never shows fabricated zones or positions.
class DriverHomeMap extends ConsumerStatefulWidget {
  const DriverHomeMap({
    super.key,
    this.height = 150,
    this.enableMaps = true,
  });

  final double height;

  /// Test hook — when false, never mounts [MapLibreMap] or a GPS watch.
  final bool enableMaps;

  @override
  ConsumerState<DriverHomeMap> createState() => _DriverHomeMapState();
}

class _DriverHomeMapState extends ConsumerState<DriverHomeMap> {
  static const _fallbackCamera = CameraPosition(
    target: LatLng(31.5204, 74.3587),
    zoom: 10.5,
  );
  static const _positionZoom = 15.0;
  static const _recentreMinMeters = 25.0;
  static const _acquireTimeout = Duration(seconds: 12);

  MapLibreMapController? _controller;
  String? _styleJson;
  String? _styleError;
  bool _mapReady = false;

  DriverLocationFix? _snapshotFix;
  bool _acquiring = false;
  bool _acquireFailed = false;
  StreamSubscription<DriverLocationReading>? _acquireSub;
  Timer? _acquireTimer;
  Circle? _positionCircle;
  LatLng? _lastCameraTarget;

  bool get _canShowMap =>
      widget.enableMaps && _styleJson != null && _styleJson!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!widget.enableMaps) return;
    _prepareStyle();
    _acquireSnapshot();
  }

  @override
  void dispose() {
    _acquireTimer?.cancel();
    _acquireSub?.cancel();
    _controller = null;
    super.dispose();
  }

  Future<void> _prepareStyle() async {
    final result = await MapPreviewStyleLoader.load();
    if (!mounted) return;
    setState(() {
      if (result.isOk) {
        _styleJson = result.styleJson;
        _styleError = null;
      } else {
        _styleJson = null;
        _styleError = result.errorMessage;
      }
    });
  }

  /// Offline path — acquires one fix then stops the watch. The online path is
  /// fed by [driverPresenceLatestFixProvider] so no second watch runs then.
  void _acquireSnapshot() {
    if (_acquiring) return;
    if (ref.read(driverPresenceLatestFixProvider) != null) return;
    _acquiring = true;
    final source = ref.read(driverLocationSourceProvider);
    _acquireSub = source.watch().listen((reading) {
      if (!mounted) return;
      if (reading is DriverLocationFixReading) {
        _stopAcquire();
        setState(() {
          _snapshotFix = reading.fix;
          _acquireFailed = false;
        });
      } else if (reading is DriverLocationFailureReading) {
        _stopAcquire();
        setState(() => _acquireFailed = true);
      }
    });
    _acquireTimer = Timer(_acquireTimeout, () {
      if (!mounted || !_acquiring) return;
      _stopAcquire();
      if (_snapshotFix == null) {
        setState(() => _acquireFailed = true);
      }
    });
  }

  void _stopAcquire() {
    _acquireSub?.cancel();
    _acquireSub = null;
    _acquireTimer?.cancel();
    _acquireTimer = null;
    _acquiring = false;
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    try {
      await controller.setCustomHeaders(
        {HttpHeaders.userAgentHeader: MapPreviewConfig.mapTilerUserAgent},
        const [r'https://api\.maptiler\.com/.*'],
      );
    } catch (_) {}
  }

  Future<void> _onStyleLoaded() async {
    _mapReady = true;
    final fix = _effectiveFix;
    if (fix != null) await _applyFix(fix, jump: true);
  }

  DriverLocationFix? get _effectiveFix =>
      ref.read(driverPresenceLatestFixProvider) ?? _snapshotFix;

  Future<void> _applyFix(DriverLocationFix fix, {bool jump = false}) async {
    final c = _controller;
    if (c == null || !_mapReady || !mounted) return;
    final target = LatLng(fix.latitude, fix.longitude);
    try {
      final circle = _positionCircle;
      if (circle == null) {
        _positionCircle = await c.addCircle(
          CircleOptions(
            geometry: target,
            circleRadius: 7,
            circleColor:
                '#${(OraColors.tealBright.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
            circleOpacity: 1,
            circleStrokeWidth: 2.5,
            circleStrokeColor: '#FFFFFF',
          ),
        );
      } else {
        await c.updateCircle(
          circle,
          CircleOptions(geometry: target),
        );
      }
      final last = _lastCameraTarget;
      final moved = last == null ||
          _distanceMeters(last, target) > _recentreMinMeters;
      if (moved || jump) {
        _lastCameraTarget = target;
        final update = jump || last == null
            ? CameraUpdate.newCameraPosition(
                CameraPosition(target: target, zoom: _positionZoom),
              )
            : CameraUpdate.newLatLng(target);
        await c.animateCamera(update);
      }
    } catch (_) {}
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  @override
  Widget build(BuildContext context) {
    final presenceFix = ref.watch(driverPresenceLatestFixProvider);
    final isOnline = ref.watch(
      driverAvailabilityProvider.select((s) => s.isOnline),
    );
    final fix = presenceFix ?? _snapshotFix;

    if (presenceFix != null) {
      if (_acquiring) _stopAcquire();
      if (_mapReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyFix(presenceFix);
        });
      }
    } else if (fix != null && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFix(fix);
      });
    }

    final statusLabel = switch ((fix != null, isOnline, _acquireFailed)) {
      (true, true, _) => 'Online · position live',
      (true, false, _) => 'Your position',
      (false, _, true) => 'Location unavailable',
      _ => 'Locating…',
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(OraRadius.card),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_canShowMap)
              MapLibreMap(
                styleString: _styleJson!,
                initialCameraPosition: _fallbackCamera,
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: _onStyleLoaded,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: false,
                logoEnabled: false,
                attributionButtonPosition:
                    AttributionButtonPosition.bottomRight,
                attributionButtonMargins: const math.Point(12, 8),
                foregroundLoadColor: OraColors.navy,
              )
            else
              _MapShellFallback(
                message: _styleError ??
                    (widget.enableMaps
                        ? 'Loading map…'
                        : 'Map preview unavailable'),
              ),
            Positioned(
              left: OraSpacing.sm,
              bottom: OraSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE612182B),
                  borderRadius: BorderRadius.circular(OraRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: fix != null && isOnline
                            ? OraColors.tealBright
                            : OraColors.slateMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: OraTypography.caption(Colors.white).copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapShellFallback extends StatelessWidget {
  const _MapShellFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OraColors.navyElevated, OraColors.surfaceStrong],
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: OraTypography.caption(OraColors.textMuted),
        ),
      ),
    );
  }
}
