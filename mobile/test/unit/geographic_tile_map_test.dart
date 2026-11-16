import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/widgets/geographic_tile_map.dart';

class _FixtureTiles extends fm.TileProvider {
  final requests = <fm.TileCoordinates>[];
  @override
  ImageProvider getImage(fm.TileCoordinates coordinates, fm.TileLayer options) {
    requests.add(coordinates);
    // Tiny deterministic image fixture: tests renderer/camera, not live tile access.
    return MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
    );
  }
}

void main() {
  testWidgets(
    'Desktop renderer requests geographic tiles and supports coordinate selection/zoom',
    (tester) async {
      final provider = _FixtureTiles();
      final key = GlobalKey<GeographicTileMapState>();
      LatLng? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: GeographicTileMap(
                key: key,
                tileProvider: provider,
                onTap: (p) => selected = p,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.requests, isNotEmpty);
      expect(find.byType(fm.TileLayer), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      final before = key.currentState!.controller.camera.zoom;
      key.currentState!.zoom(1);
      await tester.pumpAndSettle();
      expect(key.currentState!.controller.camera.zoom, before + 1);
      await tester.tap(find.byType(fm.FlutterMap));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, isNotNull);
      expect(selected!.isInGreaterJakarta, true);
      expect(
        selected!.distanceTo(
          const LatLng(latitude: -6.2088, longitude: 106.8456),
        ),
        lessThan(0.1),
      );
    },
  );
}
