import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../config/map_config.dart';
import '../models/location.dart';
import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';

/// Interactive map widget allowing users to visually select geographic coordinates
/// within the Greater Jakarta service area (lat: -6.9..-5.8, lon: 106.3..107.3).
///
/// Uses MapLibre GL with Carto Positron/Voyager vector basemaps on supported
/// platforms (Android, iOS, Web), with a seamless vector fallback for offline/test environments.
class InteractiveLocationMap extends StatefulWidget {
  final LatLng? selectedLocation;
  final LatLng? secondaryLocation;
  final String? selectedLabel;
  final String? secondaryLabel;
  final ValueChanged<LatLng>? onLocationChanged;
  final bool isInteractive;
  final double height;
  final bool showLandmarks;
  final bool forceCanvas;
  final bool showFooter;
  final List<LatLng>? routeWaypoints;
  final Color? routeColor;
  final BorderRadius? borderRadius;

  const InteractiveLocationMap({
    super.key,
    this.selectedLocation,
    this.secondaryLocation,
    this.selectedLabel,
    this.secondaryLabel,
    this.onLocationChanged,
    this.isInteractive = true,
    this.height = 240,
    this.showLandmarks = true,
    this.forceCanvas = false,
    this.showFooter = true,
    this.routeWaypoints,
    this.routeColor,
    this.borderRadius,
  });

  @override
  State<InteractiveLocationMap> createState() => InteractiveLocationMapState();
}

class InteractiveLocationMapState extends State<InteractiveLocationMap> {
  // Service envelope bounds matching backend validation.
  static const double minLat = -6.9;
  static const double maxLat = -5.8;
  static const double minLon = 106.3;
  static const double maxLon = 107.3;

  LatLng? _currentLocation;
  ml.MapLibreMapController? _mapController;
  late bool _useMapLibre;
  String _mapStyle = MapConfig.cartoPositron;

  final GeocodingService _geocodingService = GeocodingService();
  String? _resolvedAddress;

