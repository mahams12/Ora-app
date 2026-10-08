import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../domain/entities/ride.dart';
import '../../domain/location/trip_location_freshness.dart';
import '../location/trip_location_session.dart';
import '../utils/active_ride_map_camera_policy.dart';
import '../utils/active_ride_map_progression_policy.dart';

/// Active-ride Google Map — pickup/destination from HTTP [Ride], driver from RTDB.
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

  /// Test hook — when false, never mounts [GoogleMap].
  final bool enableMaps;

  /// Test / instrumentation hook. When set, invoked instead of platform
  /// [GoogleMapController.animateCamera]. Also enables camera scheduling
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

  /// Test hook — bumping this value simulates a user [onCameraMoveStarted]
  /// without mounting a platform [GoogleMap] (`enableMaps: false`).
  final int userCameraMoveEpoch;

  @override
  State<ActiveRideMap> createState() => _ActiveRideMapState();
}

class _ActiveRideMapState extends State<ActiveRideMap> {
  GoogleMapController? _controller;

  /// Last successfully applied camera identity (guards against rebuild thrash).
  String? _fittedIdentity;

  /// In-flight fit target — prevents duplicate post-frame animate for same id.
  String? _pendingIdentity;

  /// MAP-3: passenger owns framing after a genuine user camera gesture.
  bool _userOwnsCamera = false;

  /// MAP-3: true while our own [animateCamera] / test hook animate is in flight.
  /// Prevents programmatic moves from latching [_userOwnsCamera].
  bool _programmaticCameraMove = false;

  LatLng? get _pickup => _toLatLng(widget.ride.pickup);
  LatLng? get _destination => _toLatLng(widget.ride.destination);

  /// Driver for camera + markers — only when MAP-2A freshness says show marker.
  LatLng? get _driverLatLng {
    final session = widget.locationSession;
    final latest = session.latest;
    if (latest == null || !latest.hasValidCoordinates) return null;
    if (!const TripLocationFreshnessPolicy()
        .shouldShowDriverMarker(session.freshness)) {
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
      _controller != null || widget.onAnimateCamera != null;

  @override
  void initState() {
    super.initState();
    if (widget.onAnimateCamera != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleCameraFit();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ActiveRideMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // MAP-3 test hook — epoch bump == user camera gesture (not programmatic).
    if (widget.userCameraMoveEpoch != oldWidget.userCameraMoveEpoch) {
      _onUserCameraMoveStarted();
    }

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
    _controller = null;
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _scheduleCameraFit();
  }

  /// MAP-3 — genuine user gesture. Programmatic animate must not call this
  /// without the [_programmaticCameraMove] guard (see [_performAnimate]).
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

  void _onRecenter() {
    // Recenter: clear ownership, then one MAP-2B policy fit.
    _releaseUserCameraOwnership();
    _fittedIdentity = null;
    _pendingIdentity = null;
    _scheduleCameraFit();
  }

  void _scheduleCameraFit() {
    if (!_cameraReady) return;

    // MAP-3: while the user owns the camera, suppress automatic animateCamera.
    // Markers + MAP-2C guides still update via rebuild. Recenter clears ownership
    // before calling this method.
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
    // Guard: platform may emit onCameraMoveStarted for our own animateCamera.
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
      _programmaticCameraMove = false;
    }
  }

  Set<Marker> _markers() {
    final markers = <Marker>{};
    final pickup = _pickup;
    final destination = _destination;
    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          infoWindow: const InfoWindow(title: 'Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: const InfoWindow(title: 'Destination'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }

    final driver = _driverLatLng;
    final latest = widget.locationSession.latest;
    if (driver != null && latest != null) {
      final band = widget.locationSession.freshness;
      final alpha = switch (band) {
        TripLocationFreshness.fresh => 1.0,
        TripLocationFreshness.stale => 0.75,
        TripLocationFreshness.degraded => 0.55,
        TripLocationFreshness.expired ||
        TripLocationFreshness.missing =>
          0.0,
      };
      if (alpha > 0) {
        markers.add(
          Marker(
            markerId: const MarkerId('driver'),
            position: driver,
            infoWindow: const InfoWindow(title: 'Driver'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            alpha: alpha,
            // Heading is display metadata only — never invent motion.
            rotation: latest.heading.isFinite ? latest.heading : 0,
            flat: true,
          ),
        );
      }
    }
    return markers;
  }

  List<ActiveRideMapGuideSegment> _guideSegments() {
    return ActiveRideMapProgressionPolicy.segments(
      rideState: widget.ride.state,
      pickup: _pickup,
      destination: _destination,
      driver: _driverLatLng,
    );
  }

  /// Presentation-only polyline set — stroke constants live here (not in policy)
  /// so a future Ora visual layer can restyle without touching progression logic.
  Set<Polyline> _polylines(List<ActiveRideMapGuideSegment> segments) {
    if (segments.isEmpty) return const <Polyline>{};
    final out = <Polyline>{};
    for (final segment in segments) {
      out.add(
        Polyline(
          polylineId: PolylineId(segment.kind.name),
          points: <LatLng>[segment.start, segment.end],
          color: _guideStrokeColor,
          width: _guideStrokeWidth,
          patterns: _guidePatterns,
          geodesic: false,
          consumeTapEvents: false,
        ),
      );
    }
    return out;
  }

  // Presentation constants — replaceable by Ora visual layer later.
  static const Color _guideStrokeColor = Color(0xFF90A4AE);
  static const int _guideStrokeWidth = 3;
  static final List<PatternItem> _guidePatterns = <PatternItem>[
    PatternItem.dash(18),
    PatternItem.gap(12),
  ];

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
    if (pickup != null) {
      return CameraPosition(
        target: pickup,
        zoom: ActiveRideMapCameraPolicy.singlePointZoom,
      );
    }
    if (destination != null) {
      return CameraPosition(
        target: destination,
        zoom: ActiveRideMapCameraPolicy.singlePointZoom,
      );
    }
    return ActiveRideMapCameraPolicy.idleCamera;
  }

  @override
  Widget build(BuildContext context) {
    final hasAnchors = _pickup != null || _destination != null;
    final showMap = widget.enableMaps && hasAnchors;
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
                GoogleMap(
                  initialCameraPosition: _initialCamera(),
                  markers: _markers(),
                  polylines: _polylines(guides),
                  myLocationButtonEnabled: false,
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  liteModeEnabled: false,
                  onMapCreated: _onMapCreated,
                  // MAP-3: latch ownership on genuine user gestures only.
                  // Programmatic animateCamera is filtered via [_programmaticCameraMove].
                  onCameraMoveStarted: _onUserCameraMoveStarted,
                )
              else
                const _ActiveRideMapShell(),
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
    if (!const TripLocationFreshnessPolicy()
        .shouldShowDriverMarker(session.freshness)) {
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
    final text = statusOverride ??
        (locationSession.isUnavailable
            ? 'Live location unavailable'
            : null);
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
