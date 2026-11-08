import 'package:flutter/material.dart';

import 'location.dart';

/// Display mode for map environmental indicators.
enum EnvironmentalOverlayMode {
  all,
  airQuality,
  rain,
}

/// Represents a distinct environmental region (e.g. Jakarta Selatan, Cibinong, Kota Bogor)
/// with area polygon boundaries, live PM2.5 particulate pollution, rainfall precipitation,
/// severity color gradations, and contextual health advisories.
class EnvironmentalZone {
  final String id;
  final String name;
  final LatLng center;
  final double radiusKm;
  final List<LatLng> polygonBounds;
  final double pm25;
  final double rainfallMm;
  final double rainProbability;
  final bool isRaining;
  final bool isCloudy;
  final double windDirectionDegrees; // Meteorological angle: 0 = N, 90 = E, 180 = S, 270 = W
  final double windSpeedKmh;
  final String? weatherDescription;

  const EnvironmentalZone({
    required this.id,
    required this.name,
    required this.center,
    this.radiusKm = 5.0,
    this.polygonBounds = const [],
    required this.pm25,
    required this.rainfallMm,
    this.rainProbability = 0.0,
    this.isRaining = false,
    this.isCloudy = false,
    this.windDirectionDegrees = 90.0,
    this.windSpeedKmh = 12.0,
    this.weatherDescription,
  });

  /// AQI category based on US EPA / Indonesian ISPU standards.
  String get aqiCategory {
    if (pm25 <= 12.0) return 'Good';
    if (pm25 <= 35.4) return 'Moderate';
    if (pm25 <= 55.4) return 'Unhealthy for Sensitive Groups';
    if (pm25 <= 150.4) return 'Unhealthy';
    if (pm25 <= 250.4) return 'Very Unhealthy';
    return 'Hazardous';
  }

  /// Calculates the area fill color for air pollution.
  /// Rule: "and the color should get darker the more bad it is."
  /// Visible, translucent overlay so conditions are clear while streets stay discernible.
  Color get pm25Color {
    if (pm25 <= 12.0) {
      // Good: Green (clean, subtle green)
      return const Color(0xFF22C55E).withValues(alpha: 0.22);
    } else if (pm25 <= 35.4) {
      // Moderate: Amber / Yellow
      return const Color(0xFFEAB308).withValues(alpha: 0.30);
    } else if (pm25 <= 55.4) {
      // Unhealthy for Sensitive Groups: Deep Orange
      return const Color(0xFFF97316).withValues(alpha: 0.40);
    } else if (pm25 <= 150.4) {
      // Unhealthy: Red (progressively darker red as PM2.5 climbs from 55 to 150)
      final factor = ((pm25 - 55.4) / 95.0).clamp(0.0, 1.0);
      final r = (239 - (factor * 75)).round(); // 239 -> 164 (dark ruby red)
      final g = (68 - (factor * 42)).round();   // 68 -> 26
      final b = (68 - (factor * 42)).round();   // 68 -> 26
      final alpha = (0.42 * 255 + factor * 0.20 * 255).round(); // ~0.42 to 0.62
      return Color.fromARGB(alpha, r, g, b);
    } else if (pm25 <= 250.4) {
      // Very Unhealthy: Deep Dark Purple
      final factor = ((pm25 - 150.4) / 100.0).clamp(0.0, 1.0);
      final r = (107 - (factor * 40)).round(); // 107 -> 67
      final g = (33 - (factor * 20)).round();   // 33 -> 13
      final b = (168 - (factor * 60)).round();  // 168 -> 108
      return Color.fromARGB(160, r, g, b);
    } else {
      // Hazardous: Deep Dark Maroon
      return const Color(0xFF4C0519).withValues(alpha: 0.70);
    }
  }

  /// Solid border / badge color matching the AQI severity.
  Color get solidAqiColor {
    if (pm25 <= 12.0) return const Color(0xFF16A34A);
    if (pm25 <= 35.4) return const Color(0xFFCA8A04);
    if (pm25 <= 55.4) return const Color(0xFFEA580C);
    if (pm25 <= 150.4) {
      final factor = ((pm25 - 55.4) / 95.0).clamp(0.0, 1.0);
      return Color.fromARGB(
        255,
        (220 - factor * 70).round(),
        (38 - factor * 25).round(),
        (38 - factor * 25).round(),
      );
    }
    if (pm25 <= 250.4) return const Color(0xFF6B21A8);
    return const Color(0xFF4C0519);
  }

