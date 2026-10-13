import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../maps/preview/map_preview_camera_policy.dart';
import '../../../maps/preview/map_preview_config.dart';
import '../../../maps/preview/map_preview_style_loader.dart';
import '../models/ride_map_preview_model.dart';

/// Real MapLibre preview for passenger ride request (MAP-1).
///
/// Display-only: branded markers + optional estimate polyline. Never gates
/// pricing or ride creation. Soft-fails to a shell if tiles/style cannot load.
/// No Google Maps watermark — discreet MapTiler/OSM attribution only.
class RideMapPreview extends StatefulWidget {
  const RideMapPreview({
    super.key,
    required this.model,
    this.height = 168,
    this.onBack,
    this.enableMaps = true,
    this.isExpanded = false,
    this.onExpand,
    this.onCollapse,
  });

  final RideMapPreviewModel model;
  final double height;
  final VoidCallback? onBack;

  /// Test hook — when false, never mounts [MapLibreMap] (soft failure shell).
  final bool enableMaps;

  /// Whether the parent is presenting this map full-screen.
  final bool isExpanded;

  /// Compact → expanded. Null hides the expand control.
  final VoidCallback? onExpand;

  /// Expanded → compact. Null hides the collapse control.
  final VoidCallback? onCollapse;

  @override
  State<RideMapPreview> createState() => _RideMapPreviewState();
}

class _RideMapPreviewState extends State<RideMapPreview> {
  MapLibreMapController? _controller;
  String? _fittedIdentity;
  String? _styleJson;
  String? _styleError;
  bool _styleReady = false;
  bool _threeDEnabled = true;
  bool _buildingsVisible = true;
  Offset? _pickupScreen;
  Offset? _destinationScreen;

  static const String _pickupImageId = 'ora_preview_pickup';
  static const String _destImageId = 'ora_preview_dest';

  @override
  void initState() {
    super.initState();
    if (widget.enableMaps) {
      _prepareStyle();
    }
  }

