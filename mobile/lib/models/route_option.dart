import 'location.dart';
import 'current_conditions.dart';
import 'transit_journey.dart';

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
        return 'Mobil / Taksi';
      case TransportMode.motorcycle:
        return 'Motor';
      case TransportMode.publicTransit:
        return 'Transportasi umum';
      case TransportMode.walk:
        return 'Jalan kaki';
    }
  }

  String get shortName {
    switch (this) {
      case TransportMode.car:
        return 'Mobil';
      case TransportMode.motorcycle:
        return 'Motor';
      case TransportMode.publicTransit:
        return 'Transportasi umum';
      case TransportMode.walk:
        return 'Jalan kaki';
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
  final TransitJourney? transitJourney;
  final bool isRecommended;
  final String recommendationReason;
  final String? routingSource;
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
    this.transitJourney,
    this.isRecommended = false,
    required this.recommendationReason,
    this.routingSource,
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
    if (minutes < 60) return '$minutes menit';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours jam' : '$hours jam $remaining menit';
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
    transitJourney: transitJourney,
    isRecommended: recommended,
    recommendationReason: reason,
    routingSource: routingSource,
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
    return pm25UgM3 == null ? 'Tidak tersedia' : 'PM2.5 stasiun, bukan AQI';
  }

  String get pm25Label => pm25UgM3 == null
      ? 'PM2.5 tidak tersedia'
      : '${conditions?.airQuality.agedAt(DateTime.now()).isStale == true ? "DATA LAMA · " : ""}PM2.5: ${pm25UgM3!.toStringAsFixed(1)} µg/m³ (stasiun lokasi awal, bukan AQI)';
  String get rainLabel => rainfallMm == null
      ? 'Curah hujan tidak tersedia'
      : '${conditions?.weather.agedAt(DateTime.now()).isStale == true ? "DATA LAMA · " : ""}Curah hujan: ${rainfallMm!.toStringAsFixed(1)} mm (lokasi awal)';
  String get provenanceLabel => [
    ?routingSource,
    conditions?.sourceDetails ??
        'Informasi sumber kondisi lingkungan tidak tersedia',
  ].join('\n\n');

  String get trafficCategory {
    if (trafficDensity == null) return 'Lalu lintas rute tidak tersedia';
    if (trafficDensity! < 0.35) return 'Lancar';
    if (trafficDensity! < 0.65) return 'Lalu lintas sedang';
    return 'Kemacetan parah';
  }
}
