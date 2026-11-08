import 'location.dart';

/// Supported modes of transportation in Greater Jakarta.
enum TransportMode { car, motorcycle, publicTransit }

extension TransportModeExtension on TransportMode {
  String get displayName {
    switch (this) {
      case TransportMode.car:
        return 'Car / Taxi';
      case TransportMode.motorcycle:
        return 'Motorcycle';
      case TransportMode.publicTransit:
        return 'Public Transit';
    }
  }

  String get shortName {
    switch (this) {
      case TransportMode.car:
        return 'Car';
      case TransportMode.motorcycle:
        return 'Motor';
      case TransportMode.publicTransit:
        return 'Transit';
    }
  }

  String get iconEmoji {
    switch (this) {
      case TransportMode.car:
        return '🚗';
      case TransportMode.motorcycle:
        return '🏍️';
      case TransportMode.publicTransit:
        return '🚆';
    }
  }
}

/// A road-accurate route option for a specific transportation mode,
/// evaluated against current weather, air pollution (PM2.5), and traffic.
class RouteOption {
  final TransportMode mode;
  final String title;
  final Duration estimatedDuration;
  final double distanceKm;
  final List<LatLng> waypoints;
  final List<String> turnSteps;
  final bool isRecommended;
  final String recommendationReason;
  final List<String> identifiedRisks;
  final List<String> protectiveMeasures;

  // Environmental impact indicators
  final double predictedAqi;
  final double pm25UgM3;
  final double rainfallMm;
  final double rainProbability;
  final double trafficDensity; // 0.0 (free) to 1.0 (gridlock)

  const RouteOption({
    required this.mode,
    required this.title,
    required this.estimatedDuration,
    required this.distanceKm,
    required this.waypoints,
    this.turnSteps = const [],
    this.isRecommended = false,
    required this.recommendationReason,
    required this.identifiedRisks,
    required this.protectiveMeasures,
    required this.predictedAqi,
    required this.pm25UgM3,
    required this.rainfallMm,
    required this.rainProbability,
    required this.trafficDensity,
  });

  String get formattedDuration {
    final minutes = estimatedDuration.inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours hr' : '$hours hr $remaining min';
  }

  String get aqiCategory {
    if (pm25UgM3 <= 12.0) return 'Good';
    if (pm25UgM3 <= 35.4) return 'Moderate';
    if (pm25UgM3 <= 55.4) return 'Unhealthy for Sensitive Groups';
    if (pm25UgM3 <= 150.4) return 'Unhealthy';
    if (pm25UgM3 <= 250.4) return 'Very Unhealthy';
    return 'Hazardous';
  }

  String get trafficCategory {
    if (trafficDensity < 0.35) return 'Free Flow';
    if (trafficDensity < 0.65) return 'Moderate Traffic';
    return 'Heavy Gridlock';
  }
}
