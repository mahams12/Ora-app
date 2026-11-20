import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../maps/preview/map_preview_config.dart';
import '../../../maps/preview/map_preview_style_loader.dart';
import '../../domain/entities/ride.dart';
import '../../domain/location/trip_location_freshness.dart';
import '../location/trip_location_session.dart';
import '../utils/active_ride_map_camera_policy.dart';
import '../utils/active_ride_map_progression_policy.dart';
import '../utils/driver_marker_interpolator.dart';

/// Active-ride MapLibre map — pickup/destination from HTTP [Ride], driver
/// from RTDB. Rendered through the same Ora dark style + tile provider
/// (MapTiler → OpenFreeMap $0 fallback) as [RideMapPreview].
///
/// MAP-2B: camera reframes only on semantic [ActiveRideMapCameraPolicy.fitIdentity]
/// changes — never on every RTDB tick. Soft-fails. Never gates cancel/close.
///
/// MAP-2C: display-only progression guides (geometric segments — not road routes,
/// navigation, or ETA). Driver ticks update guide endpoints without camera moves.
///
/// MAP-3: user-gesture camera ownership — after the passenger pans/zooms/rotates/
/// tilts, automatic identity-driven [animateCamera] is suppressed until Recenter.
/// Not follow mode. Not continuous chase.
class ActiveRideMap extends StatefulWidget {
  const ActiveRideMap({
    super.key,
    required this.ride,
    required this.locationSession,
    this.height = 200,
    this.enableMaps = true,
    this.onAnimateCamera,
    this.showRecenter = true,
    this.onProgressionSegments,
    this.onUserOwnsCameraChanged,
    this.userCameraMoveEpoch = 0,
  });

  final Ride ride;
  final TripLocationSessionState locationSession;

  /// Slightly taller than MAP-2A 168px for readable phase framing on SM-A325F.
  final double height;

  /// Test hook — when false, never mounts [MapLibreMap].
  final bool enableMaps;

  /// Test / instrumentation hook. When set, invoked instead of platform
  /// [MapLibreMapController.animateCamera]. Also enables camera scheduling
  /// without a platform controller (for widget tests with [enableMaps] false).
  final Future<void> Function(CameraUpdate update)? onAnimateCamera;

  /// One-shot recenter control — clears last applied identity and re-runs
  /// policy fit once. Not continuous follow mode.
  final bool showRecenter;

  /// Test hook — receives MAP-2C guide segments after each build (no camera).
  final void Function(List<ActiveRideMapGuideSegment> segments)?
  onProgressionSegments;

  /// Test / instrumentation hook — fired when MAP-3 ownership latches change.
  final ValueChanged<bool>? onUserOwnsCameraChanged;

  /// Test hook — bumping this value simulates a user camera move without
  /// mounting a platform [MapLibreMap] (`enableMaps: false`).
  final int userCameraMoveEpoch;

  @override
  State<ActiveRideMap> createState() => _ActiveRideMapState();
}

