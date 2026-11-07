import '../models/environmental_zone.dart';
import '../models/location.dart';
import 'routing_service.dart';

/// Service responsible for managing area-based air pollution (PM2.5) and rainfall
/// environmental zones across Greater Jakarta (Jabodetabek).
class EnvironmentalService {
  final RoutingService? routingService;

  EnvironmentalService({this.routingService});

  /// 10 canonical Greater Jakarta metropolitan environmental zones.
  static final List<EnvironmentalZone> defaultZones = [
    // 1. Central Jakarta (Pusat) - High urban density & emissions
    EnvironmentalZone(
      id: 'jkt_central',
      name: 'Jakarta Pusat',
      center: const LatLng(latitude: -6.1800, longitude: 106.8280),
      radiusKm: 4.8,
      polygonBounds: const [
        LatLng(latitude: -6.150, longitude: 106.800),
        LatLng(latitude: -6.150, longitude: 106.865),
        LatLng(latitude: -6.210, longitude: 106.865),
        LatLng(latitude: -6.210, longitude: 106.800),
      ],
      pm25: 68.0, // Unhealthy (Red)
      rainfallMm: 0.0,
      rainProbability: 0.15,
      isRaining: false,
    ),

    // 2. South Jakarta (Selatan) - Traffic corridor & canyon entrapment
    EnvironmentalZone(
      id: 'jkt_south',
      name: 'Jakarta Selatan',
      center: const LatLng(latitude: -6.2600, longitude: 106.8150),
      radiusKm: 6.2,
      polygonBounds: const [
        LatLng(latitude: -6.210, longitude: 106.775),
        LatLng(latitude: -6.210, longitude: 106.865),
        LatLng(latitude: -6.320, longitude: 106.865),
        LatLng(latitude: -6.320, longitude: 106.775),
      ],
      pm25: 78.0, // Unhealthy (Darker Red)
      rainfallMm: 0.0,
      rainProbability: 0.20,
      isRaining: false,
    ),

    // 3. West Jakarta (Barat) - Arterial freight & commercial hubs
    EnvironmentalZone(
      id: 'jkt_west',
      name: 'Jakarta Barat',
      center: const LatLng(latitude: -6.1650, longitude: 106.7650),
      radiusKm: 5.5,
      polygonBounds: const [
        LatLng(latitude: -6.120, longitude: 106.680),
        LatLng(latitude: -6.120, longitude: 106.800),
        LatLng(latitude: -6.215, longitude: 106.800),
        LatLng(latitude: -6.215, longitude: 106.680),
      ],
      pm25: 58.0, // Unhealthy (Red)
      rainfallMm: 0.0,
      rainProbability: 0.15,
      isRaining: false,
    ),

    // 4. East Jakarta (Timur) - Industrial & toll interchange
    EnvironmentalZone(
      id: 'jkt_east',
      name: 'Jakarta Timur',
      center: const LatLng(latitude: -6.2400, longitude: 106.8900),
      radiusKm: 6.5,
      polygonBounds: const [
        LatLng(latitude: -6.170, longitude: 106.865),
        LatLng(latitude: -6.170, longitude: 106.945),
        LatLng(latitude: -6.335, longitude: 106.945),
        LatLng(latitude: -6.335, longitude: 106.865),
      ],
      pm25: 64.0, // Unhealthy (Red)
      rainfallMm: 0.0,
      rainProbability: 0.15,
      isRaining: false,
    ),

    // 5. North Jakarta (Utara) - Coastal maritime & ports
    EnvironmentalZone(
      id: 'jkt_north',
      name: 'Jakarta Utara',
      center: const LatLng(latitude: -6.1300, longitude: 106.8600),
      radiusKm: 6.0,
      polygonBounds: const [
        LatLng(latitude: -6.080, longitude: 106.720),
        LatLng(latitude: -6.080, longitude: 106.955),
        LatLng(latitude: -6.150, longitude: 106.955),
        LatLng(latitude: -6.150, longitude: 106.720),
      ],
      pm25: 46.0, // USG (Orange)
      rainfallMm: 0.0,
      rainProbability: 0.25,
      isRaining: false,
    ),

    // 6. Depok - Suburban university & commuter zone
    EnvironmentalZone(
      id: 'depok',
      name: 'Depok',
      center: const LatLng(latitude: -6.3850, longitude: 106.8250),
      radiusKm: 5.8,
      polygonBounds: const [
        LatLng(latitude: -6.325, longitude: 106.750),
        LatLng(latitude: -6.325, longitude: 106.910),
        LatLng(latitude: -6.440, longitude: 106.910),
        LatLng(latitude: -6.440, longitude: 106.750),
      ],
      pm25: 44.0, // USG (Orange)
      rainfallMm: 0.4,
      rainProbability: 0.35,
      isRaining: false,
    ),

    // 7. Cibinong (Bogor Regency) - Active rain cell & moderate pollution
    EnvironmentalZone(
      id: 'cibinong',
      name: 'Cibinong',
      center: const LatLng(latitude: -6.4850, longitude: 106.8400),
      radiusKm: 5.2,
      polygonBounds: const [
        LatLng(latitude: -6.440, longitude: 106.780),
        LatLng(latitude: -6.440, longitude: 106.905),
        LatLng(latitude: -6.535, longitude: 106.905),
        LatLng(latitude: -6.535, longitude: 106.780),
      ],
      pm25: 38.0, // USG (Orange)
      rainfallMm: 2.8, // Active rain!
      rainProbability: 0.85,
      isRaining: true,
    ),

    // 8. Kota Bogor ("Kota Hujan") - Mountain foothill rain & clean air
    EnvironmentalZone(
      id: 'bogor_city',
      name: 'Kota Bogor',
      center: const LatLng(latitude: -6.5950, longitude: 106.7950),
      radiusKm: 5.5,
      polygonBounds: const [
        LatLng(latitude: -6.535, longitude: 106.740),
        LatLng(latitude: -6.535, longitude: 106.865),
        LatLng(latitude: -6.665, longitude: 106.865),
        LatLng(latitude: -6.665, longitude: 106.740),
      ],
      pm25: 24.0, // Moderate (Amber / Yellow)
      rainfallMm: 6.2, // Heavy Tropical Rain!
      rainProbability: 0.95,
      isRaining: true,
    ),

    // 9. Tangerang & South Tangerang (Tangsel / BSD)
    EnvironmentalZone(
      id: 'tangerang',
      name: 'Tangerang / BSD',
      center: const LatLng(latitude: -6.2950, longitude: 106.6750),
      radiusKm: 6.8,
      polygonBounds: const [
        LatLng(latitude: -6.215, longitude: 106.600),
        LatLng(latitude: -6.215, longitude: 106.755),
        LatLng(latitude: -6.365, longitude: 106.755),
        LatLng(latitude: -6.365, longitude: 106.600),
      ],
      pm25: 52.0, // USG (Orange)
      rainfallMm: 0.0,
      rainProbability: 0.20,
      isRaining: false,
    ),

    // 10. Bekasi - Manufacturing & high diesel particulate load
    EnvironmentalZone(
      id: 'bekasi',
      name: 'Bekasi',
      center: const LatLng(latitude: -6.2450, longitude: 107.0000),
      radiusKm: 7.2,
      polygonBounds: const [
        LatLng(latitude: -6.175, longitude: 106.945),
        LatLng(latitude: -6.175, longitude: 107.130),
        LatLng(latitude: -6.325, longitude: 107.130),
        LatLng(latitude: -6.325, longitude: 106.945),
      ],
      pm25: 86.0, // Unhealthy (Deep Dark Red!)
      rainfallMm: 0.0,
      rainProbability: 0.15,
      isRaining: false,
    ),
  ];