  @override
  void didUpdateWidget(covariant RideMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enableMaps != widget.enableMaps && widget.enableMaps) {
      _prepareStyle();
    }
    if (oldWidget.model.routeIdentity != widget.model.routeIdentity) {
      _fittedIdentity = null;
      if (_styleReady) {
        _applyOverlays();
      }
    }
  }

  @override
  void dispose() {
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

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _applyOverlays();
  }

  LatLng? _toMl(gmaps.LatLng? p) {
    if (p == null) return null;
    return LatLng(p.latitude, p.longitude);
  }

  List<LatLng> _routeGeometry() {
    return widget.model.polylinePoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList(growable: false);
  }

  Future<void> _applyOverlays() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    try {
      await c.clearLines();
      await c.clearSymbols();

      Future<void> addImg(String name, String asset) async {
        final data = await rootBundle.load(asset);
        try {
          await c.addImage(name, data.buffer.asUint8List());
        } catch (_) {
          // Image may already exist after style reload — ignore.
        }
      }

      await addImg(_pickupImageId, MapPreviewConfig.pickupMarkerAsset);
      await addImg(_destImageId, MapPreviewConfig.destinationMarkerAsset);

      final route = _routeGeometry();
      if (route.length >= 2) {
        await c.addLine(
          LineOptions(
            geometry: route,
            lineColor: MapPreviewConfig.routeGlow,
            lineWidth: MapPreviewConfig.routeGlowWidth,
            lineBlur: 1.2,
            lineOpacity: 0.35,
          ),
        );
        await c.addLine(
          LineOptions(
            geometry: route,
            lineColor: MapPreviewConfig.routeBlue,
            lineWidth: MapPreviewConfig.routeCoreWidth,
            lineOpacity: 0.95,
          ),
        );
      }

      final pickup = _toMl(widget.model.pickup);
      final destination = _toMl(widget.model.destination);
      if (pickup != null) {
        await c.addSymbol(
          SymbolOptions(
            geometry: pickup,
            iconImage: _pickupImageId,
            iconSize: 0.9,
            iconAnchor: 'bottom',
          ),
        );
      }
      if (destination != null) {
        await c.addSymbol(
          SymbolOptions(
            geometry: destination,
            iconImage: _destImageId,
            iconSize: 0.9,
            iconAnchor: 'bottom',
          ),
        );
      }

      await _applyBuildingVisibility(c);
      _scheduleCameraFit();
      await _updateCalloutPositions();
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('RideMapPreview overlays soft-failed: $error');
        debugPrint('$stack');
      }
    }
  }

  Future<void> _applyBuildingVisibility(MapLibreMapController c) async {
    try {
      await c.setLayerVisibility('building-3d', _buildingsVisible);
      await c.setLayerVisibility('building-2d', _buildingsVisible);
    } catch (_) {
      // Layer ids may differ — soft.
    }
  }

  void _scheduleCameraFit() {
    final identity = widget.model.routeIdentity;
    if (_fittedIdentity == identity) return;
    final controller = _controller;
    if (controller == null || !_styleReady) return;

    final pickup = _toMl(widget.model.pickup);
    final destination = _toMl(widget.model.destination);
    final update = MapPreviewCameraPolicy.cameraUpdate(
      pickup: pickup,
      destination: destination,
    );
    if (update == null) {
      _fittedIdentity = identity;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_fittedIdentity == identity) return;
      try {
        await controller.animateCamera(update);
        if (_threeDEnabled) {
          await _applyTilt(controller, MapPreviewConfig.threeDTilt);
        }
        if (mounted) {
          _fittedIdentity = identity;
          await _updateCalloutPositions();
        }
      } catch (error, stack) {
        if (kDebugMode) {
          debugPrint('RideMapPreview camera fit soft-failed: $error');
          debugPrint('$stack');
        }
      }
    });
  }

  Future<void> _applyTilt(MapLibreMapController controller, double tilt) async {
    try {
      final pos = controller.cameraPosition;
      if (pos == null) return;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos.target,
            zoom: pos.zoom,
            bearing: pos.bearing,
            tilt: tilt,
          ),
        ),
        duration: const Duration(milliseconds: 450),
      );
    } catch (_) {
      // Soft.
    }
  }

  Future<void> _updateCalloutPositions() async {
    final c = _controller;
    if (c == null || !mounted) return;
    try {
      final pickup = _toMl(widget.model.pickup);
      final destination = _toMl(widget.model.destination);
      Offset? pickupOff;
      Offset? destOff;
      if (pickup != null) {
        final p = await c.toScreenLocation(pickup);
        pickupOff = Offset(p.x.toDouble(), p.y.toDouble());
      }
      if (destination != null) {
        final p = await c.toScreenLocation(destination);
        destOff = Offset(p.x.toDouble(), p.y.toDouble());
      }
      if (!mounted) return;
      setState(() {
        _pickupScreen = pickupOff;
        _destinationScreen = destOff;
      });
    } catch (_) {
      // Soft — fall back to stacked callouts.
      if (!mounted) return;
      setState(() {
        _pickupScreen = null;
        _destinationScreen = null;
      });
    }
  }

  Future<void> _resetBearing() async {
    final c = _controller;
    if (c == null) return;
    final pos = c.cameraPosition;
    if (pos == null) return;
    try {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos.target,
            zoom: pos.zoom,
            bearing: 0,
            tilt: _threeDEnabled
                ? MapPreviewConfig.threeDTilt
                : MapPreviewConfig.flatTilt,
          ),
        ),
        duration: const Duration(milliseconds: 400),
      );
      await _updateCalloutPositions();
    } catch (_) {}
  }

  Future<void> _toggleThreeD() async {
    final next = !_threeDEnabled;
    setState(() => _threeDEnabled = next);
    final c = _controller;
    if (c == null) return;
    await _applyTilt(
      c,
      next ? MapPreviewConfig.threeDTilt : MapPreviewConfig.flatTilt,
    );
    await _updateCalloutPositions();
  }

  Future<void> _toggleBuildings() async {
    final next = !_buildingsVisible;
    setState(() => _buildingsVisible = next);
    final c = _controller;
    if (c == null) return;
    await _applyBuildingVisibility(c);
  }

  void _handleBack() {
    if (widget.isExpanded && widget.onCollapse != null) {
      widget.onCollapse!();
      return;
    }
    widget.onBack?.call();
  }

  /// Live map as soon as the Ora style is ready — same surface while searching
  /// pickup/destination (inDrive-like), not only after both points confirm.
  bool get _canShowMap =>
      widget.enableMaps && _styleJson != null && _styleJson!.isNotEmpty;

  bool get _styleLoading =>
      widget.enableMaps && _styleJson == null && _styleError == null;

  bool get _showStatusChip {
    if (widget.model.statusLabel.isEmpty) return false;
    if (!_canShowMap) return true;
    if (widget.model.status == RideMapPreviewStatus.loading) return true;
    if (widget.model.status == RideMapPreviewStatus.routeUnavailable) {
      return true;
    }
    // Compose guidance while pins are still incomplete.
    return !widget.model.hasPickup || !widget.model.hasDestination;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mapSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              if (_canShowMap)
                MapLibreMap(
                  styleString: _styleJson!,
                  initialCameraPosition: _initialCamera(),
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                  onCameraIdle: () {
                    _updateCalloutPositions();
                  },
                  compassEnabled: false,
                  rotateGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  logoEnabled: false,
                  attributionButtonPosition:
                      AttributionButtonPosition.bottomLeft,
                  foregroundLoadColor: OraColors.navy,
                  trackCameraPosition: true,
                )
              else
                _MapShellFallback(
                  message: _styleError ??
                      (_styleLoading
                          ? 'Loading map…'
                          : 'Map preview unavailable'),
                ),
              if (widget.model.status == RideMapPreviewStatus.loading ||
                  _styleLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: OraColors.info,
                  ),
                ),
              // Callouts only when the live map is up (avoid duplicating review metrics).
              if (_canShowMap) ..._buildCallouts(mapSize),
              // Top chrome
              Positioned(
                top: topInset + OraSpacing.sm,
                left: OraSpacing.md,
                right: OraSpacing.md,
                child: Row(
                  children: [
                    if (widget.onBack != null ||
                        (widget.isExpanded && widget.onCollapse != null))
                      _MapChromeButton(
                        tooltip:
                            widget.isExpanded ? 'Collapse map' : 'Back',
                        icon: widget.isExpanded
                            ? Icons.close_fullscreen_rounded
                            : Icons.arrow_back_rounded,
                        onPressed: _handleBack,
                      ),
                    const Spacer(),
                    if (!widget.isExpanded && widget.onExpand != null)
                      _MapChromeButton(
                        tooltip: 'Expand map',
                        icon: Icons.open_in_full_rounded,
                        onPressed: widget.onExpand!,
                      ),
                  ],
                ),
              ),
              // Right-side map controls
              if (_canShowMap)
                Positioned(
                  right: OraSpacing.md,
                  bottom: OraSpacing.lg + 8,
                  child: _MapControlStack(
                    threeDEnabled: _threeDEnabled,
                    buildingsVisible: _buildingsVisible,
                    onCompass: _resetBearing,
                    onToggleThreeD: _toggleThreeD,
                    onToggleLayers: _toggleBuildings,
                  ),
                ),
              if (_showStatusChip)
                Positioned(
                  left: OraSpacing.md,
                  right: OraSpacing.md + 56,
                  bottom: OraSpacing.md,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: OraSpacing.sm,
                        vertical: OraSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: OraColors.surfaceElevated.withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(OraRadius.md),
                        border: Border.all(
                          color: OraColors.info.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        widget.model.statusLabel,
                        textAlign: TextAlign.center,
                        style: OraTypography.caption(OraColors.info),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildCallouts(Size mapSize) {
    final widgets = <Widget>[];
    final pickupLabel = widget.model.pickupLabel;
    final destLabel = widget.model.destinationLabel;

    if (widget.model.hasPickup && pickupLabel.isNotEmpty) {
      widgets.add(
        _positionedCallout(
          screen: _pickupScreen,
          mapSize: mapSize,
          fallbackAlignment: const Alignment(-0.55, -0.35),
          child: _EndpointCallout(
            title: 'Pickup',
            line1: pickupLabel,
          ),
        ),
      );
    }
    if (widget.model.hasDestination && destLabel.isNotEmpty) {
      widgets.add(
        _positionedCallout(
          screen: _destinationScreen,
          mapSize: mapSize,
          fallbackAlignment: const Alignment(0.45, 0.15),
          child: _EndpointCallout(
            title: 'Destination',
            line1: destLabel,
            line2: widget.model.hasTripMetrics
                ? widget.model.tripMetricsLabel
                : null,
          ),
        ),
      );
    }
    return widgets;
  }

  /// Keep callouts on-canvas — edge pins previously clipped destination cards.
  Widget _positionedCallout({
    required Offset? screen,
    required Size mapSize,
    required Alignment fallbackAlignment,
    required Widget child,
  }) {
    if (screen != null) {
      const calloutW = 168.0;
      const calloutH = 72.0;
      final maxLeft = math.max(8.0, mapSize.width - calloutW - 8);
      final maxTop = math.max(8.0, mapSize.height - calloutH - 8);
      final left = (screen.dx - 20).clamp(8.0, maxLeft);
      final top = (screen.dy - 72).clamp(8.0, maxTop);
      return Positioned(
        left: left,
        top: top,
        child: IgnorePointer(child: child),
      );
    }
    return Align(
      alignment: fallbackAlignment,
      child: IgnorePointer(child: child),
    );
  }

  CameraPosition _initialCamera() {
    final pickup = _toMl(widget.model.pickup);
    final destination = _toMl(widget.model.destination);
    final tilt =
        _threeDEnabled ? MapPreviewConfig.threeDTilt : MapPreviewConfig.flatTilt;
    if (pickup != null && destination != null) {
      if (MapPreviewCameraPolicy.areExtremelyClose(pickup, destination)) {
        return CameraPosition(
          target: MapPreviewCameraPolicy.midpoint(pickup, destination),
          zoom: MapPreviewCameraPolicy.closePointsZoom,
          tilt: tilt,
        );
      }
      return CameraPosition(
        target: MapPreviewCameraPolicy.midpoint(pickup, destination),
        zoom: 12,
        tilt: tilt,
      );
    }
    if (pickup != null) {
      return CameraPosition(
        target: pickup,
        zoom: MapPreviewCameraPolicy.singlePointZoom,
        tilt: tilt,
      );
    }
    if (destination != null) {
      return CameraPosition(
        target: destination,
        zoom: MapPreviewCameraPolicy.singlePointZoom,
        tilt: tilt,
      );
    }
    return MapPreviewCameraPolicy.idleCamera;
  }
}

class _EndpointCallout extends StatelessWidget {
  const _EndpointCallout({
    required this.title,
    required this.line1,
    this.line2,
  });

  final String title;
  final String line1;
  final String? line2;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE612182B),
        borderRadius: BorderRadius.circular(OraRadius.md),
        border: Border.all(color: OraColors.info.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: OraTypography.caption(OraColors.textMuted).copyWith(
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            line1,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.label(OraColors.textPrimary).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.2,
            ),
          ),
          if (line2 != null && line2!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              line2!,
              style: OraTypography.caption(OraColors.info).copyWith(
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapControlStack extends StatelessWidget {
  const _MapControlStack({
    required this.threeDEnabled,
    required this.buildingsVisible,
    required this.onCompass,
    required this.onToggleThreeD,
    required this.onToggleLayers,
  });

  final bool threeDEnabled;
  final bool buildingsVisible;
  final VoidCallback onCompass;
  final VoidCallback onToggleThreeD;
  final VoidCallback onToggleLayers;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapChromeButton(
          tooltip: 'Reset north',
          icon: Icons.navigation_rounded,
          onPressed: onCompass,
        ),
        const SizedBox(height: 8),
        _MapTextChromeButton(
          tooltip: threeDEnabled ? 'Switch to 2D' : 'Switch to 3D',
          label: '3D',
          active: threeDEnabled,
          onPressed: onToggleThreeD,
        ),
        const SizedBox(height: 8),
        _MapChromeButton(
          tooltip: buildingsVisible ? 'Hide buildings' : 'Show buildings',
          icon: Icons.layers_rounded,
          onPressed: onToggleLayers,
          active: buildingsVisible,
        ),
      ],
    );
  }
}

class _MapChromeButton extends StatelessWidget {
  const _MapChromeButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = true,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE612182B),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black54,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: active ? OraColors.textPrimary : OraColors.textMuted,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }
}

class _MapTextChromeButton extends StatelessWidget {
  const _MapTextChromeButton({
    required this.tooltip,
    required this.label,
    required this.onPressed,
    required this.active,
  });

  final String tooltip;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE612182B),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black54,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? OraColors.info : OraColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapShellFallback extends StatelessWidget {
  const _MapShellFallback({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1224),
            Color(0xFF132038),
            Color(0xFF1A2C48),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              color: OraColors.info.withValues(alpha: 0.9),
              size: 28,
            ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Map preview',
              style: OraTypography.label(OraColors.textPrimary).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: OraSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: OraSpacing.lg),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
