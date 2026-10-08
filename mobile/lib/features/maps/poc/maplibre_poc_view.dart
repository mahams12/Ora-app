import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/theme/ora_colors.dart';
import '../../../app/theme/ora_spacing.dart';
import 'maplibre_poc_config.dart';
import 'maplibre_poc_geometry.dart';
import 'maplibre_poc_metrics.dart';

/// Isolated disposable MapLibre proof-of-concept screen.
///
/// Does NOT replace RideMapPreview / ActiveRideMap.
/// Does NOT connect to RTDB, Google Routes, pricing, or ride state.
class MapLibrePoCView extends StatefulWidget {
  const MapLibrePoCView({super.key});

  @override
  State<MapLibrePoCView> createState() => _MapLibrePoCViewState();
}

class _MapLibrePoCViewState extends State<MapLibrePoCView> {
  final MapLibrePoCMetrics _metrics = MapLibrePoCMetrics();
  MapLibreMapController? _controller;
  String? _styleJson;
  String? _loadError;
  bool _overlaysApplied = false;
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    _metrics.mark('screen_open');
    _prepareStyle();
  }

  Future<void> _prepareStyle() async {
    if (!MapLibrePoCConfig.hasTileKey) {
      setState(() {
        _loadError = MapLibrePoCConfig.missingKeyMessage;
      });
      _metrics.error('missing_MAPLIBRE_TILE_KEY');
      return;
    }
    try {
      final preflight = await _preflightMapTiler(MapLibrePoCConfig.mapTilerApiKey);
      if (!preflight.ok) {
        if (!mounted) return;
        setState(() {
          _loadError = preflight.message;
        });
        _metrics.error(preflight.metricCode);
        return;
      }
      _metrics.mark('maptiler_preflight_ok');

      final raw =
          await rootBundle.loadString(MapLibrePoCConfig.styleAssetPath);
      final injected = raw.replaceAll(
        MapLibrePoCConfig.styleKeyPlaceholder,
        MapLibrePoCConfig.mapTilerApiKey,
      );
      // Validate JSON before handing to native.
      jsonDecode(injected);
      if (!mounted) return;
      setState(() {
        _styleJson = injected;
      });
      _metrics.mark('style_json_ready');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load Ora PoC style: $e';
      });
      _metrics.error('style_prepare_failed');
    }
  }

  /// Confirms MapTiler accepts the key before mounting the map (never logs the key).
  Future<({bool ok, String message, String metricCode})> _preflightMapTiler(
    String apiKey,
  ) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(MapLibrePoCConfig.tilesPreflightUrl(apiKey));
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 12));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        return (ok: true, message: '', metricCode: 'maptiler_ok');
      }
      if (res.statusCode == 403) {
        return (
          ok: false,
          message: MapLibrePoCConfig.keyRestrictedMessage,
          metricCode: 'maptiler_http_403_restricted',
        );
      }
      // Do not echo body if it could include secrets; status only.
      return (
        ok: false,
        message:
            'MapTiler tiles preflight failed (HTTP ${res.statusCode}). '
            'Fix the key/account, then rebuild.\n\n'
            'Body hint: ${body.length > 160 ? '${body.substring(0, 160)}…' : body}',
        metricCode: 'maptiler_http_${res.statusCode}',
      );
    } catch (e) {
      return (
        ok: false,
        message: 'MapTiler tiles preflight network error: $e',
        metricCode: 'maptiler_preflight_network_error',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _metrics.onMapCreated();
  }

  Future<void> _onStyleLoaded() async {
    _metrics.onStyleLoaded();
    setState(() => _styleReady = true);
    final c = _controller;
    if (c == null || _overlaysApplied) return;
    try {
      await _applyOraLayerTweaks(c);
      await _addMarkersAndRoute(c);
      _overlaysApplied = true;
      _metrics.onOverlaysReady();
      await c.animateCamera(
        CameraUpdate.newCameraPosition(MapLibrePoCGeometry.showcaseCamera),
        duration: const Duration(milliseconds: 1800),
      );
      _metrics.onShowcaseDone();
      if (mounted) setState(() {});
    } catch (e) {
      _metrics.error('overlay_failed:$e');
      if (mounted) {
        setState(() {
          _loadError = 'Map loaded but overlay setup failed: $e';
        });
      }
    }
  }

  /// Extra runtime paint proof that Ora controls vector style (not a dark overlay).
  Future<void> _applyOraLayerTweaks(MapLibreMapController c) async {
    try {
      await c.setLayerProperties(
        'background',
        const BackgroundLayerProperties(backgroundColor: '#12182B'),
      );
      await c.setLayerProperties(
        'water',
        const FillLayerProperties(fillColor: '#0B3A52'),
      );
      await c.setLayerProperties(
        'road-major',
        const LineLayerProperties(lineColor: '#3A4560'),
      );
      await c.setLayerProperties(
        'building-3d',
        const FillExtrusionLayerProperties(
          fillExtrusionColor: '#243056',
          fillExtrusionOpacity: 0.92,
        ),
      );
      _metrics.mark('ora_layer_tweaks_applied');
    } catch (e) {
      // Layer ids may differ if style partial — record, continue.
      _metrics.mark('ora_layer_tweaks_partial:$e');
    }
  }

  Future<void> _addMarkersAndRoute(MapLibreMapController c) async {
    Future<void> addImg(String name, String asset) async {
      final data = await rootBundle.load(asset);
      await c.addImage(name, data.buffer.asUint8List());
    }

    await addImg('ora_poc_pickup', MapLibrePoCConfig.pickupMarkerAsset);
    await addImg('ora_poc_dest', MapLibrePoCConfig.destinationMarkerAsset);
    await addImg('ora_poc_driver', MapLibrePoCConfig.driverMarkerAsset);

    // Route casing / glow then core blue (DISPLAY-ONLY geometry).
    await c.addLine(
      LineOptions(
        geometry: MapLibrePoCGeometry.displayOnlyRoute,
        lineColor: MapLibrePoCGeometry.routeGlow,
        lineWidth: 10,
        lineBlur: 1.2,
        lineOpacity: 0.35,
      ),
    );
    await c.addLine(
      LineOptions(
        geometry: MapLibrePoCGeometry.displayOnlyRoute,
        lineColor: MapLibrePoCGeometry.routeBlue,
        lineWidth: 5.5,
        lineOpacity: 0.95,
      ),
    );

    await c.addSymbol(
      SymbolOptions(
        geometry: MapLibrePoCGeometry.pickup,
        iconImage: 'ora_poc_pickup',
        iconSize: 0.85,
        iconAnchor: 'bottom',
      ),
    );
    await c.addSymbol(
      SymbolOptions(
        geometry: MapLibrePoCGeometry.destination,
        iconImage: 'ora_poc_dest',
        iconSize: 0.85,
        iconAnchor: 'bottom',
      ),
    );
    await c.addSymbol(
      SymbolOptions(
        geometry: MapLibrePoCGeometry.driver,
        iconImage: 'ora_poc_driver',
        iconSize: 0.95,
        iconRotate: MapLibrePoCGeometry.driverHeadingDeg,
        iconAnchor: 'center',
      ),
    );
    _metrics.mark('markers_and_route_added');
  }

  Future<void> _runShowcaseOrbit() async {
    final c = _controller;
    if (c == null) return;
    _metrics.mark('manual_showcase_orbit_start');
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: MapLibrePoCGeometry.lahoreCenter,
          zoom: 16.4,
          tilt: 62,
          bearing: 120,
        ),
      ),
      duration: const Duration(milliseconds: 2200),
    );
    await c.animateCamera(
      CameraUpdate.newCameraPosition(MapLibrePoCGeometry.showcaseCamera),
      duration: const Duration(milliseconds: 1800),
    );
    _metrics.mark('manual_showcase_orbit_done');
  }

  @override
  void dispose() {
    _metrics.mark('screen_dispose');
    _metrics.openCloseCycle += 1;
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.navy,
        foregroundColor: OraColors.textPrimary,
        title: const Text('MapLibre PoC'),
        actions: [
          IconButton(
            tooltip: 'Orbit showcase',
            onPressed: _styleReady ? _runShowcaseOrbit : null,
            icon: const Icon(Icons.threed_rotation),
          ),
          IconButton(
            tooltip: 'Metrics',
            onPressed: () => _showMetrics(context),
            icon: const Icon(Icons.speed),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: OraColors.navyElevated,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.md,
                OraSpacing.sm,
                OraSpacing.md,
                OraSpacing.sm,
              ),
              child: Text(
                'DISPOSABLE PoC — Lahore vector tiles · Ora dark style · '
                'display-only route/markers · not production · not RTDB',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: OraColors.goldSoft,
                      height: 1.35,
                    ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null && _styleJson == null) {
      return _FailClosedPane(message: _loadError!);
    }
    if (_styleJson == null) {
      return const Center(
        child: CircularProgressIndicator(color: OraColors.info),
      );
    }
    return Stack(
      children: [
        MapLibreMap(
          styleString: _styleJson!,
          initialCameraPosition: MapLibrePoCGeometry.initialCamera,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          onMapIdle: () {
            _metrics.onMapIdle();
          },
          onCameraIdle: () {
            _metrics.onCameraIdle();
          },
          compassEnabled: true,
          rotateGesturesEnabled: true,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          tiltGesturesEnabled: true,
          logoEnabled: true,
          attributionButtonPosition: AttributionButtonPosition.bottomLeft,
          foregroundLoadColor: OraColors.navy,
          trackCameraPosition: true,
        ),
        if (_loadError != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 48,
            child: Material(
              color: OraColors.dangerMuted,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _loadError!,
                  style: const TextStyle(color: OraColors.dangerForeground),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _chip(
                _styleReady ? 'Style: Ora-controlled' : 'Style: loading…',
              ),
              const SizedBox(height: 6),
              _chip('3D / pitch / rotate enabled'),
              const SizedBox(height: 6),
              _chip('Route: DISPLAY-ONLY'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label) {
    return Material(
      color: const Color(0xCC12182B),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: OraColors.tealBright,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showMetrics(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: OraColors.navyElevated,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(OraSpacing.lg),
          child: SingleChildScrollView(
            child: SelectableText(
              _metrics.toPrettyJson(),
              style: const TextStyle(
                color: OraColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FailClosedPane extends StatelessWidget {
  const _FailClosedPane({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final restricted = message.contains('403');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              restricted ? Icons.block : Icons.key_off,
              color: OraColors.gold,
              size: 48,
            ),
            const SizedBox(height: OraSpacing.md),
            Text(
              restricted ? 'MapTiler key rejected' : 'MapTiler key required',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: OraColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: OraSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: OraColors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