  /// Returns the canonical zones across Greater Jakarta.
  static List<EnvironmentalZone> getCanonicalZones() => List.unmodifiable(defaultZones);

  /// Static helper to find which environmental zone encompasses the coordinate.
  static EnvironmentalZone? findZoneAt(LatLng point) {
    for (final zone in defaultZones) {
      if (zone.contains(point)) return zone;
    }
    // Fall back to nearest zone center
    EnvironmentalZone? closest;
    double minDist = 999.0;
    for (final zone in defaultZones) {
      final d = zone.center.distanceTo(point);
      if (d < minDist && d <= 15.0) {
        minDist = d;
        closest = zone;
      }
    }
    return closest;
  }

  /// Alias for findZoneAt
  static EnvironmentalZone? findZone(LatLng point) => findZoneAt(point);

  /// Fetches live PM2.5 and rainfall updates for all zones from real-time APIs.
  Future<List<EnvironmentalZone>> fetchLiveZoneData() async {
    final rs = routingService ?? RoutingService();
    final updated = <EnvironmentalZone>[];

    for (final zone in defaultZones) {
      try {
        final livePm = await rs.fetchLivePm25(zone.center);
        final liveRain = await rs.fetchLiveRainfallMm(zone.center);
        updated.add(
          zone.copyWith(
            pm25: livePm > 0 ? livePm : zone.pm25,
            rainfallMm: liveRain >= 0 ? liveRain : zone.rainfallMm,
            isRaining: liveRain > 0.5,
          ),
        );
      } catch (_) {
        updated.add(zone);
      }
    }
    return updated;
  }
}
