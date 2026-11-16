import 'package:flutter/material.dart';

import 'current_conditions.dart';
import 'location.dart';
import 'prediction.dart';

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

  String get mapLabel {
    final air = conditions?.airQuality.agedAt(DateTime.now());
    final weather = conditions?.weather.agedAt(DateTime.now());
    final aqi = air?.number('aqi');
    final temperature = weather?.number('temperature_c');
    final airText = aqi != null
        ? 'AQI ${aqi.round()}'
        : pm25 != null
        ? 'PM2.5 ${pm25!.round()}'
        : 'Air unavailable';
    final weatherText = temperature != null
        ? '${temperature.round()}°C'
        : 'Weather unavailable';
    final description = weather?.data?['description'];
    final rain = weather?.number('precipitation_mm');
    final detail =
        description ?? (rain != null ? '${rain.toStringAsFixed(1)} mm' : '');
    final label = air?.kind == 'model_estimate' ? 'model' : 'station';
    return '$name · $airText ($label)${air?.isStale == true ? " STALE" : ""}\n$weatherText $detail${weather?.isStale == true ? " STALE" : ""}';
  }

  String get aqiCategory => pm25 == null ? 'Unavailable' : 'PM2.5, not AQI';
  // No unsupported area-wide interpolation from a single station sample.
  Color get pm25Color => Colors.transparent;
  Color get rainColor => Colors.transparent;
  Color get compositeAreaColor => Colors.transparent;
  double? get _suppliedAqi => conditions?.airQuality.number('aqi');
  int? get _colorBand {
    if (_suppliedAqi != null) return aqiLevel(_suppliedAqi!).index;
    if (pm25 == null) return null;
    // Concentration bands for display only; no AQI value is derived.
    if (pm25! <= 9) return 0;
    if (pm25! <= 35.4) return 1;
    if (pm25! <= 55.4) return 2;
    if (pm25! <= 125.4) return 3;
    if (pm25! <= 225.4) return 4;
    return 5;
  }

  Color get solidAqiColor =>
      _colorBand == null ? Colors.grey : AqiLevel.values[_colorBand!].color();
  String get colorBandLabel => _colorBand == null
      ? 'Unavailable'
      : _suppliedAqi != null
      ? AqiLevel.values[_colorBand!].label()
      : 'PM2.5 band · ${['Low', 'Moderate', 'Elevated', 'High', 'Very high', 'Extreme'][_colorBand!]}';

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
      '${pm25 == null ? "PM2.5 unavailable" : "${conditions?.airQuality.kind == "model_estimate" ? "Model" : "Station"} PM2.5 ${pm25!.toStringAsFixed(1)} µg/m³ (not AQI)"}'
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
