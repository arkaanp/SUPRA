import 'package:flutter/material.dart';

import 'current_conditions.dart';
import 'location.dart';

enum EnvironmentalOverlayMode { all, airQuality, rain }

/// A geographic lookup anchor. A nearby station is not a measured area polygon.
class EnvironmentalZone {
  final String id;
  final String name;
  final LatLng center;
  final double radiusKm;
  final List<LatLng> polygonBounds;
  final double? pm25;
  final double? rainfallMm;
  final double? rainProbability;
  final bool isRaining;
  final bool isCloudy;
  final double? windDirectionDegrees;
  final double? windSpeedKmh;
  final String? weatherDescription;
  final CurrentConditions? conditions;
  const EnvironmentalZone({
    required this.id,
    required this.name,
    required this.center,
    this.radiusKm = 5,
    this.polygonBounds = const [],
    this.pm25,
    this.rainfallMm,
    this.rainProbability,
    this.isRaining = false,
    this.isCloudy = false,
    this.windDirectionDegrees,
    this.windSpeedKmh,
    this.weatherDescription,
    this.conditions,
  });

  String get aqiCategory => pm25 == null ? 'Unavailable' : 'PM2.5, not AQI';
  // No unsupported area-wide interpolation from a single station sample.
  Color get pm25Color => Colors.transparent;
  Color get rainColor => Colors.transparent;
  Color get compositeAreaColor => Colors.transparent;
  Color get solidAqiColor => pm25 == null ? Colors.grey : Colors.blueGrey;

  String get cardinalWindDirection {
    if (windDirectionDegrees == null) return 'Unavailable';
    final d = (windDirectionDegrees! % 360 + 360) % 360;
    return [
      'N',
      'NE',
      'E',
      'SE',
      'S',
      'SW',
      'W',
      'NW',
    ][((d + 22.5) / 45).floor() % 8];
  }

  String get weatherSummary =>
      '${conditions?.weather.agedAt(DateTime.now()).isStale == true ? "STALE · " : ""}'
      '${weatherDescription ?? (rainfallMm == null ? 'Weather unavailable' : 'Precipitation ${rainfallMm!.toStringAsFixed(1)} mm')}';
  String get descriptiveLabel =>
      '$name · $weatherSummary · '
      '${pm25 == null ? "PM2.5 unavailable" : "Station PM2.5 ${pm25!.toStringAsFixed(1)} µg/m³ (not AQI)"}'
      '${conditions == null ? "" : " · ${conditions!.airQuality.source}: ${conditions!.airQuality.status}"}';
  String get healthAdvisory =>
      'Location sample only, not area-wide exposure. '
      '${conditions == null ? "Current conditions unavailable." : "${conditions!.airQuality.message} ${conditions!.weather.message} "
                "Retrieved ${conditions!.retrievedAt.toUtc().toIso8601String()}. "
                "Air valid at ${conditions!.airQuality.validAt?.toUtc().toIso8601String() ?? 'unavailable'}; "
                "weather ${conditions!.weather.source}/${conditions!.weather.kind ?? 'unavailable'} "
                "valid at ${conditions!.weather.validAt?.toUtc().toIso8601String() ?? 'unavailable'}."}';

  bool contains(LatLng point) {
    if (polygonBounds.length < 3) return center.distanceTo(point) <= radiusKm;
    var inside = false;
    for (
      int i = 0, j = polygonBounds.length - 1;
      i < polygonBounds.length;
      j = i++
    ) {
      final a = polygonBounds[i], b = polygonBounds[j];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
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
    CurrentConditions? conditions,
  }) => EnvironmentalZone(
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
    conditions: conditions ?? this.conditions,
  );
}
