import 'package:flutter/material.dart';

import 'current_conditions.dart';
import 'location.dart';
import 'prediction.dart';
import '../utils/display_text.dart';
import '../widgets/weather_icon.dart';

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
    final aqiReading = conditions?.aqiSignal.agedAt(DateTime.now());
    final aqi = usAqi;
    final temperature = weather?.number('temperature_c');
    final airText = aqi != null
        ? 'AQI ${aqi.round()}'
        : pm25 != null
        ? 'PM2.5 ${pm25!.round()}'
        : 'Kualitas udara tidak tersedia';
    final weatherText = temperature != null
        ? '${temperature.round()}°C'
        : 'Cuaca tidak tersedia';
    final description = weather?.data?['description'];
    final rain = weather?.number('precipitation_mm');
    final detail = [
      if (description is String && description.isNotEmpty)
        weatherPresentation(description: description).$1,
      if (rain != null) '${rain.toStringAsFixed(1)} mm',
      if (weather?.kind == 'provider_forecast') 'Prakiraan',
    ].join(' · ');
    final label = (aqi != null ? aqiReading : air)?.kind == 'model_estimate'
        ? 'model'
        : 'stasiun';
    return '$name · $airText ($label)${(aqi != null ? aqiReading : air)?.isStale == true ? " DATA LAMA" : ""}\n$weatherText $detail${weather?.isStale == true ? " DATA LAMA" : ""}';
  }

  String get aqiCategory =>
      pm25 == null ? 'Tidak tersedia' : 'PM2.5, bukan AQI';
  // No unsupported area-wide interpolation from a single station sample.
  Color get pm25Color => Colors.transparent;
  Color get rainColor => Colors.transparent;
  Color get compositeAreaColor => Colors.transparent;
  double? get usAqi => conditions?.aqiSignal.usAqi;
  int? get _colorBand {
    if (usAqi != null) return aqiLevel(usAqi!).index;
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
      ? 'Tidak tersedia'
      : usAqi != null
      ? AqiLevel.values[_colorBand!].label()
      : 'Rentang PM2.5 · ${['Rendah', 'Sedang', 'Meningkat', 'Tinggi', 'Sangat tinggi', 'Ekstrem'][_colorBand!]}';

  String get cardinalWindDirection {
    if (windDirectionDegrees == null) return 'Tidak tersedia';
    final d = (windDirectionDegrees! % 360 + 360) % 360;
    return [
      'U',
      'TL',
      'T',
      'TG',
      'S',
      'BD',
      'B',
      'BL',
    ][((d + 22.5) / 45).floor() % 8];
  }

  String get weatherSummary =>
      '${conditions?.weather.agedAt(DateTime.now()).isStale == true ? "DATA LAMA · " : ""}'
      '${weatherDescription == null ? (rainfallMm == null ? 'Cuaca tidak tersedia' : 'Curah hujan ${rainfallMm!.toStringAsFixed(1)} mm') : weatherPresentation(description: weatherDescription).$1}';
  String get descriptiveLabel =>
      '$name · $weatherSummary · '
      '${pm25 == null ? "PM2.5 tidak tersedia" : "${conditions?.airQuality.kind == "model_estimate" ? "Model" : "Stasiun"} PM2.5 ${pm25!.toStringAsFixed(1)} µg/m³ (bukan AQI)"}'
      '${conditions == null ? "" : " · ${signalStatusLabel(conditions!.airQuality.status)}"}';
  String get healthAdvisory =>
      'Data titik lokasi, bukan paparan seluruh wilayah. '
      '${conditions == null ? "Kondisi terkini tidak tersedia." : "${conditions!.airQuality.message} ${conditions!.weather.message} "
                "Diperiksa ${conditions!.retrievedAt.toUtc().toIso8601String()}. "
                "Data udara berlaku pada ${conditions!.airQuality.validAt?.toUtc().toIso8601String() ?? 'unavailable'}; "
                "cuaca ${conditions!.weather.providerLabel}/${signalKindLabel(conditions!.weather.kind)} "
                "berlaku pada ${conditions!.weather.validAt?.toUtc().toIso8601String() ?? 'unavailable'}."}';

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
