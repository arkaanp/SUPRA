import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../config/map_config.dart';
import '../models/environmental_zone.dart';
import '../models/location.dart';
import '../services/environmental_service.dart';
import '../services/geocoding_service.dart';
import '../theme/app_theme.dart';
import 'geographic_tile_map.dart';
import 'route_environment_samples.dart';

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
  final bool showEnvironmentalOverlays;
  final List<EnvironmentalZone>? environmentalZones;
  final bool autoFitRoute;
  final ValueChanged<List<EnvironmentalZone>>? onEnvironmentalSamplesChanged;

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
    this.showEnvironmentalOverlays = true,
    this.environmentalZones,
    this.autoFitRoute = true,
    this.onEnvironmentalSamplesChanged,
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
  final _tileMapKey = GlobalKey<GeographicTileMapState>();
  bool get _useTileMap =>
      !_useMapLibre && !widget.forceCanvas && !MapConfig.isTestEnvironment;
  String _mapStyle = MapConfig.cartoPositron;

  final GeocodingService _geocodingService = GeocodingService();
  String? _resolvedAddress;

  late List<EnvironmentalZone> _environmentalZones;
  EnvironmentalOverlayMode _overlayMode = EnvironmentalOverlayMode.all;
  EnvironmentalZone? _inspectedZone;
  final EnvironmentalService _environmentalService = EnvironmentalService();

  // Canvas pan & zoom state
  Offset _panOffset = Offset.zero;
  double _zoomFactor = 1.0;
  double _baseZoomFactor = 1.0;
  Offset _dragStart = Offset.zero;
  Offset _panStart = Offset.zero;
  bool _isDragging = false;
  Size? _lastCanvasSize;
  Offset? _tapCandidatePos;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.selectedLocation;
    _useMapLibre =
        !widget.forceCanvas &&
        !MapConfig.isTestEnvironment &&
        MapConfig.isMapLibreSupported;
    _environmentalZones =
        widget.environmentalZones ?? EnvironmentalService.defaultZones;
    if (widget.showEnvironmentalOverlays) {
      _refreshEnvironmentalZones();
    }
    if (_currentLocation != null) {
      _resolveAddress(_currentLocation!);
    }
    if (widget.routeWaypoints != null &&
        widget.routeWaypoints!.length >= 2 &&
        widget.autoFitRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) fitToRoute(widget.routeWaypoints!);
      });
    }
  }

  int _environmentGeneration = 0;
  Future<void> _refreshEnvironmentalZones() async {
    final generation = ++_environmentGeneration;
    if (widget.environmentalZones != null) {
      setState(() => _environmentalZones = widget.environmentalZones!);
      return;
    }
    try {
      final path = widget.routeWaypoints;
      final updated = path != null && path.length >= 2
          ? await _environmentalService.fetchRouteData(path)
          : await _environmentalService.fetchLiveZoneData(
              point: _currentLocation,
            );
      if (mounted && generation == _environmentGeneration) {
        setState(() => _environmentalZones = updated);
        widget.onEnvironmentalSamplesChanged?.call(updated);
        if (_useMapLibre && _mapController != null) {
          _updateMapLibreLayers();
        }
      }
    } catch (_) {}
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
    if (oldWidget.onEnvironmentalSamplesChanged == null &&
        widget.onEnvironmentalSamplesChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onEnvironmentalSamplesChanged?.call(_environmentalZones);
        }
      });
    }

    if (widget.showEnvironmentalOverlays &&
        (widget.selectedLocation != oldWidget.selectedLocation ||
            !listEquals(widget.routeWaypoints, oldWidget.routeWaypoints) ||
            widget.environmentalZones != oldWidget.environmentalZones)) {
      _environmentalZones = []; // Do not show the previous route's samples.
      _refreshEnvironmentalZones();
    }
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
      if (widget.routeWaypoints != oldWidget.routeWaypoints &&
          widget.routeWaypoints != null &&
          widget.routeWaypoints!.length >= 2 &&
          widget.autoFitRoute) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) fitToRoute(widget.routeWaypoints!);
        });
      }
    }
  }

  void _onMapCreated(ml.MapLibreMapController controller) {
    _mapController = controller;
    controller.onFillTapped.add((fill) {
      if (widget.isInteractive) {
        final coords = fill.options.geometry?.first;
        if (coords != null && coords.isNotEmpty) {
          double avgLat = 0;
          double avgLon = 0;
          for (final c in coords) {
            avgLat += c.latitude;
            avgLon += c.longitude;
          }
          _handleMapLibreClick(
            ml.LatLng(avgLat / coords.length, avgLon / coords.length),
          );
        }
      }
    });
    controller.onCircleTapped.add((circle) {
      if (widget.isInteractive && circle.options.geometry != null) {
        _handleMapLibreClick(circle.options.geometry!);
      }
    });
    _updateMapLibreLayers();
  }

  Future<void> _updateMapLibreLayers() async {
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.clearCircles();
      await controller.clearSymbols();
      await controller.clearLines();
      await controller.clearFills();

      if (widget.showEnvironmentalOverlays) {
        for (final zone in _environmentalZones) {
          Color areaColor;
          if (_overlayMode == EnvironmentalOverlayMode.airQuality) {
            areaColor = zone.pm25Color;
          } else if (_overlayMode == EnvironmentalOverlayMode.rain) {
            areaColor = zone.isRaining ? zone.rainColor : Colors.transparent;
          } else {
            areaColor = zone.compositeAreaColor;
          }
          if (zone.conditions != null) {
            final c = zone.center;
            const d = 0.003;
            final hex =
                '#${(zone.solidAqiColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
            await controller.addFill(
              ml.FillOptions(
                geometry: [
                  [
                    ml.LatLng(c.latitude - d, c.longitude - d),
                    ml.LatLng(c.latitude + d, c.longitude - d),
                    ml.LatLng(c.latitude + d, c.longitude + d),
                    ml.LatLng(c.latitude - d, c.longitude + d),
                    ml.LatLng(c.latitude - d, c.longitude - d),
                  ],
                ],
                fillColor: hex,
                fillOpacity: 0.20,
                fillOutlineColor: hex,
              ),
            );
            final rain = zone.rainfallMm;
            await controller.addSymbol(
              ml.SymbolOptions(
                geometry: ml.LatLng(c.latitude, c.longitude),
                textField: rain == null
                    ? '☁ —'
                    : '${rain > 0 ? '🌧' : '☁'} ${rain.toStringAsFixed(1)} mm',
                textSize: 11,
                textColor: rain != null && rain > 0 ? '#1565C0' : '#607D8B',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 2,
              ),
            );
          }
          if (areaColor == Colors.transparent) continue;

          final colorHex =
              '#${(areaColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
          await controller.addFill(
            ml.FillOptions(
              geometry: [
                zone.polygonBounds
                    .map((p) => ml.LatLng(p.latitude, p.longitude))
                    .toList(),
              ],
              fillColor: colorHex,
              fillOpacity: areaColor.a,
              fillOutlineColor: colorHex,
            ),
          );
        }
      }

      final loc = _currentLocation ?? widget.selectedLocation;
      if (loc != null) {
        final isStart = widget.selectedLabel == 'S';
        final pinColor = isStart ? '#00AA13' : '#EF4444';
        // Outer glow halo.
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(loc.latitude, loc.longitude),
            circleColor: pinColor,
            circleOpacity: 0.22,
            circleRadius: 18.0,
          ),
        );
        // Primary marker.
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(loc.latitude, loc.longitude),
            circleColor: pinColor,
            circleRadius: 8.0,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 2.5,
          ),
        );
      }

      final sec = widget.secondaryLocation;
      if (sec != null) {
        final isStartSec = widget.secondaryLabel == 'S';
        final secPinColor = isStartSec ? '#00AA13' : '#EF4444';
        await controller.addCircle(
          ml.CircleOptions(
            geometry: ml.LatLng(sec.latitude, sec.longitude),
            circleColor: secPinColor,
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
      }
    } catch (_) {
      // Discard errors during controller reloads.
    }
  }

  void _handleMapLibreClick(ml.LatLng coordinates) {
    if (!widget.isInteractive) return;
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 250) {
      return;
    }
    _lastTapTime = now;
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
    if (_useTileMap) {
      setState(() => _currentLocation = loc);
      _tileMapKey.currentState?.centerOn(loc);
      _resolveAddress(loc);
      return;
    }
    final size = mapSize ?? _lastCanvasSize ?? const Size(400, 300);
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);
    final normX = ((loc.longitude - minLon) / (maxLon - minLon)).clamp(
      0.0,
      1.0,
    );
    final normY = ((maxLat - loc.latitude) / (maxLat - minLat)).clamp(0.0, 1.0);
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

  /// Centers and zooms in/out the view such that the whole route is visible within the viewport.
  void fitToRoute(List<LatLng> points, {Size? mapSize, double padding = 48.0}) {
    if (points.isEmpty) return;
    if (_useTileMap) {
      _tileMapKey.currentState?.fit(points);
      return;
    }

    double routeMinLat = 90.0;
    double routeMaxLat = -90.0;
    double routeMinLon = 180.0;
    double routeMaxLon = -180.0;

    for (final pt in points) {
      if (pt.latitude < routeMinLat) routeMinLat = pt.latitude;
      if (pt.latitude > routeMaxLat) routeMaxLat = pt.latitude;
      if (pt.longitude < routeMinLon) routeMinLon = pt.longitude;
      if (pt.longitude > routeMaxLon) routeMaxLon = pt.longitude;
    }

    // Include selected / secondary locations if present for complete route bounds
    final loc = _currentLocation ?? widget.selectedLocation;
    if (loc != null) {
      if (loc.latitude < routeMinLat) routeMinLat = loc.latitude;
      if (loc.latitude > routeMaxLat) routeMaxLat = loc.latitude;
      if (loc.longitude < routeMinLon) routeMinLon = loc.longitude;
      if (loc.longitude > routeMaxLon) routeMaxLon = loc.longitude;
    }
    final sec = widget.secondaryLocation;
    if (sec != null) {
      if (sec.latitude < routeMinLat) routeMinLat = sec.latitude;
      if (sec.latitude > routeMaxLat) routeMaxLat = sec.latitude;
      if (sec.longitude < routeMinLon) routeMinLon = sec.longitude;
      if (sec.longitude > routeMaxLon) routeMaxLon = sec.longitude;
    }

    final centerLat = (routeMinLat + routeMaxLat) / 2.0;
    final centerLon = (routeMinLon + routeMaxLon) / 2.0;
    final spanLat = (routeMaxLat - routeMinLat).abs();
    final spanLon = (routeMaxLon - routeMinLon).abs();

    // 1. Vector Map Canvas calculation:
    final size = mapSize ?? _lastCanvasSize ?? const Size(400, 300);
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    // Unzoomed pixel span of the route bounding box:
    final routeWidthPx = max(24.0, (spanLon / (maxLon - minLon)) * usableW);
    final routeHeightPx = max(24.0, (spanLat / (maxLat - minLat)) * usableH);

    // Viewport space available for route with padding
    final availW = max(50.0, size.width - (padding * 2));
    final availH = max(50.0, size.height - (padding * 2));

    final zoomX = availW / routeWidthPx;
    final zoomY = availH / routeHeightPx;
    // Optimal zoom factor clamped between 0.75 (zoomed out full region) and 3.2 (close-up)
    final targetZoom = min(zoomX, zoomY).clamp(0.75, 3.2);

    // Center offset calculation
    final normCenterX = ((centerLon - minLon) / (maxLon - minLon)).clamp(
      0.0,
      1.0,
    );
    final normCenterY = ((maxLat - centerLat) / (maxLat - minLat)).clamp(
      0.0,
      1.0,
    );
    final baseCenterX = pad + normCenterX * usableW;
    final baseCenterY = pad + normCenterY * usableH;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final targetPan = Offset(
      -(baseCenterX - centerX) * targetZoom,
      -(baseCenterY - centerY) * targetZoom,
    );

    setState(() {
      _zoomFactor = targetZoom;
      _panOffset = targetPan;
    });

    // 2. MapLibre GL camera animation:
    if (_useMapLibre && _mapController != null) {
      try {
        _mapController!.animateCamera(
          ml.CameraUpdate.newLatLngBounds(
            ml.LatLngBounds(
              southwest: ml.LatLng(routeMinLat, routeMinLon),
              northeast: ml.LatLng(routeMaxLat, routeMaxLon),
            ),
            left: padding,
            top: padding,
            right: padding,
            bottom: padding,
          ),
        );
      } catch (_) {
        final maxSpan = max(spanLat, spanLon);
        double zoom = 11.5;
        if (maxSpan > 0.45) {
          zoom = 9.8;
        } else if (maxSpan > 0.25) {
          zoom = 10.8;
        } else if (maxSpan > 0.12) {
          zoom = 12.0;
        } else if (maxSpan > 0.05) {
          zoom = 13.2;
        } else {
          zoom = 14.5;
        }
        _mapController!.animateCamera(
          ml.CameraUpdate.newLatLngZoom(ml.LatLng(centerLat, centerLon), zoom),
        );
      }
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
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 250) {
      return;
    }
    _lastTapTime = now;
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
                    onMapClick: (point, coordinates) {
                      if (widget.isInteractive) {
                        _handleMapLibreClick(coordinates);
                      }
                    },
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
                    rotateGesturesEnabled: true,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    featureTapsTriggersMapClick: true,
                    annotationConsumeTapEvents: const [
                      ml.AnnotationType.circle,
                      ml.AnnotationType.symbol,
                    ],
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  )
                else if (_useTileMap)
                  GeographicTileMap(
                    key: _tileMapKey,
                    attributionBottomInset: widget.showFooter ? 72 : 0,
                    selected: location,
                    secondary: widget.secondaryLocation,
                    points: widget.routeWaypoints ?? [],
                    color: widget.routeColor ?? SupraTheme.brand,
                    samples: widget.showEnvironmentalOverlays
                        ? _environmentalZones
                        : [],
                    onTap: widget.isInteractive
                        ? (point) {
                            setState(() => _currentLocation = point);
                            widget.onLocationChanged?.call(point);
                          }
                        : null,
                  )
                else
                  LayoutBuilder(
                    builder: (context, mapConstraints) {
                      final size = mapConstraints.biggest;
                      _lastCanvasSize = size;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          _tapCandidatePos = details.localPosition;
                        },
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
                          _tapCandidatePos = details.localFocalPoint;
                        },
                        onScaleUpdate: (details) {
                          final dist =
                              (details.localFocalPoint - _dragStart).distance;
                          if (dist > 6.0 || details.scale != 1.0) {
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
                          if (!_isDragging && _tapCandidatePos != null) {
                            _handleCanvasTap(_tapCandidatePos!, size);
                          }
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) _isDragging = false;
                          });
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
                                      showEnvironmentalOverlays:
                                          widget.showEnvironmentalOverlays,
                                      environmentalZones: _environmentalZones,
                                      overlayMode: _overlayMode,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Environmental zone descriptive badges!
                            if (widget.showEnvironmentalOverlays)
                              for (final zone in _environmentalZones)
                                _buildZoneBadge(zone, size),

                            // Connecting route line: ONLY when routeWaypoints is provided and has >= 2 points!
                            if (widget.routeWaypoints != null &&
                                widget.routeWaypoints!.length >= 2)
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
                                        from: widget.routeWaypoints!.first,
                                        to: widget.routeWaypoints!.last,
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

                            // Floating detailed inspection card when an area is tapped
                            if (_inspectedZone != null)
                              _buildInspectedZoneCard(),
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
                            } else if (_useTileMap) {
                              _tileMapKey.currentState?.zoom(1);
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
                            } else if (_useTileMap) {
                              _tileMapKey.currentState?.zoom(-1);
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
                          tooltip: 'Center on route or location',
                          onPressed: () {
                            if (widget.routeWaypoints != null &&
                                widget.routeWaypoints!.length >= 2) {
                              fitToRoute(widget.routeWaypoints!);
                              return;
                            }
                            final target =
                                _currentLocation ?? widget.selectedLocation;
                            if (target != null) {
                              animateToLocation(target);
                            } else {
                              if (_useTileMap) {
                                _tileMapKey.currentState?.reset();
                              }
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
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
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
                                _useMapLibre
                                    ? Icons.public
                                    : Icons.map_outlined,
                                size: 13,
                                color: SupraTheme.brand,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _useMapLibre
                                    ? 'MapLibre GL'
                                    : _useTileMap
                                    ? 'OpenStreetMap'
                                    : 'Test canvas (no basemap)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: SupraTheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.showEnvironmentalOverlays) ...[
                          const SizedBox(width: 6),
                          PopupMenuButton<EnvironmentalOverlayMode>(
                            tooltip: 'Environmental Overlay Mode',
                            initialValue: _overlayMode,
                            onSelected: (mode) {
                              setState(() => _overlayMode = mode);
                              if (_useMapLibre && _mapController != null) {
                                _updateMapLibreLayers();
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: EnvironmentalOverlayMode.all,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.layers,
                                      size: 16,
                                      color: SupraTheme.brand,
                                    ),
                                    SizedBox(width: 8),
                                    Text('All Overlays (Air + Rain)'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: EnvironmentalOverlayMode.airQuality,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.air,
                                      size: 16,
                                      color: Color(0xFFEF4444),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Air Pollution (PM2.5)'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: EnvironmentalOverlayMode.rain,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.water_drop,
                                      size: 16,
                                      color: Color(0xFF2563EB),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Rain (Precipitation)'),
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _overlayMode ==
                                            EnvironmentalOverlayMode.rain
                                        ? Icons.water_drop
                                        : _overlayMode ==
                                              EnvironmentalOverlayMode
                                                  .airQuality
                                        ? Icons.air
                                        : Icons.cloud_outlined,
                                    size: 13,
                                    color:
                                        _overlayMode ==
                                            EnvironmentalOverlayMode.rain
                                        ? const Color(0xFF2563EB)
                                        : _overlayMode ==
                                              EnvironmentalOverlayMode
                                                  .airQuality
                                        ? const Color(0xFFEF4444)
                                        : SupraTheme.brand,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _overlayMode ==
                                            EnvironmentalOverlayMode.rain
                                        ? 'Rain'
                                        : _overlayMode ==
                                              EnvironmentalOverlayMode
                                                  .airQuality
                                        ? 'PM2.5'
                                        : 'Eco Layers',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: SupraTheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () async {
                              await _refreshEnvironmentalZones();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Location sample lookup completed. Check each source/status; unavailable readings are not substituted.',
                                    ),
                                    duration: Duration(milliseconds: 1500),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.blueGrey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 3.5),
                                  const Text(
                                    'Refresh sample',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: _showAqiLegendDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildLegendDot(const Color(0xFF22C55E)),
                                  const SizedBox(width: 2.5),
                                  _buildLegendDot(const Color(0xFFEAB308)),
                                  const SizedBox(width: 2.5),
                                  _buildLegendDot(const Color(0xFFEF4444)),
                                  const SizedBox(width: 2.5),
                                  _buildLegendDot(const Color(0xFF2563EB)),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Data guide',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: SupraTheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (MapConfig.isMapLibreSupported &&
                            !widget.forceCanvas) ...[
                          const SizedBox(width: 6),
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
                      ],
                    ),
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
                                    ? (nearest.name.toLowerCase().contains(
                                            nearest.area.toLowerCase(),
                                          )
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

  Widget _buildLegendDot(Color color, [String? label]) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        if (label != null) ...[
          const SizedBox(width: 2.5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: SupraTheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildZoneBadge(EnvironmentalZone zone, Size size) {
    const pad = 18.0;
    final usableW = max(1.0, size.width - 2 * pad);
    final usableH = max(1.0, size.height - 2 * pad);

    final normX = ((zone.center.longitude - minLon) / (maxLon - minLon)).clamp(
      0.0,
      1.0,
    );
    final normY = ((maxLat - zone.center.latitude) / (maxLat - minLat)).clamp(
      0.0,
      1.0,
    );

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final baseX = pad + normX * usableW;
    final baseY = pad + normY * usableH;
    final px = (baseX - centerX) * _zoomFactor + centerX + _panOffset.dx;
    final py = (baseY - centerY) * _zoomFactor + centerY + _panOffset.dy;

    if (px < -70 || px > size.width + 70 || py < -30 || py > size.height + 30) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: px - 27,
      top: py - 27,
      width: 54,
      height: 54,
      child: EnvironmentalSampleMarker(sample: zone),
    );
  }

  Widget _buildInspectedZoneCard() {
    final zone = _inspectedZone!;
    return Positioned(
      left: 12,
      right: 12,
      bottom: widget.showFooter ? 60 : 12,
      child: Card(
        elevation: 6,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: zone.solidAqiColor, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: zone.solidAqiColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  zone.isRaining ? Icons.water_drop : Icons.air,
                  color: zone.solidAqiColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          zone.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: zone.solidAqiColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            zone.aqiCategory,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      zone.descriptiveLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: zone.solidAqiColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      zone.healthAdvisory,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SupraTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _inspectedZone = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAqiLegendDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: SupraTheme.brand,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AQI Colors & Rain Guide',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sensors, size: 13, color: Color(0xFF0F766E)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Transparent squares mark individual samples, not measured area coverage. Provider AQI uses the categories below. PM2.5-only samples use labelled concentration bands; missing values are gray.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF334155),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildAqiScaleRow(
                const Color(0xFF22C55E),
                'AQI 0–50',
                'Good',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFFEAB308),
                'AQI 51–100',
                'Moderate',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFFF97316),
                'AQI 101–150',
                'Unhealthy for sensitive groups',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFFEF4444),
                'AQI 151–200',
                'Unhealthy',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFF8B5CF6),
                'AQI 201–300',
                'Very unhealthy',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFF7F1D1D),
                'AQI 301+',
                'Hazardous',
                'Provider-supplied US AQI category.',
              ),
              _buildAqiScaleRow(
                const Color(0xFF2563EB),
                'Rain (mm)',
                'Blue droplet',
                'Precipitation in the provider interval. A cloud with 0.0 mm means zero reported rain; a crossed cloud means unavailable. See cards below transport options for sources and times.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAqiScaleRow(
    Color color,
    String range,
    String title,
    String desc,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      range,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SupraTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  desc,
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
              if (context.mounted && selected == loc) {
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
                        final res = await geocoder.searchPlaces(
                          text,
                          remote: false,
                        );
                        if (context.mounted && searchCtrl.text == text) {
                          setSheetState(() => searchResults = res);
                        }
                      } else {
                        setSheetState(() => searchResults = []);
                      }
                    },
                    onSubmitted: (text) async {
                      try {
                        final res = await geocoder.searchPlaces(text);
                        if (context.mounted && searchCtrl.text == text) {
                          setSheetState(() => searchResults = res);
                          if (res.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No matching locations. Choose on the map.',
                                ),
                              ),
                            );
                          }
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$error')));
                        }
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
/// arterial tollways, reference cities/landmarks, and environmental areas.
class _JakartaCanvasPainter extends CustomPainter {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final bool showLandmarks;
  final bool showEnvironmentalOverlays;
  final List<EnvironmentalZone> environmentalZones;
  final EnvironmentalOverlayMode overlayMode;

  _JakartaCanvasPainter({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.showLandmarks,
    this.showEnvironmentalOverlays = true,
    this.environmentalZones = const [],
    this.overlayMode = EnvironmentalOverlayMode.all,
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

    // 2.5 Environmental Area Fills (Air Pollution & Rain)
    if (showEnvironmentalOverlays) {
      for (final zone in environmentalZones) {
        if (zone.polygonBounds.isEmpty) continue;
        final path = Path();
        for (int i = 0; i < zone.polygonBounds.length; i++) {
          final pt = _toPx(
            zone.polygonBounds[i].latitude,
            zone.polygonBounds[i].longitude,
            size,
          );
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();

        // Area color: darker the more bad PM2.5 is; rain blue if raining
        Color areaColor;
        if (overlayMode == EnvironmentalOverlayMode.airQuality) {
          areaColor = zone.pm25Color;
        } else if (overlayMode == EnvironmentalOverlayMode.rain) {
          areaColor = zone.isRaining ? zone.rainColor : Colors.transparent;
        } else {
          areaColor = zone.compositeAreaColor;
        }

        if (areaColor != Colors.transparent) {
          canvas.drawPath(path, Paint()..color = areaColor);
        }

        // Zone perimeter border (whisper-thin, barely visible)
        canvas.drawPath(
          path,
          Paint()
            ..color = zone.solidAqiColor.withValues(alpha: 0.035)
            ..strokeWidth = 0.5
            ..style = PaintingStyle.stroke,
        );

        // Active rain streaks pattern if raining
        if ((overlayMode == EnvironmentalOverlayMode.all ||
                overlayMode == EnvironmentalOverlayMode.rain) &&
            zone.isRaining) {
          _drawRainStreaks(canvas, path, size);
        }
      }
    }

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

  void _drawRainStreaks(Canvas canvas, Path clipPath, Size size) {
    canvas.save();
    canvas.clipPath(clipPath);

    final rainPaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.05)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final bounds = clipPath.getBounds();
    const spacing = 16.0;
    const streakLen = 8.0;
    const angleX = 3.5;

    for (double y = bounds.top - 10; y <= bounds.bottom + 10; y += spacing) {
      for (double x = bounds.left - 10; x <= bounds.right + 10; x += spacing) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + angleX, y + streakLen),
          rainPaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JakartaCanvasPainter old) =>
      old.showLandmarks != showLandmarks ||
      old.showEnvironmentalOverlays != showEnvironmentalOverlays ||
      old.environmentalZones != environmentalZones ||
      old.overlayMode != overlayMode;
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
    if (waypoints == null || waypoints!.length < 2) return;

    final linePaint = Paint()
      ..color = (color ?? SupraTheme.brand).withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pts = waypoints!;

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