class _ActiveRideMapState extends State<ActiveRideMap>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _controller;

  String? _styleJson;
  String? _styleError;
  bool _styleReady = false;

  /// Last successfully applied camera identity (guards against rebuild thrash).
  String? _fittedIdentity;

  /// MAP-RT: display-only marker smoothing. RTDB coords stay authoritative;
  /// the interpolator only renders a position between accepted fixes.
  final DriverMarkerInterpolator _interpolator = DriverMarkerInterpolator();
  Ticker? _markerTicker;
  ({double lat, double lng})? _renderedDriver;

  /// In-flight fit target — prevents duplicate post-frame animate for same id.
  String? _pendingIdentity;

  /// MAP-3: passenger owns framing after a genuine user camera gesture.
  bool _userOwnsCamera = false;

  /// MAP-3: true while our own [animateCamera] / test hook animate is in
  /// flight (cleared on [onCameraIdle] so trailing platform camera events
  /// cannot latch [_userOwnsCamera]).
  bool _programmaticCameraMove = false;

  /// Overlay sync coalescing — interpolator ticks at frame rate; pushing a
  /// GeoJSON diff every tick would spam the platform channel. Cap source
  /// updates at ~30fps, always flushing the final rendered position.
  bool _overlaySyncQueued = false;
  int _lastOverlayPushMs = 0;
  bool _overlayDirty = false;

  static const String _sourceId = 'ora_active_ride';
  static const String _guideLayerId = 'ora_active_ride_guides';
  static const String _poiLayerId = 'ora_active_ride_poi';
  static const String _driverLayerId = 'ora_active_ride_driver';
  static const String _pickupImageId = 'ora_active_pickup';
  static const String _destImageId = 'ora_active_dest';
  static const String _driverImageId = 'ora_active_driver';
  static const int _minOverlayPushIntervalMs = 33;

  LatLng? get _pickup => _toLatLng(widget.ride.pickup);
  LatLng? get _destination => _toLatLng(widget.ride.destination);

  /// Driver for camera + markers — only when MAP-2A freshness says show marker.
  LatLng? get _driverLatLng {
    final session = widget.locationSession;
    final latest = session.latest;
    if (latest == null || !latest.hasValidCoordinates) return null;
    if (!const TripLocationFreshnessPolicy().shouldShowDriverMarker(
      session.freshness,
    )) {
      return null;
    }
    return LatLng(latest.lat, latest.lng);
  }

  String get _currentIdentity => ActiveRideMapCameraPolicy.fitIdentity(
    rideState: widget.ride.state,
    pickup: _pickup,
    destination: _destination,
    driver: _driverLatLng,
  );

  bool get _cameraReady =>
      (_controller != null && _styleReady) ||
      widget.onAnimateCamera != null;

  @override
  void initState() {
    super.initState();
    if (widget.enableMaps) {
      _prepareStyle();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _feedLocationFix();
        if (widget.onAnimateCamera != null) _scheduleCameraFit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ActiveRideMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // MAP-3 test hook — epoch bump == user camera gesture (not programmatic).
    if (widget.userCameraMoveEpoch != oldWidget.userCameraMoveEpoch) {
      _onUserCameraMoveStarted();
    }

    if (oldWidget.enableMaps != widget.enableMaps && widget.enableMaps) {
      _prepareStyle();
    }

    // Ride-state transition — restart interpolation so the next fix snaps.
    if (widget.ride.state != oldWidget.ride.state) {
      _interpolator.reset();
    }
    _feedLocationFix();

    final nextId = _currentIdentity;
    final prevId = ActiveRideMapCameraPolicy.fitIdentity(
      rideState: oldWidget.ride.state,
      pickup: _toLatLng(oldWidget.ride.pickup),
      destination: _toLatLng(oldWidget.ride.destination),
      driver: _driverFromSession(oldWidget.locationSession),
    );
    // Semantic identity change only — not every driver coordinate tick.
    if (nextId != prevId) {
      _fittedIdentity = null;
      _pendingIdentity = null;
      _scheduleCameraFit();
    }
  }

  @override
  void dispose() {
    _markerTicker?.dispose();
    _markerTicker = null;
    _controller = null;
    super.dispose();
  }

  // ── Style ──────────────────────────────────────────────────────────────

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

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    try {
      await controller.setCustomHeaders(
        {HttpHeaders.userAgentHeader: MapPreviewConfig.mapTilerUserAgent},
        const [r'https://api\.maptiler\.com/.*'],
      );
    } catch (_) {
      // Soft — global setHttpHeaders from style loader still applies.
    }
  }

  /// Registers marker icons, the GeoJSON source, and guide/point layers.
  /// All overlays update through a single [setGeoJsonSource] diff — no
  /// annotation churn during interpolation.
  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    final c = _controller;
    if (c == null) return;
    try {
      await _addImage(c, _pickupImageId, MapPreviewConfig.pickupMarkerAsset);
      await _addImage(c, _destImageId, MapPreviewConfig.destinationMarkerAsset);
      final driverBytes = await _buildDriverPuckBytes();
      if (driverBytes != null) {
        try {
          await c.addImage(_driverImageId, driverBytes);
        } catch (_) {}
      }

      await c.addGeoJsonSource(_sourceId, _buildGeoJson());

      await c.addLineLayer(
        _sourceId,
        _guideLayerId,
        const LineLayerProperties(
          lineColor: '#8B93AD',
          lineWidth: 3,
          lineOpacity: 0.9,
          lineDasharray: [2.5, 1.8],
          lineCap: 'round',
        ),
        filter: [
          '==',
          ['geometry-type'],
          'LineString',
        ],
      );

      await c.addSymbolLayer(
        _sourceId,
        _poiLayerId,
        const SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 0.9,
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          textField: ['get', 'label'],
          textSize: 11,
          textFont: ['Noto Sans Regular'],
          textAnchor: 'top',
          textOffset: [0, 0.2],
          textColor: '#B9C2DD',
          textHaloColor: '#12182B',
          textHaloWidth: 1.5,
          textAllowOverlap: true,
        ),
        filter: [
          'in',
          ['get', 'kind'],
          ['literal', ['pickup', 'destination']],
        ],
      );

      await c.addSymbolLayer(
        _sourceId,
        _driverLayerId,
        const SymbolLayerProperties(
          iconImage: _driverImageId,
          iconSize: 0.55,
          iconAnchor: 'center',
          iconRotate: ['get', 'rot'],
          iconRotationAlignment: 'map',
          iconOpacity: ['get', 'opa'],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          textField: 'Driver',
          textSize: 11,
          textFont: ['Noto Sans Regular'],
          textAnchor: 'top',
          textOffset: [0, 1.4],
          textColor: '#9FE8C8',
          textHaloColor: '#12182B',
          textHaloWidth: 1.5,
          textOpacity: ['get', 'opa'],
        ),
        filter: [
          '==',
          ['get', 'kind'],
          'driver',
        ],
      );

      _scheduleCameraFit();
      _scheduleOverlaySync();
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('ActiveRideMap overlay setup soft-failed: $error');
        debugPrint('$stack');
      }
    }
  }

  Future<void> _addImage(
    MapLibreMapController c,
    String name,
    String asset,
  ) async {
    try {
      final data = await rootBundle.load(asset);
      await c.addImage(name, data.buffer.asUint8List());
    } catch (_) {
      // Image may already exist after style reload — ignore.
    }
  }

  /// Driver puck — white ring + green disc + north-facing heading wedge.
  /// Rendered once per style load; rotated by icon-rotate (never invents
  /// motion — rotation comes from the authoritative fix's heading).
  static Future<Uint8List?> _buildDriverPuckBytes() async {
    try {
      const size = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const center = Offset(size / 2, size / 2);

      canvas.drawCircle(
        center,
        22,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        18,
        Paint()
          ..color = const Color(0xFF2ECC71)
          ..style = PaintingStyle.fill,
      );
      final wedge = Path()
        ..moveTo(center.dx, center.dy - 13)
        ..lineTo(center.dx - 6.5, center.dy + 2)
        ..lineTo(center.dx + 6.5, center.dy + 2)
        ..close();
      canvas.drawPath(wedge, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        4,
        Paint()..color = Colors.white,
      );

      final image = await recorder.endRecording().toImage(
        size.round(),
        size.round(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ── Overlays ───────────────────────────────────────────────────────────

  List<ActiveRideMapGuideSegment> _guideSegments() {
    return ActiveRideMapProgressionPolicy.segments(
      rideState: widget.ride.state,
      pickup: _pickup,
      destination: _destination,
      driver: _displayDriver,
    );
  }

  Map<String, Object?> _buildGeoJson() {
    final features = <Map<String, Object?>>[];

    final pickup = _pickup;
    if (pickup != null) {
      features.add(
        _pointFeature(
          kind: 'pickup',
          icon: _pickupImageId,
          label: 'Pickup',
          point: pickup,
        ),
      );
    }
    final destination = _destination;
    if (destination != null) {
      features.add(
        _pointFeature(
          kind: 'destination',
          icon: _destImageId,
          label: 'Destination',
          point: destination,
        ),
      );
    }

    final driver = _displayDriver;
    final latest = widget.locationSession.latest;
    if (driver != null && latest != null) {
      final alpha = switch (widget.locationSession.freshness) {
        TripLocationFreshness.fresh => 1.0,
        TripLocationFreshness.stale => 0.75,
        TripLocationFreshness.degraded => 0.55,
        TripLocationFreshness.expired || TripLocationFreshness.missing => 0.0,
      };
      if (alpha > 0) {
        features.add(
          _pointFeature(
            kind: 'driver',
            icon: _driverImageId,
            label: 'Driver',
            point: driver,
            opacity: alpha,
            rotation: latest.heading.isFinite ? latest.heading : 0,
          ),
        );
      }
    }

    for (final segment in _guideSegments()) {
      features.add(<String, Object?>{
        'type': 'Feature',
        'properties': <String, Object?>{'kind': segment.kind.name},
        'geometry': <String, Object?>{
          'type': 'LineString',
          'coordinates': [
            [segment.start.longitude, segment.start.latitude],
            [segment.end.longitude, segment.end.latitude],
          ],
        },
      });
    }

    return <String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    };
  }

  static Map<String, Object?> _pointFeature({
    required String kind,
    required String icon,
    required String label,
    required LatLng point,
    double opacity = 1,
    double rotation = 0,
  }) {
    return <String, Object?>{
      'type': 'Feature',
      'properties': <String, Object?>{
        'kind': kind,
        'icon': icon,
        'label': label,
        'opa': opacity,
        'rot': rotation,
      },
      'geometry': <String, Object?>{
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    };
  }

  /// Coalesced overlay push — at most ~30fps, always flushing final state.
  void _scheduleOverlaySync() {
    if (!_styleReady || _controller == null) return;
    if (_overlaySyncQueued) {
      _overlayDirty = true;
      return;
    }
    _overlaySyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlaySyncQueued = false;
      if (!mounted) return;
      _pushOverlays();
    });
  }

  Future<void> _pushOverlays() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastOverlayPushMs < _minOverlayPushIntervalMs) {
      if (_overlayDirty) return;
      _overlayDirty = true;
      Future<void>.delayed(
        const Duration(milliseconds: _minOverlayPushIntervalMs),
        () {
          if (mounted && _overlayDirty) {
            _overlayDirty = false;
            _pushOverlays();
          }
        },
      );
      return;
    }
    _overlayDirty = false;
    _lastOverlayPushMs = now;
    final c = _controller;
    if (c == null || !_styleReady || !mounted) return;
    try {
      await c.setGeoJsonSource(_sourceId, _buildGeoJson());
    } catch (_) {
      // Soft — overlay stays at last good state.
    }
  }

  // ── MAP-RT marker smoothing ────────────────────────────────────────────

  /// MAP-RT: feed the newest authoritative fix into the interpolator.
  /// Ineligible input (no fix, invalid coords, marker hidden by freshness)
  /// resets smoothing so the marker can't coast on stale data.
  void _feedLocationFix() {
    if (!mounted) return;
    final session = widget.locationSession;
    final latest = session.latest;
    final eligible =
        latest != null &&
        latest.hasValidCoordinates &&
        const TripLocationFreshnessPolicy().shouldShowDriverMarker(
          session.freshness,
        );
    if (!eligible) {
      if (_renderedDriver != null || _interpolator.isAnimating) {
        _interpolator.reset();
        _renderedDriver = null;
        _stopMarkerTicker();
        setState(() {});
        _scheduleOverlaySync();
      }
      return;
    }

    _interpolator.onFix(
      lat: latest.lat,
      lng: latest.lng,
      streamKey: latest.locationStreamId,
      seq: latest.locationSeq,
    );
    final rendered = _interpolator.rendered();
    if (rendered != null && rendered != _renderedDriver) {
      _renderedDriver = rendered;
      setState(() {});
      _scheduleOverlaySync();
    }
    if (_interpolator.isAnimating) {
      _ensureMarkerTicker();
    } else {
      _stopMarkerTicker();
    }
  }

  void _ensureMarkerTicker() {
    final ticker = _markerTicker ??= createTicker(_onMarkerTick);
    if (!ticker.isActive) {
      ticker.start();
    }
  }

  void _stopMarkerTicker() {
    final ticker = _markerTicker;
    if (ticker != null && ticker.isActive) {
      ticker.stop();
    }
  }

  void _onMarkerTick(Duration _) {
    if (!mounted) return;
    final rendered = _interpolator.rendered();
    if (rendered != null && rendered != _renderedDriver) {
      _renderedDriver = rendered;
      setState(() {});
      _scheduleOverlaySync();
    }
    if (!_interpolator.isAnimating) {
      _stopMarkerTicker();
    }
  }

  /// Displayed driver position — interpolated for the marker/guide only;
  /// camera policy still reads the authoritative fix via [_driverLatLng].
  LatLng? get _displayDriver {
    final r = _renderedDriver;
    if (r != null) return LatLng(r.lat, r.lng);
    return _driverLatLng;
  }

  // ── MAP-3 camera ownership ─────────────────────────────────────────────

  /// MAP-3 — genuine user gesture. MapLibre has no camera-move-started
  /// callback, so this latches on the first [onCameraMove] outside a
  /// programmatic animate window.
  void _onUserCameraMoveStarted() {
    if (_programmaticCameraMove) return;
    if (_userOwnsCamera) return;
    _userOwnsCamera = true;
    widget.onUserOwnsCameraChanged?.call(true);
  }

  void _releaseUserCameraOwnership() {
    if (!_userOwnsCamera) return;
    _userOwnsCamera = false;
    widget.onUserOwnsCameraChanged?.call(false);
  }

  void _onCameraMove(CameraPosition _) {
    _onUserCameraMoveStarted();
  }

  void _onCameraIdle() {
    // Camera settled — safe to accept user gestures again.
    _programmaticCameraMove = false;
  }

  void _onRecenter() {
    // Recenter: clear ownership, reset smoothing (next render snaps to the
    // authoritative fix), then one MAP-2B policy fit.
    _releaseUserCameraOwnership();
    _interpolator.reset();
    _feedLocationFix();
    _fittedIdentity = null;
    _pendingIdentity = null;
    _scheduleCameraFit();
  }

  // ── MAP-2B identity-driven camera fit ──────────────────────────────────

  void _scheduleCameraFit() {
    if (!_cameraReady) return;

    // MAP-3: while the user owns the camera, suppress automatic animateCamera.
    // Markers + MAP-2C guides still update via overlay sync. Recenter clears
    // ownership before calling this method.
    if (_userOwnsCamera) {
      _pendingIdentity = null;
      return;
    }

    final identity = _currentIdentity;
    if (_fittedIdentity == identity) return;
    if (_pendingIdentity == identity) return;

    final update = ActiveRideMapCameraPolicy.cameraUpdate(
      rideState: widget.ride.state,
      pickup: _pickup,
      destination: _destination,
      driver: _driverLatLng,
    );
    if (update == null) {
      _fittedIdentity = identity;
      _pendingIdentity = null;
      return;
    }

    _pendingIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Ownership may have latched between schedule and post-frame.
      if (_userOwnsCamera) {
        _pendingIdentity = null;
        return;
      }
      if (_fittedIdentity == identity) {
        _pendingIdentity = null;
        return;
      }
      // Identity may have moved again while waiting — only apply if still current.
      if (_currentIdentity != identity) {
        _pendingIdentity = null;
        _scheduleCameraFit();
        return;
      }
      try {
        await _performAnimate(update);
        if (mounted && !_userOwnsCamera && _currentIdentity == identity) {
          _fittedIdentity = identity;
        }
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint('ActiveRideMap camera fit soft-failed: $error');
          debugPrint('$stack');
        }
      } finally {
        if (_pendingIdentity == identity) {
          _pendingIdentity = null;
        }
      }
    });
  }

  Future<void> _performAnimate(CameraUpdate update) async {
    // Guard: platform onCameraMove fires for our own animateCamera — keep the
    // latch suppressed until the camera goes idle.
    _programmaticCameraMove = true;
    try {
      final hook = widget.onAnimateCamera;
      if (hook != null) {
        await hook(update);
        return;
      }
      final controller = _controller;
      if (controller == null) return;
      await controller.animateCamera(update);
    } finally {
      if (widget.onAnimateCamera != null) {
        // No platform stream in test-hook mode — clear immediately.
        _programmaticCameraMove = false;
      }
      // Platform mode: cleared by _onCameraIdle so trailing move events
      // emitted during the animation can't latch user ownership.
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  CameraPosition _initialCamera() {
    final pickup = _pickup;
    final destination = _destination;
    final driver = _driverLatLng;
    if (driver != null && pickup != null) {
      return CameraPosition(
        target: ActiveRideMapCameraPolicy.midpoint(driver, pickup),
        zoom: 12,
      );
    }
    if (pickup != null && destination != null) {
      return CameraPosition(
        target: ActiveRideMapCameraPolicy.midpoint(pickup, destination),
        zoom: 12,
      );
    }
    // Single-point frames open at the same 3D tilt as RideMapPreview for a
    // consistent look; identity-driven bounds fits flatten to 0° as usual.
    if (pickup != null) {
      return CameraPosition(
        target: pickup,
        zoom: ActiveRideMapCameraPolicy.singlePointZoom,
        tilt: MapPreviewConfig.threeDTilt,
      );
    }
    if (destination != null) {
      return CameraPosition(
        target: destination,
        zoom: ActiveRideMapCameraPolicy.singlePointZoom,
        tilt: MapPreviewConfig.threeDTilt,
      );
    }
    return ActiveRideMapCameraPolicy.idleCamera;
  }

  @override
  Widget build(BuildContext context) {
    final hasAnchors = _pickup != null || _destination != null;
    final showMap =
        widget.enableMaps &&
        hasAnchors &&
        _styleJson != null &&
        _styleJson!.isNotEmpty;
    final styleFailed = widget.enableMaps && _styleError != null;
    final status = widget.locationSession.statusMessage;
    final guides = _guideSegments();
    // Test hook only — never drives camera or side effects in production.
    widget.onProgressionSegments?.call(guides);

    final semanticsLabel = guides.isEmpty
        ? 'Active ride map'
        : 'Active ride map. ${guides.first.semanticsLabel}';

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(OraRadius.xxl),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showMap)
                MapLibreMap(
                  styleString: _styleJson!,
                  initialCameraPosition: _initialCamera(),
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                  // MAP-3: latch ownership on genuine user gestures only.
                  // Programmatic moves are filtered via [_programmaticCameraMove].
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                  trackCameraPosition: true,
                  compassEnabled: false,
                  rotateGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  logoEnabled: false,
                  attributionButtonPosition:
                      AttributionButtonPosition.bottomLeft,
                  foregroundLoadColor: OraColors.navy,
                )
              else if (!hasAnchors || styleFailed || widget.enableMaps == false)
                const _ActiveRideMapShell()
              else
                const ColoredBox(color: OraColors.navyElevated),
              Positioned(
                left: OraSpacing.sm,
                right: OraSpacing.sm,
                bottom: OraSpacing.sm,
                child: _StatusBanner(
                  rideState: widget.ride.state,
                  locationSession: widget.locationSession,
                  statusOverride: status,
                ),
              ),
              // Shown when the live map is up, or when camera scheduling is
              // available via [onAnimateCamera] (widget tests with enableMaps:false).
              if (widget.showRecenter &&
                  hasAnchors &&
                  (showMap || widget.onAnimateCamera != null))
                Positioned(
                  top: OraSpacing.sm,
                  right: OraSpacing.sm,
                  child: Material(
                    color: OraColors.surfaceElevated.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(OraRadius.lg),
                    child: IconButton(
                      tooltip: 'Recenter map',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      onPressed: _onRecenter,
                      icon: const Icon(
                        Icons.my_location_outlined,
                        size: 20,
                        color: OraColors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static LatLng? _toLatLng(LatLngPoint point) {
    if (!point.lat.isFinite || !point.lng.isFinite) return null;
    if (point.lat < -90 ||
        point.lat > 90 ||
        point.lng < -180 ||
        point.lng > 180) {
      return null;
    }
    return LatLng(point.lat, point.lng);
  }

  static LatLng? _driverFromSession(TripLocationSessionState session) {
    final latest = session.latest;
    if (latest == null || !latest.hasValidCoordinates) return null;
    if (!const TripLocationFreshnessPolicy().shouldShowDriverMarker(
      session.freshness,
    )) {
      return null;
    }
    return LatLng(latest.lat, latest.lng);
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.rideState,
    required this.locationSession,
    required this.statusOverride,
  });

  final String rideState;
  final TripLocationSessionState locationSession;
  final String? statusOverride;

  @override
  Widget build(BuildContext context) {
    final text =
        statusOverride ??
        (locationSession.isUnavailable ? 'Live location unavailable' : null);
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: OraColors.surfaceElevated.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(OraRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.sm,
          vertical: OraSpacing.xs,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: OraTypography.caption(OraColors.textSecondary),
        ),
      ),
    );
  }
}

class _ActiveRideMapShell extends StatelessWidget {
  const _ActiveRideMapShell();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OraColors.navyElevated,
        border: Border.all(color: OraColors.border),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(OraSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: OraColors.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: OraSpacing.xs),
              Text(
                'Map preview',
                style: OraTypography.label(OraColors.textPrimary),
              ),
              Text(
                'Live map is temporarily unavailable. Ride controls still work.',
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
