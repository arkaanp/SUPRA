import 'package:flutter/material.dart' hide Route;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../config/map_config.dart';
import '../models/location.dart';
import '../models/prediction.dart';
import '../models/route.dart';
import '../theme/app_theme.dart';
import '../widgets/supra_map.dart';

/// Full-screen route map with rain/traffic overlays (UML: "Display Map with
/// Rain/Traffic Highlights") powered by MapLibre GL vector basemaps.
class MapScreen extends StatefulWidget {
  final LatLng start;
  final LatLng destination;
  final String? startName;
  final String? destinationName;
  final Route? route;
  final List<Prediction> predictions;
  final bool forceCanvas;

  const MapScreen({
    super.key,
    required this.start,
    required this.destination,
    this.startName,
    this.destinationName,
    this.route,
    this.predictions = const [],
    this.forceCanvas = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _showTraffic = true;
  bool _showRain = true;
  LatLng? _inspectedLocation;
  late bool _useMapLibre;
  ml.MapLibreMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _useMapLibre = !widget.forceCanvas && MapConfig.isMapLibreSupported;
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _mapController = controller;
    _drawMapLibreRoute();
  }

  Future<void> _drawMapLibreRoute() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.clearCircles();
      await controller.clearLines();

      // Start circle marker (Green).
      await controller.addCircle(
        ml.CircleOptions(
          geometry: ml.LatLng(widget.start.latitude, widget.start.longitude),
          circleColor: '#22C55E',
          circleRadius: 9.0,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        ),
      );

      // Destination circle marker (Red).
      await controller.addCircle(
        ml.CircleOptions(
          geometry: ml.LatLng(
            widget.destination.latitude,
            widget.destination.longitude,
          ),
          circleColor: '#EF4444',
          circleRadius: 9.0,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        ),
      );

      // Route polyline.
      final points = widget.route?.waypoints ??
          [
            widget.start,
            LatLng(
              latitude: (widget.start.latitude + widget.destination.latitude) / 2 +
                  0.001,
              longitude: (widget.start.longitude + widget.destination.longitude) /
                      2 -
                  0.002,
            ),
            widget.destination,
          ];

      await controller.addLine(
        ml.LineOptions(
          geometry: points
              .map((p) => ml.LatLng(p.latitude, p.longitude))
              .toList(),
          lineColor: _showTraffic ? '#F59E0B' : '#0F766E',
          lineWidth: 5.0,
          lineOpacity: 0.9,
        ),
      );
    } catch (_) {
      // Discard during teardown.
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.start.distanceTo(widget.destination);
    final sName = widget.startName ?? 'Kemang';
    final dName = widget.destinationName ?? 'Sudirman CBD';
    final nearest = _inspectedLocation != null
        ? findNearestLandmark(_inspectedLocation!)
        : null;

    final midLat = (widget.start.latitude + widget.destination.latitude) / 2;
    final midLon = (widget.start.longitude + widget.destination.longitude) / 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route map'),
        actions: [
          if (MapConfig.isMapLibreSupported && !widget.forceCanvas)
            IconButton(
              icon: Icon(_useMapLibre ? Icons.public : Icons.map_outlined),
              onPressed: () => setState(() => _useMapLibre = !_useMapLibre),
              tooltip: _useMapLibre ? 'Switch to schematic map' : 'Switch to MapLibre',
            ),
          IconButton(
            icon: Icon(_showTraffic ? Icons.traffic : Icons.traffic_outlined),
            onPressed: () {
              setState(() => _showTraffic = !_showTraffic);
              if (_useMapLibre) _drawMapLibreRoute();
            },
            tooltip: 'Traffic overlay',
          ),
          IconButton(
            icon: Icon(_showRain ? Icons.wb_cloudy : Icons.wb_cloudy_outlined),
            onPressed: () => setState(() => _showRain = !_showRain),
            tooltip: 'Rain overlay',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_useMapLibre)
                  ml.MapLibreMap(
                    styleString: MapConfig.cartoPositron,
                    initialCameraPosition: ml.CameraPosition(
                      target: ml.LatLng(midLat, midLon),
                      zoom: 12.0,
                    ),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedCallback: _drawMapLibreRoute,
                    onMapClick: (point, coordinates) {
                      setState(() {
                        _inspectedLocation = LatLng(
                          latitude: double.parse(
                              coordinates.latitude.toStringAsFixed(4)),
                          longitude: double.parse(
                              coordinates.longitude.toStringAsFixed(4)),
                        );
                      });
                    },
                    compassEnabled: true,
                    trackCameraPosition: true,
                  )
                else
                  SupraMap(
                    start: widget.start,
                    destination: widget.destination,
                    route: widget.route,
                    predictions: widget.predictions,
                    onTapLocation: (tapped) {
                      setState(() => _inspectedLocation = tapped);
                    },
                  ),

                if (_inspectedLocation != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place,
                            color: SupraTheme.brand,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  nearest != null
                                      ? nearest.name
                                      : 'Tapped location',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Lat: ${_inspectedLocation!.latitude.toStringAsFixed(4)}, Lon: ${_inspectedLocation!.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: SupraTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _inspectedLocation = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.directions,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$sName → $dName · ${distance.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _toggleChip('Traffic', Icons.traffic, _showTraffic),
                    const SizedBox(width: 10),
                    _toggleChip('Rain', Icons.wb_cloudy, _showRain),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, IconData icon, bool active) => FilterChip(
    avatar: Icon(icon, size: 16, color: active ? SupraTheme.brand : null),
    label: Text(label),
    selected: active,
    onSelected: (v) {
      if (label == 'Traffic') {
        setState(() => _showTraffic = v);
        if (_useMapLibre) _drawMapLibreRoute();
      }
      if (label == 'Rain') setState(() => _showRain = v);
    },
  );
}
