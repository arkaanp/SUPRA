import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as geo;
import 'package:url_launcher/url_launcher.dart';

import '../models/location.dart';
import '../models/environmental_zone.dart';

/// Real geographic basemap for platforms without the MapLibre plugin.
class GeographicTileMap extends StatefulWidget {
  const GeographicTileMap({
    super.key,
    this.selected,
    this.secondary,
    this.points = const [],
    this.color = Colors.blue,
    this.onTap,
    this.samples = const [],
    this.tileProvider,
    this.attributionBottomInset = 0,
  });
  final LatLng? selected;
  final LatLng? secondary;
  final List<LatLng> points;
  final Color color;
  final ValueChanged<LatLng>? onTap;
  final List<EnvironmentalZone> samples;
  final fm.TileProvider? tileProvider;
  final double attributionBottomInset;
  @override
  State<GeographicTileMap> createState() => GeographicTileMapState();
}

class GeographicTileMapState extends State<GeographicTileMap> {
  final controller = fm.MapController();
  bool _ready = false;
  bool _tileError = false;
  int _tileRevision = 0;
  geo.LatLng _geo(LatLng p) => geo.LatLng(p.latitude, p.longitude);
  void centerOn(LatLng p) {
    if (_ready) controller.move(_geo(p), 13.5);
  }

  void fit(List<LatLng> points) {
    if (!_ready || points.isEmpty) return;
    if (points.length == 1) {
      centerOn(points.first);
      return;
    }
    controller.fitCamera(
      fm.CameraFit.bounds(
        bounds: fm.LatLngBounds.fromPoints(points.map(_geo).toList()),
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ),
    );
  }

  void zoom(double delta) {
    if (_ready) {
      controller.move(
        controller.camera.center,
        (controller.camera.zoom + delta).clamp(8, 18),
      );
    }
  }

  void reset() {
    if (_ready) controller.move(const geo.LatLng(-6.2088, 106.8456), 11);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      fm.FlutterMap(
        mapController: controller,
        options: fm.MapOptions(
          initialCenter: _geo(
            widget.selected ??
                const LatLng(latitude: -6.2088, longitude: 106.8456),
          ),
          initialZoom: 11,
          minZoom: 8,
          maxZoom: 18,
          onMapReady: () {
            _ready = true;
            if (widget.points.length >= 2) fit(widget.points);
          },
          onTap: (_, p) {
            final point = LatLng(latitude: p.latitude, longitude: p.longitude);
            if (point.isInGreaterJakarta) widget.onTap?.call(point);
          },
        ),
        children: [
          fm.TileLayer(
            key: ValueKey(_tileRevision),
            tileProvider: widget.tileProvider,
            urlTemplate: const String.fromEnvironment(
              'MAP_TILE_URL',
              defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            userAgentPackageName: 'org.supra.commute',
            errorTileCallback: (_, _, _) {
              if (!_tileError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _tileError = true);
                });
              }
            },
          ),
          if (widget.points.length >= 2)
            fm.PolylineLayer(
              polylines: [
                fm.Polyline(
                  points: widget.points.map(_geo).toList(),
                  strokeWidth: 5,
                  color: widget.color,
                ),
              ],
            ),
          fm.MarkerLayer(
            markers: [
              if (widget.selected != null)
                fm.Marker(
                  point: _geo(widget.selected!),
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.blue,
                    size: 36,
                  ),
                ),
              if (widget.secondary != null)
                fm.Marker(
                  point: _geo(widget.secondary!),
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
              for (final sample in widget.samples.where(
                (s) => s.conditions != null,
              ))
                fm.Marker(
                  point: _geo(sample.center),
                  width: 40,
                  height: 40,
                  child: Tooltip(
                    message:
                        '${sample.descriptiveLabel}\n${sample.healthAdvisory}',
                    child: const Icon(
                      Icons.info_outline,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      Positioned(
        bottom: widget.attributionBottomInset + 4,
        left: 6,
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => launchUrl(
              Uri.parse(
                const String.fromEnvironment(
                  'MAP_ATTRIBUTION_URL',
                  defaultValue: 'https://www.openstreetmap.org/copyright',
                ),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Text(
                String.fromEnvironment(
                  'MAP_ATTRIBUTION_TEXT',
                  defaultValue: '© OpenStreetMap contributors',
                ),
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
      ),
      if (_tileError)
        Positioned(
          top: 48,
          left: 8,
          right: 8,
          child: Material(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Basemap tiles unavailable. Check connection/provider access; pins alone are not a basemap.',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _tileError = false;
                      _tileRevision++;
                    }),
                    child: const Text('Retry basemap'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