  /// Atmospheric translucent blue for rain areas, getting darker with rainfall rate.
  Color get rainColor {
    if (!isRaining && rainfallMm <= 0.2) return Colors.transparent;
    final intensity = (rainfallMm / 10.0).clamp(0.0, 1.0);
    final r = (37 - (intensity * 20)).round();
    final g = (99 - (intensity * 40)).round();
    final b = (235 - (intensity * 45)).round();
    final alpha = (0.35 * 255 + intensity * 0.25 * 255).round(); // ~0.35 to 0.60
    return Color.fromARGB(alpha, r, g, b);
  }

  /// Combined visual color for the area on the map.
  Color get compositeAreaColor {
    if ((isRaining || rainfallMm > 0.5) && rainfallMm > 0.2) {
      return Color.alphaBlend(rainColor, pm25Color);
    }
    return pm25Color;
  }

  /// Returns human-readable 8-point compass cardinal direction (e.g. N, NE, E, SE, S, SW, W, NW).
  String get cardinalWindDirection {
    final deg = (windDirectionDegrees % 360 + 360) % 360;
    if (deg >= 337.5 || deg < 22.5) return 'N';
    if (deg < 67.5) return 'NE';
    if (deg < 112.5) return 'E';
    if (deg < 157.5) return 'SE';
    if (deg < 202.5) return 'S';
    if (deg < 247.5) return 'SW';
    if (deg < 292.5) return 'W';
    return 'NW';
  }

  /// Concise weather description (Rainy, Cloudy, or Sunny).
  String get weatherSummary {
    if (weatherDescription != null && weatherDescription!.isNotEmpty) {
      return weatherDescription!;
    }
    if (isRaining || rainfallMm > 0.5) return 'Rainy';
    if (isCloudy) return 'Cloudy';
    return 'Sunny';
  }

  /// Human-readable descriptive text showing weather condition, wind, PM2.5 and rain.
  String get descriptiveLabel {
    final hasRain = isRaining || rainfallMm > 0.5;
    final weatherText = hasRain
        ? '🌧️ ${rainfallMm.toStringAsFixed(1)} mm'
        : (isCloudy ? '☁️ Cloudy' : '☀️ Sunny');
    final windText = '💨 $cardinalWindDirection ${windSpeedKmh.toStringAsFixed(0)} km/h';
    return '$name · $weatherText · $windText · ${pm25.toStringAsFixed(0)} µg/m³ ($aqiCategory)';
  }

  /// Contextual health and protection advisory for this region.
  String get healthAdvisory {
    final hasRain = isRaining || rainfallMm > 0.5;
    if (pm25 >= 55.5) {
      return 'Air quality is Unhealthy (${pm25.toStringAsFixed(0)} µg/m³). Wear an N95 respirator mask outdoors. Keep car windows closed with AC recirculation ON.';
    } else if (pm25 >= 35.5) {
      return 'Elevated PM2.5 (${pm25.toStringAsFixed(0)} µg/m³). Sensitive groups should reduce prolonged outdoor exertion. Motorcyclists should wear face masks.';
    } else if (hasRain) {
      return 'Active rainfall (${rainfallMm.toStringAsFixed(1)} mm). Wet pavement and slippery markings. Equip rain gear and increase following distance.';
    } else {
      return 'Air quality is acceptable. Safe for outdoor commuting and open ventilation.';
    }
  }

  /// Checks if a geographic coordinate falls inside this zone's polygon bounds.
  bool contains(LatLng point) {
    if (polygonBounds.length < 3) {
      return center.distanceTo(point) <= radiusKm;
    }
    bool inside = false;
    for (int i = 0, j = polygonBounds.length - 1; i < polygonBounds.length; j = i++) {
      final xi = polygonBounds[i].longitude;
      final yi = polygonBounds[i].latitude;
      final xj = polygonBounds[j].longitude;
      final yj = polygonBounds[j].latitude;

      final intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside || (center.distanceTo(point) <= (radiusKm * 0.8));
  }

  EnvironmentalZone copyWith({
    double? pm25,
    double? rainfallMm,
    double? rainProbability,
    bool? isRaining,
    bool? isCloudy,
    double? windDirectionDegrees,
    double? windSpeedKmh,
    String? weatherDescription,
  }) {
    return EnvironmentalZone(
      id: id,
      name: name,
      center: center,
      radiusKm: radiusKm,
      polygonBounds: polygonBounds,
      pm25: pm25 ?? this.pm25,
      rainfallMm: rainfallMm ?? this.rainfallMm,
      rainProbability: rainProbability ?? this.rainProbability,
      isRaining: isRaining ?? this.isRaining,
      isCloudy: isCloudy ?? this.isCloudy,
      windDirectionDegrees: windDirectionDegrees ?? this.windDirectionDegrees,
      windSpeedKmh: windSpeedKmh ?? this.windSpeedKmh,
      weatherDescription: weatherDescription ?? this.weatherDescription,
    );
  }
}
