import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../models/ride_map_preview_model.dart';
import '../utils/ride_map_camera_policy.dart';

/// Real Google Maps preview for passenger ride request (MAP-1).
///
/// Display-only: markers + optional estimate polyline. Never gates pricing
/// or ride creation. Soft-fails to a shell if the Maps SDK cannot load.
class RideMapPreview extends StatefulWidget {
  const RideMapPreview({
    super.key,
    required this.model,
    this.height = 168,
    this.onBack,
    this.enableMaps = true,
  });

  final RideMapPreviewModel model;
  final double height;
  final VoidCallback? onBack;

  /// Test hook — when false, never mounts [GoogleMap] (soft failure shell).
  final bool enableMaps;

  @override
  State<RideMapPreview> createState() => _RideMapPreviewState();
}

class _RideMapPreviewState extends State<RideMapPreview> {
  GoogleMapController? _controller;
  String? _fittedIdentity;

  @override
  void didUpdateWidget(covariant RideMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.routeIdentity != widget.model.routeIdentity) {
      _fittedIdentity = null;
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

  void _scheduleCameraFit() {
    final identity = widget.model.routeIdentity;
    if (_fittedIdentity == identity) return;
    final controller = _controller;
    if (controller == null) return;

    final update = RideMapCameraPolicy.cameraUpdate(
      pickup: widget.model.pickup,
      destination: widget.model.destination,
    );
    if (update == null) {
      _fittedIdentity = identity;
      return;
    }

    // Defer so platform view is ready; ignore failures (soft).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_fittedIdentity == identity) return;
      try {
        await controller.animateCamera(update);
        if (mounted) _fittedIdentity = identity;
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint('RideMapPreview camera fit soft-failed: $error');
          debugPrint('$stack');
        }
      }
    });
  }

  Set<Marker> _markers() {
    final markers = <Marker>{};
    final pickup = widget.model.pickup;
    final destination = widget.model.destination;
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
    return markers;
  }

  Set<Polyline> _polylines() {
    if (!widget.model.hasRouteLine) return const <Polyline>{};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: widget.model.polylinePoints,
        color: OraColors.gold,
        width: 4,
      ),
    };
  }

  CameraPosition _initialCamera() {
    final pickup = widget.model.pickup;
    final destination = widget.model.destination;
    if (pickup != null && destination != null) {
      if (RideMapCameraPolicy.areExtremelyClose(pickup, destination)) {
        return CameraPosition(
          target: RideMapCameraPolicy.midpoint(pickup, destination),
          zoom: RideMapCameraPolicy.closePointsZoom,
        );
      }
      return CameraPosition(
        target: RideMapCameraPolicy.midpoint(pickup, destination),
        zoom: 12,
      );
    }
    if (pickup != null) {
      return CameraPosition(
        target: pickup,
        zoom: RideMapCameraPolicy.singlePointZoom,
      );
    }
    if (destination != null) {
      return CameraPosition(
        target: destination,
        zoom: RideMapCameraPolicy.singlePointZoom,
      );
    }
    return RideMapCameraPolicy.idleCamera;
  }

  @override
  Widget build(BuildContext context) {
    final showMap = widget.enableMaps &&
        widget.model.status != RideMapPreviewStatus.idle &&
        (widget.model.hasPickup || widget.model.hasDestination);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showMap)
            GoogleMap(
              initialCameraPosition: _initialCamera(),
              markers: _markers(),
              polylines: _polylines(),
              myLocationButtonEnabled: false,
              myLocationEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              liteModeEnabled: false,
              onMapCreated: _onMapCreated,
              onCameraMoveStarted: () {},
            )
          else
            const _MapShellFallback(),
          if (widget.model.status == RideMapPreviewStatus.loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: OraColors.gold,
              ),
            ),
          if (widget.onBack != null)
            Positioned(
              top: OraSpacing.md,
              left: OraSpacing.md,
              child: Material(
                color: OraColors.surfaceElevated.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  color: OraColors.textPrimary,
                ),
              ),
            ),
          Positioned(
            left: OraSpacing.md,
            right: OraSpacing.md,
            bottom: OraSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: OraSpacing.sm,
                vertical: OraSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: OraColors.surfaceElevated.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(OraRadius.pill),
                border: Border.all(color: OraColors.border),
              ),
              child: Text(
                widget.model.statusLabel,
                textAlign: TextAlign.center,
                style: OraTypography.caption(OraColors.goldSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapShellFallback extends StatelessWidget {
  const _MapShellFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OraColors.navy, OraColors.navyElevated, OraColors.surface],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: OraColors.primary, size: 28),
            SizedBox(height: OraSpacing.xs),
            Text(
              'Map preview',
              style: TextStyle(
                color: OraColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
