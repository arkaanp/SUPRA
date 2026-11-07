import 'package:flutter/material.dart' hide Route;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../config/map_config.dart';
import '../models/location.dart';
import '../models/prediction.dart';
import '../models/route.dart';
import '../models/route_option.dart';
import '../services/routing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/route_planner_view.dart';
import '../widgets/supra_map.dart';

/// Full-screen route map with road-accurate routing, multi-modal transport options
/// (Car, Motorcycle, Public Transit), weather/air quality exposure evaluation,
/// and contextual health & safety advisories (e.g. N95 mask recommendations).
class MapScreen extends StatefulWidget {
  final LatLng start;
  final LatLng destination;
  final String? startName;
  final String? destinationName;
  final Route? route;
  final List<Prediction> predictions;
  final bool forceCanvas;
  final double? initialPm25;
  final double? initialRainMm;
  final RoutingService? routingService;
  final List<RouteOption>? initialRouteOptions;

  const MapScreen({
    super.key,
    required this.start,
    required this.destination,
    this.startName,
    this.destinationName,
    this.route,
    this.predictions = const [],
    this.forceCanvas = false,
    this.initialPm25,
    this.initialRainMm,
    this.routingService,
    this.initialRouteOptions,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final RoutingService _routingService;
  bool _showTraffic = true;
  bool _showRain = true;
  LatLng? _inspectedLocation;
  late bool _useMapLibre;
  ml.MapLibreMapController? _mapController;

  List<RouteOption> _routeOptions = [];
  RouteOption? _selectedOption;
  bool _loadingRoutes = false;

  @override
  void initState() {
    super.initState();
    _routingService = widget.routingService ?? RoutingService();
    _useMapLibre =
        !widget.forceCanvas &&
        !MapConfig.isTestEnvironment &&
        MapConfig.isMapLibreSupported;
    if (widget.initialRouteOptions != null &&
        widget.initialRouteOptions!.isNotEmpty) {
      _routeOptions = widget.initialRouteOptions!;
      _selectedOption = widget.initialRouteOptions!.firstWhere(
        (o) => o.isRecommended,
        orElse: () => widget.initialRouteOptions!.first,
      );
      _loadingRoutes = false;
    } else {
      _loadingRoutes = true;
      _loadRoutes();
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final options = await _routingService.calculateRoutes(
        start: widget.start,
        destination: widget.destination,
        pm25UgM3: widget.initialPm25,
        rainfallMm: widget.initialRainMm,
      );
      if (mounted) {
        setState(() {
          _routeOptions = options;
          _selectedOption = options.firstWhere(
            (o) => o.isRecommended,
            orElse: () => options.first,
          );
          _loadingRoutes = false;
        });
        if (_useMapLibre) {
          _drawMapLibreRoute();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRoutes = false);
    }
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

      // Road-accurate waypoints from the active route option.
      final points =
          _selectedOption?.waypoints ??
          widget.route?.waypoints ??
          [widget.start, widget.destination];

      String lineColor = '#0F766E';
      if (_selectedOption != null) {
        if (_selectedOption!.mode == TransportMode.motorcycle) {
          lineColor = _selectedOption!.pm25UgM3 >= 35.0 ? '#D97706' : '#0F766E';
        } else if (_selectedOption!.mode == TransportMode.car) {
          lineColor = _showTraffic ? '#E11D48' : '#0F766E';
        } else {
          lineColor = '#2563EB'; // Blue for rail / transit
        }
      }

      await controller.addLine(
        ml.LineOptions(
          geometry: points
              .map((p) => ml.LatLng(p.latitude, p.longitude))
              .toList(),
          lineColor: lineColor,
          lineWidth: 5.0,
          lineOpacity: 0.9,
        ),
      );
    } catch (_) {
      // Discard during teardown.
    }
  }

  void _onSelectOption(RouteOption opt) {
    setState(() => _selectedOption = opt);
    if (_useMapLibre) {
      _drawMapLibreRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance =
        _selectedOption?.distanceKm ??
        widget.start.distanceTo(widget.destination);
    final sName = widget.startName ?? 'Kemang';
    final dName = widget.destinationName ?? 'Sudirman CBD';
    final nearest = _inspectedLocation != null
        ? findNearestLandmark(_inspectedLocation!)
        : null;

    final midLat = (widget.start.latitude + widget.destination.latitude) / 2;
    final midLon = (widget.start.longitude + widget.destination.longitude) / 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedOption != null
              ? '${_selectedOption!.mode.iconEmoji} ${_selectedOption!.mode.displayName} (${_selectedOption!.formattedDuration})'
              : 'Route map',
        ),
        actions: [
          if (MapConfig.isMapLibreSupported && !widget.forceCanvas)
            IconButton(
              icon: Icon(_useMapLibre ? Icons.public : Icons.map_outlined),
              onPressed: () => setState(() => _useMapLibre = !_useMapLibre),
              tooltip: _useMapLibre
                  ? 'Switch to schematic map'
                  : 'Switch to MapLibre',
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
          // 1. Map View (Road-Accurate MapLibre GL or Vector Canvas)
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
                            coordinates.latitude.toStringAsFixed(4),
                          ),
                          longitude: double.parse(
                            coordinates.longitude.toStringAsFixed(4),
                          ),
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
                    route: Route(
                      id: 'active_route',
                      tripId: 'active_trip',
                      waypoints:
                          _selectedOption?.waypoints ??
                          widget.route?.waypoints ??
                          const [],
                      totalDistanceKm: distance,
                    ),
                    predictions: widget.predictions,
                    onTapLocation: (tapped) {
                      setState(() => _inspectedLocation = tapped);
                    },
                  ),

                // Top inspected location card
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

                // Loading overlay while calculating road geometry
                if (_loadingRoutes)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Snapping to road network…',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Google-Maps-Style Multi-Modal Route & Health Advisory Drawer
          Material(
            elevation: 8,
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Origin -> Destination readout
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
                            '$sName → $dName',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '${distance.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SupraTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Route Planner with Mode Options & Health Advisories
                    if (_routeOptions.isNotEmpty && _selectedOption != null)
                      RoutePlannerView(
                        options: _routeOptions,
                        selectedOption: _selectedOption!,
                        onOptionSelected: _onSelectOption,
                        onConfirmRoute: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Selected ${_selectedOption!.mode.displayName} route (${_selectedOption!.formattedDuration}).',
                              ),
                            ),
                          );
                        },
                      )
                    else if (_loadingRoutes)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      const Center(child: Text('Could not load road routes.')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
