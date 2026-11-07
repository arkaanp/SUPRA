import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../config/map_config.dart';
import '../models/location.dart';
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
  });

  @override
  State<InteractiveLocationMap> createState() => _InteractiveLocationMapState();
}

class _InteractiveLocationMapState extends State<InteractiveLocationMap> {
  // Service envelope bounds matching backend validation.
  static const double minLat = -6.9;
  static const double maxLat = -5.8;
  static const double minLon = 106.3;
  static const double maxLon = 107.3;

  LatLng? _currentLocation;
  ml.MapLibreMapController? _mapController;
  late bool _useMapLibre;
  String _mapStyle = MapConfig.cartoPositron;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.selectedLocation;
    _useMapLibre = !widget.forceCanvas && MapConfig.isMapLibreSupported;
  }

  @override
  void didUpdateWidget(covariant InteractiveLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedLocation != oldWidget.selectedLocation) {
      _currentLocation = widget.selectedLocation;
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

      if (loc != null && sec != null) {
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
    _updateMapLibreLayers();
    widget.onLocationChanged?.call(location);
  }

  void animateToLocation(LatLng loc) {
    setState(() => _currentLocation = loc);
    if (_useMapLibre && _mapController != null) {
      _mapController!.animateCamera(
        ml.CameraUpdate.newLatLngZoom(
          ml.LatLng(loc.latitude, loc.longitude),
          13.5,
        ),
      );
      _updateMapLibreLayers();
    }
    widget.onLocationChanged?.call(loc);
  }

  LatLng _pixelToLatLng(Offset localPos, Size size) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final normalizedX = ((localPos.dx - pad) / usableW).clamp(0.0, 1.0);
    final normalizedY = ((localPos.dy - pad) / usableH).clamp(0.0, 1.0);

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
    widget.onLocationChanged?.call(location);
  }

  @override
  Widget build(BuildContext context) {
    final location = _currentLocation ?? widget.selectedLocation;
    final nearest = location != null ? findNearestLandmark(location) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBounded = constraints.maxHeight.isFinite;

        final mapWidget = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: isBounded ? null : widget.height,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: SupraTheme.divider),
              borderRadius: BorderRadius.circular(16),
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
                  )
                else
                  LayoutBuilder(
                    builder: (context, mapConstraints) {
                      final size = mapConstraints.biggest;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _handleCanvasTap(details.localPosition, size),
                        onPanUpdate: (details) =>
                            _handleCanvasTap(details.localPosition, size),
                        child: Stack(
                          children: [
                            // Base vector map canvas.
                            CustomPaint(
                              size: size,
                              painter: _JakartaCanvasPainter(
                                minLat: minLat,
                                maxLat: maxLat,
                                minLon: minLon,
                                maxLon: maxLon,
                                showLandmarks: widget.showLandmarks,
                              ),
                            ),

                            // Connecting route line.
                            if (location != null &&
                                widget.secondaryLocation != null)
                              CustomPaint(
                                size: size,
                                painter: _RouteLinePainter(
                                  from: location,
                                  to: widget.secondaryLocation!,
                                  minLat: minLat,
                                  maxLat: maxLat,
                                  minLon: minLon,
                                  maxLon: maxLon,
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
            if (location != null) ...[
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
                            nearest != null
                                ? '${nearest.name} (${nearest.area})'
                                : 'Selected Point',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: SupraTheme.onSurface,
                            ),
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

    final px = pad + normX * usableW;
    final py = pad + normY * usableH;

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

/// Modal bottom sheet to pick a location using MapLibre GL.
Future<LatLng?> showLocationPickerSheet({
  required BuildContext context,
  LatLng? initialLocation,
  String title = 'Select location on map',
}) async {
  LatLng selected =
      initialLocation ?? const LatLng(latitude: -6.2088, longitude: 106.8456);

  return showModalBottomSheet<LatLng>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final mapKey = GlobalKey<_InteractiveLocationMapState>();

      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
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

                  // Quick preset landmark chips.
                  SizedBox(
                    height: 38,
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
                            setSheetState(() => selected = landmark.point);
                            mapKey.currentState?.animateToLocation(
                              landmark.point,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Interactive MapLibre Map.
                  InteractiveLocationMap(
                    key: mapKey,
                    selectedLocation: selected,
                    onLocationChanged: (newLoc) {
                      setSheetState(() => selected = newLoc);
                    },
                    height: 280,
                  ),
                  const SizedBox(height: 16),

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

/// Draws a dashed route line between from and to coordinates.
class _RouteLinePainter extends CustomPainter {
  final LatLng from;
  final LatLng to;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  _RouteLinePainter({
    required this.from,
    required this.to,
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
    final a = _toPx(from, size);
    final b = _toPx(to, size);

    final linePaint = Paint()
      ..color = SupraTheme.brand.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(a, b, linePaint);
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter old) =>
      old.from != from || old.to != to;
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
