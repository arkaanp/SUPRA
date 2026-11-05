import 'package:flutter/material.dart';

/// AQI bands (US EPA) used to color-code forecasts and chat advice.
enum AqiLevel { good, moderate, usg, unhealthy, veryUnhealthy, hazardous }

AqiLevel aqiLevel(double aqi) {
  if (aqi <= 50) return AqiLevel.good;
  if (aqi <= 100) return AqiLevel.moderate;
  if (aqi <= 150) return AqiLevel.usg;
  if (aqi <= 200) return AqiLevel.unhealthy;
  if (aqi <= 300) return AqiLevel.veryUnhealthy;
  return AqiLevel.hazardous;
}

extension AqiLevelExtensions on AqiLevel {
  Color color() {
    switch (this) {
      case AqiLevel.good:
        return const Color(0xFF22C55E);
      case AqiLevel.moderate:
        return const Color(0xFFEAB308);
      case AqiLevel.usg:
        return const Color(0xFFF97316);
      case AqiLevel.unhealthy:
        return const Color(0xFFEF4444);
      case AqiLevel.veryUnhealthy:
        return const Color(0xFF8B5CF6);
      case AqiLevel.hazardous:
        return const Color(0xFF7F1D1D);
    }
  }

  String label() {
    switch (this) {
      case AqiLevel.good:
        return 'Good';
      case AqiLevel.moderate:
        return 'Moderate';
      case AqiLevel.usg:
        return 'Unhealthy for Sensitive';
      case AqiLevel.unhealthy:
        return 'Unhealthy';
      case AqiLevel.veryUnhealthy:
        return 'Very Unhealthy';
      case AqiLevel.hazardous:
        return 'Hazardous';
    }
  }
}

/// One hourly prediction for a route (ERD entity PREDICTION).
class Prediction {
  final String id;
  final String routeId;
  final DateTime targetTime;
  final double predictedAqi;

  /// Rain probability, 0.0 - 1.0.
  final double predictedRainfallProbability;

  /// Traffic density, 0.0 - 1.0.
  final double predictedTrafficDensity;
  final DateTime generatedAt;

  const Prediction({
    required this.id,
    required this.routeId,
    required this.targetTime,
    required this.predictedAqi,
    required this.predictedRainfallProbability,
    required this.predictedTrafficDensity,
    required this.generatedAt,
  });

  AqiLevel get aqiBand => aqiLevel(predictedAqi);

  String get timeLabel =>
      '${targetTime.hour.toString().padLeft(2, '0')}:${targetTime.minute.toString().padLeft(2, '0')}';

  String get rainLabel {
    final pct = (predictedRainfallProbability * 100).round();
    if (pct <= 20) return 'Low';
    if (pct <= 60) return 'Moderate';
    return 'High';
  }

  String get trafficLabel {
    final pct = (predictedTrafficDensity * 100).round();
    if (pct <= 40) return 'Free flow';
    if (pct <= 70) return 'Moderate';
    return 'Heavy';
  }
}
