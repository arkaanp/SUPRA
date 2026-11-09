import 'location.dart';
import 'current_conditions.dart';

/// Supported modes of transportation in Greater Jakarta.
enum TransportMode { car, motorcycle, publicTransit, walk }

extension TransportModeExtension on TransportMode {
  String get apiValue => switch (this) {
    TransportMode.publicTransit => 'public_transit',
    _ => name,
  };
  String get displayName {
    switch (this) {
      case TransportMode.car:
        return 'Car / Taxi';
      case TransportMode.motorcycle:
        return 'Motorcycle';
      case TransportMode.publicTransit:
        return 'Public Transit';
      case TransportMode.walk:
        return 'Walking';
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
      case TransportMode.walk:
        return 'Walk';
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
      case TransportMode.walk:
        return '🚶';
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
  final double? predictedAqi;
  final double? pm25UgM3;
  final double? rainfallMm;
  final double? rainProbability;
  final double? trafficDensity;
  final CurrentConditions? conditions;

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
    this.predictedAqi,
    this.pm25UgM3,
    this.rainfallMm,
    this.rainProbability,
    this.trafficDensity,
    this.conditions,
  });

  String get formattedDuration {
    final minutes = estimatedDuration.inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours hr' : '$hours hr $remaining min';
  }

  RouteOption withAdvice({
    required bool recommended,
    required String reason,
    required List<String> risks,
    required List<String> items,
  }) => RouteOption(
    mode: mode,
    title: title,
    estimatedDuration: estimatedDuration,
    distanceKm: distanceKm,
    waypoints: waypoints,
    turnSteps: turnSteps,
    isRecommended: recommended,
    recommendationReason: reason,
    identifiedRisks: risks,
    protectiveMeasures: items,
    predictedAqi: predictedAqi,
    pm25UgM3: pm25UgM3,
    rainfallMm: rainfallMm,
    rainProbability: rainProbability,
    trafficDensity: trafficDensity,
    conditions: conditions,
  );

  String get aqiCategory {
    return pm25UgM3 == null ? 'Unavailable' : 'Station PM2.5, not AQI';
  }

  String get pm25Label => pm25UgM3 == null
      ? 'PM2.5 unavailable'
      : '${conditions?.airQuality.agedAt(DateTime.now()).isStale == true ? "STALE · " : ""}PM2.5: ${pm25UgM3!.toStringAsFixed(1)} µg/m³ (origin station, not AQI)';
  String get rainLabel => rainfallMm == null
      ? 'Rainfall unavailable'
      : '${conditions?.weather.agedAt(DateTime.now()).isStale == true ? "STALE · " : ""}Precipitation: ${rainfallMm!.toStringAsFixed(1)} mm (origin)';
  String get provenanceLabel {
    final c = conditions;
    if (c == null) return 'Environmental source metadata unavailable';
    String label(ConditionSignal s) =>
        '${s.source}: ${s.status} · ${s.kind ?? "no data"}'
        '${s.validAt == null ? "" : " · ${s.validAt!.toUtc().toIso8601String()}"} · ${s.message}';
    final station = c.airQuality.data;
    final licenses = station?['licenses'] as List? ?? [];
    return '${label(c.airQuality)}\n${label(c.weather)}\n${label(c.traffic)}\n'
        '${station == null ? "" : "Station: ${station['station_name'] ?? 'unnamed'} · ${station['distance_km'] ?? 'unknown'} km away\n"}'
        '${licenses.map((l) => "License: ${l['name'] ?? 'see source terms'} · ${l['attribution']?['name'] ?? ''}").join('\n')}'
        '\nRetrieved ${c.retrievedAt.toUtc().toIso8601String()} · nearest-road traffic, not route-wide. '
        'Sources: openaq.org · open-meteo.com · tomtom.com';
  }

  String get trafficCategory {
    if (trafficDensity == null) return 'Route traffic unavailable';
    if (trafficDensity! < 0.35) return 'Free Flow';
    if (trafficDensity! < 0.65) return 'Moderate Traffic';
    return 'Heavy Gridlock';
  }
}
