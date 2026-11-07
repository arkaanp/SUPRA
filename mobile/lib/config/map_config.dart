import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Configuration and basemap styles for MapLibre GL.
abstract final class MapConfig {
  /// Carto Positron: clean, light, modern vector basemap ideal for urban data visualization.
  static const String cartoPositron =
      'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

  /// Carto Voyager: high-detail vector basemap showing parks, POIs, and transit corridors.
  static const String cartoVoyager =
      'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json';

  /// MapLibre official demo tiles.
  static const String demoTiles = 'https://demotiles.maplibre.org/style.json';

  /// Default basemap style for SUPRA.
  static const String defaultStyle = cartoPositron;

  /// Default center coordinates: Monas / Central Jakarta.
  static const double defaultLat = -6.2088;
  static const double defaultLon = 106.8456;
  static const double defaultZoom = 11.0;

  /// Returns true if MapLibre GL native/web platform views are supported in the current runtime.
  static bool get isMapLibreSupported {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return !isTestEnvironment;
    }
    return false;
  }

  /// Returns true if running within a widget or unit test runner.
  static bool get isTestEnvironment {
    try {
      if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
        return true;
      }
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      return bindingName.contains('Test');
    } catch (_) {
      return false;
    }
  }
}