  // Canvas pan & zoom state
  Offset _panOffset = Offset.zero;
  double _zoomFactor = 1.0;
  double _baseZoomFactor = 1.0;
  Offset _dragStart = Offset.zero;
  Offset _panStart = Offset.zero;
  bool _isDragging = false;
  Size? _lastCanvasSize;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.selectedLocation;
    _useMapLibre =
        !widget.forceCanvas &&
        !MapConfig.isTestEnvironment &&
        MapConfig.isMapLibreSupported;
    if (_currentLocation != null) {
      _resolveAddress(_currentLocation!);
    }
  }

  Future<void> _resolveAddress(LatLng loc) async {
    final addr = await _geocodingService.reverseGeocode(loc);
    if (mounted && _currentLocation == loc) {
      setState(() => _resolvedAddress = addr);
    }
  }

  @override
  void didUpdateWidget(covariant InteractiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedLocation != oldWidget.selectedLocation) {
      _currentLocation = widget.selectedLocation;
      if (_currentLocation != null && widget.showFooter) {
        _resolveAddress(_currentLocation!);
      }
      if (_useMapLibre) {
        _updateMapLibreLayers();
      }
    }
    if (widget.secondaryLocation != oldWidget.secondaryLocation ||
        widget.routeWaypoints != oldWidget.routeWaypoints ||
        widget.routeColor != oldWidget.routeColor) {
      if (_useMapLibre) {
        _updateMapLibreLayers();
      }
    }
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _mapController = controller;
    _updateMapLibreLayers();
  }

  Future<void> _updateMapLibreLayers() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.clearCircles();
      await controller.clearLines();

      final loc = _currentLocation ?? widget.selectedLocation;
      if (loc != null) {
        // Outer glow halo.
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(loc.latitude, loc.longitude),
            circleColor: '#0F766E',
            circleOpacity: 0.22,
            circleRadius: 18.0,
          ),
        );
        // Primary marker.
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(loc.latitude, loc.longitude),
            circleColor: '#0F766E',
            circleRadius: 8.0,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2.5,
          ),
        );
      }

      final sec = widget.secondaryLocation;
      if (sec != null) {
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(sec.latitude, sec.longitude),
            circleColor: '#EF4444',
            circleRadius: 8.0,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2.5,
          ),
        );
      }

      final waypoints = widget.routeWaypoints;
      if (waypoints != null && waypoints.length >= 2) {
        final colorHex = widget.routeColor != null
            ? '#${(widget.routeColor!.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
            : '#0F766E';
        await controller.addLine(
          ml.LineOptions(
            geometry: waypoints
                .map((p) => ml.LatLng(p.latitude, p.longitude))
                .toList(),
            lineColor: colorHex,
            lineWidth: 4.5,
            lineOpacity: 0.9,
          ),
        );
      } else if (loc != null && sec != null) {
        await controller.addLine(
          ml.LineOptions(
            geometry: [
              ml.LatLng(loc.latitude, loc.longitude),
              ml.LatLng(sec.latitude, sec.longitude),
            ],
            lineColor: '#0F766E',
            lineWidth: 3.5,
            lineOpacity: 0.85,
          ),
        );
      }
    } catch (_) {
      // Discard errors during controller reloads.
    }
  }

  void _handleMapLibreClick(ml.LatLng coordinates) {
    if (!widget.isInteractive) return;
    final lat = coordinates.latitude.clamp(minLat, maxLat);
    final lon = coordinates.longitude.clamp(minLon, maxLon);
    final location = LatLng(
      latitude: double.parse(lat.toStringAsFixed(4)),
      longitude: double.parse(lon.toStringAsFixed(4)),
    );
    setState(() => _currentLocation = location);
    _resolveAddress(location);
    _updateMapLibreLayers();
    widget.onLocationChanged?.call(location);
  }

  void animateToLocation(LatLng loc, {Size? mapSize}) {
    final size = mapSize ?? _lastCanvasSize ?? const Size(400, 300);
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);
    final normX =
        ((loc.longitude - minLon) / (maxLon - minLon)).clamp(0.0, 1.0);
    final normY =
        ((maxLat - loc.latitude) / (maxLat - minLat)).clamp(0.0, 1.0);
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseX = pad + normX * usableW;
    final baseY = pad + normY * usableH;
    const targetZoom = 1.35;
    final targetPan = Offset(
      -(baseX - centerX) * targetZoom,
      -(baseY - centerY) * targetZoom,
    );

    setState(() {
      _currentLocation = loc;
      _panOffset = targetPan;
      _zoomFactor = targetZoom;
    });
    _resolveAddress(loc);
    if (_useMapLibre && _mapController != null) {
      _mapController!.animateCamera(
        ml.CameraUpdate.newLatLngZoom(
          ml.LatLng(loc.latitude, loc.longitude),
          13.5,
        ),
      );
      _updateMapLibreLayers();
    }
  }

  LatLng _pixelToLatLng(Offset localPos, Size size) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final unzoomedX =
        (localPos.dx - _panOffset.dx - centerX) / _zoomFactor + centerX;
    final unzoomedY =
        (localPos.dy - _panOffset.dy - centerY) / _zoomFactor + centerY;

    final normalizedX = ((unzoomedX - pad) / usableW).clamp(0.0, 1.0);
    final normalizedY = ((unzoomedY - pad) / usableH).clamp(0.0, 1.0);

    final lon = minLon + normalizedX * (maxLon - minLon);
    final lat = maxLat - normalizedY * (maxLat - minLat);

    return LatLng(
      latitude: double.parse(lat.toStringAsFixed(4)),
      longitude: double.parse(lon.toStringAsFixed(4)),
    );
  }

  void _handleCanvasTap(Offset localPos, Size size) {
    if (!widget.isInteractive) return;
    final location = _pixelToLatLng(localPos, size);
    setState(() => _currentLocation = location);
    _resolveAddress(location);
    widget.onLocationChanged?.call(location);
  }

  @override
  Widget build(BuildContext context) {
    final location = _currentLocation ?? widget.selectedLocation;
    final nearest = location != null ? findNearestLandmark(location) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBounded = constraints.maxHeight.isFinite;
        final radius = widget.borderRadius ?? BorderRadius.circular(16);

        final mapWidget = ClipRRect(
          borderRadius: radius,
          child: Container(
            height: isBounded ? null : widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: radius == BorderRadius.zero
                  ? null
                  : Border.all(color: SupraTheme.divider),
              borderRadius: radius,
            ),
            child: Stack(
              children: [
                if (_useMapLibre)
                  ml.MapLibreMap(
                    styleString: _mapStyle,
                    initialCameraPosition: ml.CameraPosition(
                      target: ml.LatLng(
                        location?.latitude ?? MapConfig.defaultLat,
                        location?.longitude ?? MapConfig.defaultLon,
                      ),
                      zoom: location != null ? 12.5 : MapConfig.defaultZoom,
                    ),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedCallback: _updateMapLibreLayers,
                    onMapClick: (point, coordinates) =>
                        _handleMapLibreClick(coordinates),
                    cameraTargetBounds: ml.CameraTargetBounds(
                      ml.LatLngBounds(
                        southwest: const ml.LatLng(
                          minLat - 0.05,
                          minLon - 0.05,
                        ),
                        northeast: const ml.LatLng(
                          maxLat + 0.05,
                          maxLon + 0.05,
                        ),
                      ),
                    ),
                    minMaxZoomPreference: const ml.MinMaxZoomPreference(
                      9.0,
                      18.0,
                    ),
                    trackCameraPosition: true,
                    compassEnabled: true,
                    rotateGesturesEnabled: widget.isInteractive,
                    scrollGesturesEnabled: widget.isInteractive,
                    zoomGesturesEnabled: widget.isInteractive,
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  )
                else
                  LayoutBuilder(
                    builder: (context, mapConstraints) {
                      final size = mapConstraints.biggest;
                      _lastCanvasSize = size;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          if (!_isDragging) {
                            _handleCanvasTap(details.localPosition, size);
                          }
                        },
                        onScaleStart: (details) {
                          _dragStart = details.localFocalPoint;
                          _panStart = _panOffset;
                          _baseZoomFactor = _zoomFactor;
                          _isDragging = false;
                        },
                        onScaleUpdate: (details) {
                          final dist =
                              (details.localFocalPoint - _dragStart).distance;
                          if (dist > 8.0 || details.scale != 1.0) {
                            _isDragging = true;
                            setState(() {
                              _panOffset =
                                  _panStart +
                                  (details.localFocalPoint - _dragStart);
                              if (details.scale != 1.0) {
                                _zoomFactor = (_baseZoomFactor * details.scale)
                                    .clamp(0.6, 3.5);
                              }
                            });
                          }
                        },
                        onScaleEnd: (details) {
                          Future.delayed(
                            const Duration(milliseconds: 100),
                            () {
                              if (mounted) _isDragging = false;
                            },
                          );
                        },
                        child: Stack(
                          children: [
                            // Base vector map canvas with pan and zoom.
                            ClipRect(
                              child: Transform.translate(
                                offset: _panOffset,
                                child: Transform.scale(
                                  scale: _zoomFactor,
                                  origin: Offset(
                                    size.width / 2,
                                    size.height / 2,
                                  ),
                                  child: CustomPaint(
                                    size: size,
                                    painter: _JakartaCanvasPainter(
                                      minLat: minLat,
                                      maxLat: maxLat,
                                      minLon: minLon,
                                      maxLon: maxLon,
                                      showLandmarks: widget.showLandmarks,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Connecting route line.
                            if ((location != null &&
                                    widget.secondaryLocation != null) ||
                                (widget.routeWaypoints != null &&
                                    widget.routeWaypoints!.length >= 2))
                              ClipRect(
                                child: Transform.translate(
                                  offset: _panOffset,
                                  child: Transform.scale(
                                    scale: _zoomFactor,
                                    origin: Offset(
                                      size.width / 2,
                                      size.height / 2,
                                    ),
                                    child: CustomPaint(
                                      size: size,
                                      painter: _RouteLinePainter(
                                        from: location ??
                                            widget.routeWaypoints!.first,
                                        to: widget.secondaryLocation ??
                                            widget.routeWaypoints!.last,
                                        waypoints: widget.routeWaypoints,
                                        color: widget.routeColor,
                                        minLat: minLat,
                                        maxLat: maxLat,
                                        minLon: minLon,
                                        maxLon: maxLon,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // Secondary location pin.
                            if (widget.secondaryLocation != null)
                              _buildCanvasPin(
                                location: widget.secondaryLocation!,
                                size: size,
                                color: SupraTheme.aqiUnhealthy,
                                label: widget.secondaryLabel ?? 'D',
                              ),

                            // Primary selected pin.
                            if (location != null)
                              _buildCanvasPin(
                                location: location,
                                size: size,
                                color: SupraTheme.brand,
                                label: widget.selectedLabel ?? '📍',
                                isMain: true,
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                // Floating Zoom & Reset Map Controls
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, size: 16),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Zoom in',
                          onPressed: () {
                            if (_useMapLibre && _mapController != null) {
                              _mapController!.animateCamera(
                                ml.CameraUpdate.zoomIn(),
                              );
                            } else {
                              setState(
                                () => _zoomFactor = (_zoomFactor * 1.25).clamp(
                                  0.6,
                                  3.5,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(
                          width: 24,
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove, size: 16),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Zoom out',
                          onPressed: () {
                            if (_useMapLibre && _mapController != null) {
                              _mapController!.animateCamera(
                                ml.CameraUpdate.zoomOut(),
                              );
                            } else {
                              setState(
                                () => _zoomFactor = (_zoomFactor / 1.25).clamp(
                                  0.6,
                                  3.5,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(
                          width: 24,
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        IconButton(
                          icon: const Icon(Icons.my_location, size: 15),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Center on selected location',
                          onPressed: () {
                            final target =
                                _currentLocation ?? widget.selectedLocation;
                            if (target != null) {
                              animateToLocation(target);
                            } else {
                              setState(() {
                                _panOffset = Offset.zero;
                                _zoomFactor = 1.0;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Top controls overlay: MapLibre badge + style toggle.
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _useMapLibre ? Icons.public : Icons.map_outlined,
                              size: 13,
                              color: SupraTheme.brand,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _useMapLibre ? 'MapLibre GL' : 'Vector Map',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: SupraTheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (MapConfig.isMapLibreSupported && !widget.forceCanvas)
                        PopupMenuButton<String>(
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Icon(
                              Icons.layers_outlined,
                              size: 16,
                              color: SupraTheme.onSurface,
                            ),
                          ),
                          tooltip: 'Map style',
                          onSelected: (style) {
                            setState(() {
                              if (style == 'canvas') {
                                _useMapLibre = false;
                              } else {
                                _useMapLibre = true;
                                _mapStyle = style;
                              }
                            });
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: MapConfig.cartoPositron,
                              child: Text('MapLibre (Positron Light)'),
                            ),
                            const PopupMenuItem(
                              value: MapConfig.cartoVoyager,
                              child: Text('MapLibre (Voyager Color)'),
                            ),
                            const PopupMenuItem(
                              value: 'canvas',
                              child: Text('Vector Overview'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // Tap guide hint.
                if (widget.isInteractive && location == null)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Tap anywhere to pick coordinates',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isBounded) Expanded(child: mapWidget) else mapWidget,

            // Live location readout footer.
            if (widget.showFooter && location != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: SupraTheme.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: SupraTheme.brand.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: SupraTheme.brand,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _resolvedAddress ??
                                (nearest != null
                                    ? (nearest.name
                                            .toLowerCase()
                                            .contains(nearest.area.toLowerCase())
                                        ? nearest.name
                                        : '${nearest.name}, ${nearest.area}')
                                    : 'Selected Point'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: SupraTheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Lat: ${location.latitude.toStringAsFixed(4)}, Lon: ${location.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: SupraTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (nearest != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: SupraTheme.divider),
                        ),
                        child: Text(
                          '~${location.distanceTo(nearest.point).toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: SupraTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCanvasPin({
    required LatLng location,
    required Size size,
    required Color color,
    required String label,
    bool isMain = false,
  }) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final normX = ((location.longitude - minLon) / (maxLon - minLon)).clamp(
      0.0,
      1.0,
    );
    final normY = ((maxLat - location.latitude) / (maxLat - minLat)).clamp(
      0.0,
      1.0,
    );

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseX = pad + normX * usableW;
    final baseY = pad + normY * usableH;
    final px = (baseX - centerX) * _zoomFactor + centerX + _panOffset.dx;
    final py = (baseY - centerY) * _zoomFactor + centerY + _panOffset.dy;

    return Positioned(
      left: px - 14,
      top: py - 32,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            CustomPaint(size: const Size(8, 6), painter: _PinTipPainter(color)),
          ],
        ),
      ),
    );
  }
}

/// Modal bottom sheet to pick a location using MapLibre GL or Vector Canvas with live search & geocoding.
Future<LatLng?> showLocationPickerSheet({
  required BuildContext context,
  LatLng? initialLocation,
  String title = 'Select location on map',
}) async {
  LatLng selected =
      initialLocation ?? const LatLng(latitude: -6.2088, longitude: 106.8456);

  final geocoder = GeocodingService();
  String resolvedAddress = 'Resolving location…';

  return showModalBottomSheet<LatLng>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final mapKey = GlobalKey<InteractiveLocationMapState>();
      final searchCtrl = TextEditingController();
      List<GeocodedPlace> searchResults = [];

      return StatefulBuilder(
        builder: (context, setSheetState) {
          void updateAddress(LatLng loc) {
            geocoder.reverseGeocode(loc).then((addr) {
              if (context.mounted) {
                setSheetState(() => resolvedAddress = addr);
              }
            });
          }

          if (resolvedAddress == 'Resolving location…') {
            updateAddress(selected);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Grab handle.
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Header.
                  Row(
                    children: [
                      const Icon(Icons.map, color: SupraTheme.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: SupraTheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Search input bar with autocomplete
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search place, station, or street in Jakarta…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchCtrl.clear();
                                setSheetState(() => searchResults = []);
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    onChanged: (text) async {
                      if (text.trim().length >= 2) {
                        final res = await geocoder.searchPlaces(text);
                        setSheetState(() => searchResults = res);
                      } else {
                        setSheetState(() => searchResults = []);
                      }
                    },
                  ),

                  // Autocomplete dropdown suggestions
                  if (searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: SupraTheme.divider),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final place = searchResults[i];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(
                              Icons.location_on,
                              size: 18,
                              color: SupraTheme.brand,
                            ),
                            title: Text(
                              place.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            subtitle: Text(
                              place.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: SupraTheme.textSecondary,
                              ),
                            ),
                            onTap: () {
                              setSheetState(() {
                                selected = place.point;
                                resolvedAddress = place.displayName;
                                searchResults = [];
                                searchCtrl.text = place.name;
                              });
                              mapKey.currentState?.animateToLocation(
                                place.point,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Quick preset landmark chips.
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: greaterJakartaLandmarks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 6),
                      itemBuilder: (context, i) {
                        final landmark = greaterJakartaLandmarks[i];
                        final isSelected = selected == landmark.point;
                        return ChoiceChip(
                          label: Text(
                            landmark.name.split(' (').first,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : SupraTheme.onSurface,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: SupraTheme.brand,
                          backgroundColor: const Color(0xFFF1F5F9),
                          onSelected: (_) {
                            setSheetState(() {
                              selected = landmark.point;
                              resolvedAddress = landmark.name;
                            });
                            mapKey.currentState?.animateToLocation(
                              landmark.point,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Interactive MapLibre Map (footer disabled to avoid duplicate address card below).
                  InteractiveLocationMap(
                    key: mapKey,
                    selectedLocation: selected,
                    showFooter: false,
                    onLocationChanged: (newLoc) {
                      setSheetState(() => selected = newLoc);
                      updateAddress(newLoc);
                    },
                    height: 200,
                  ),
                  const SizedBox(height: 10),

                  // Dynamic Resolved Address Card
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SupraTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.place,
                          color: SupraTheme.brand,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resolvedAddress,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Lat: ${selected.latitude.toStringAsFixed(4)}, Lon: ${selected.longitude.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: SupraTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm button.
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Confirm location'),
                    onPressed: () => Navigator.of(context).pop(selected),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Draws the Greater Jakarta map: landmass, Java Sea coast, Ciliwung river,
/// arterial tollways, and reference cities/landmarks.
class _JakartaCanvasPainter extends CustomPainter {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final bool showLandmarks;

  _JakartaCanvasPainter({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.showLandmarks,
  });

  Offset _toPx(double lat, double lon, Size size) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final normX = ((lon - minLon) / (maxLon - minLon)).clamp(0.0, 1.0);
    final normY = ((maxLat - lat) / (maxLat - minLat)).clamp(0.0, 1.0);

    return Offset(pad + normX * usableW, pad + normY * usableH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Land background.
    final landPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(Offset.zero & size, landPaint);

    // 2. Java Sea (Teluk Jakarta) in the North (lat > -6.08).
    final seaPath = Path();
    final pStart = _toPx(-6.02, minLon, size);
    final pEnd = _toPx(-6.00, maxLon, size);

    seaPath.moveTo(0, 0);
    seaPath.lineTo(size.width, 0);
    seaPath.lineTo(pEnd.dx, pEnd.dy);

    // Coastline contour with Jakarta bay indentation.
    final c1 = _toPx(-6.10, 106.65, size);
    final c2 = _toPx(-6.09, 106.85, size);
    final c3 = _toPx(-6.12, 107.05, size);

    seaPath.cubicTo(c3.dx, c3.dy, c2.dx, c2.dy, c1.dx, c1.dy);
    seaPath.lineTo(pStart.dx, pStart.dy);
    seaPath.close();

    final seaPaint = Paint()..color = const Color(0xFFE0F2FE);
    canvas.drawPath(seaPath, seaPaint);

    // Coastline stroke.
    final coastPaint = Paint()
      ..color = const Color(0xFFBAE6FD)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final coastLine = Path()
      ..moveTo(pStart.dx, pStart.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pEnd.dx, pEnd.dy);
    canvas.drawPath(coastLine, coastPaint);

    // 3. Grid lines (lat / lon reference).
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    for (double lat = -6.8; lat <= -5.9; lat += 0.2) {
      final a = _toPx(lat, minLon, size);
      final b = _toPx(lat, maxLon, size);
      canvas.drawLine(Offset(0, a.dy), Offset(size.width, b.dy), gridPaint);
    }
    for (double lon = 106.4; lon <= 107.2; lon += 0.2) {
      final a = _toPx(maxLat, lon, size);
      final b = _toPx(minLat, lon, size);
      canvas.drawLine(Offset(a.dx, 0), Offset(b.dx, size.height), gridPaint);
    }

    // 4. Ciliwung River (Bogor -> Depok -> Jakarta Bay).
    final riverPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final riverPath = Path();
    final r1 = _toPx(-6.62, 106.82, size);
    final r2 = _toPx(-6.48, 106.84, size);
    final r3 = _toPx(-6.36, 106.83, size);
    final r4 = _toPx(-6.24, 106.86, size);
    final r5 = _toPx(-6.13, 106.83, size);

    riverPath.moveTo(r1.dx, r1.dy);
    riverPath.quadraticBezierTo(r2.dx, r2.dy, r3.dx, r3.dy);
    riverPath.quadraticBezierTo(r4.dx, r4.dy, r5.dx, r5.dy);
    canvas.drawPath(riverPath, riverPaint);

    // 5. Major Arterial Road Networks.
    final highwayPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Tol Jagorawi (Jakarta to Bogor).
    final jagoPath = Path()
      ..moveTo(_toPx(-6.25, 106.87, size).dx, _toPx(-6.25, 106.87, size).dy)
      ..lineTo(_toPx(-6.59, 106.81, size).dx, _toPx(-6.59, 106.81, size).dy);
    canvas.drawPath(jagoPath, highwayPaint);

    // Tol Jakarta - Cikampek (to Bekasi).
    final ckpPath = Path()
      ..moveTo(_toPx(-6.25, 106.87, size).dx, _toPx(-6.25, 106.87, size).dy)
      ..lineTo(_toPx(-6.26, 107.25, size).dx, _toPx(-6.26, 107.25, size).dy);
    canvas.drawPath(ckpPath, highwayPaint);

    // Tol Jakarta - Tangerang.
    final tgrPath = Path()
      ..moveTo(_toPx(-6.20, 106.82, size).dx, _toPx(-6.20, 106.82, size).dy)
      ..lineTo(_toPx(-6.18, 106.60, size).dx, _toPx(-6.18, 106.60, size).dy);
    canvas.drawPath(tgrPath, highwayPaint);

    // JORR (Outer Ring Road loop).
    final jorrPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final jorrRect = Rect.fromPoints(
      _toPx(-6.15, 106.72, size),
      _toPx(-6.32, 106.94, size),
    );
    canvas.drawOval(jorrRect, jorrPaint);

    // 6. District Labels (Subtle).
    _drawText(
      canvas,
      'JAKARTA',
      _toPx(-6.20, 106.82, size),
      11,
      const Color(0xFF94A3B8),
      true,
    );
    _drawText(
      canvas,
      'TANGERANG',
      _toPx(-6.21, 106.64, size),
      9,
      const Color(0xFF94A3B8),
      false,
    );
    _drawText(
      canvas,
      'BEKASI',
      _toPx(-6.24, 107.01, size),
      9,
      const Color(0xFF94A3B8),
      false,
    );
    _drawText(
      canvas,
      'DEPOK',
      _toPx(-6.40, 106.82, size),
      9,
      const Color(0xFF94A3B8),
      false,
    );
    _drawText(
      canvas,
      'BOGOR',
      _toPx(-6.60, 106.79, size),
      10,
      const Color(0xFF94A3B8),
      true,
    );

    // 7. Reference Landmark dots.
    if (showLandmarks) {
      final dotPaint = Paint()..color = const Color(0xFF94A3B8);
      for (final lm in greaterJakartaLandmarks) {
        final pt = _toPx(lm.point.latitude, lm.point.longitude, size);
        canvas.drawCircle(pt, 2.5, dotPaint);
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    double fontSize,
    Color color,
    bool bold,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JakartaCanvasPainter old) => false;
}

/// Draws a route line (either multi-point waypoints or direct segment) between coordinates.
class _RouteLinePainter extends CustomPainter {
  final LatLng from;
  final LatLng to;
  final List<LatLng>? waypoints;
  final Color? color;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  _RouteLinePainter({
    required this.from,
    required this.to,
    this.waypoints,
    this.color,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  Offset _toPx(LatLng p, Size size) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final normX = ((p.longitude - minLon) / (maxLon - minLon)).clamp(0.0, 1.0);
    final normY = ((maxLat - p.latitude) / (maxLat - minLat)).clamp(0.0, 1.0);

    return Offset(pad + normX * usableW, pad + normY * usableH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = (color ?? SupraTheme.brand).withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pts = (waypoints != null && waypoints!.length >= 2)
        ? waypoints!
        : [from, to];

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final p = _toPx(pts[i], size);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter old) =>
      old.from != from ||
      old.to != to ||
      old.waypoints != waypoints ||
      old.color != color;
}

class _PinTipPainter extends CustomPainter {
  final Color color;
  _PinTipPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PinTipPainter old) => old.color != color;
}
