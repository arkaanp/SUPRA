import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/environmental_zone.dart';
import '../models/location.dart';
import 'routing_service.dart';

/// Service responsible for managing area-based air pollution (PM2.5) and rainfall
/// environmental zones across Greater Jakarta (Jabodetabek) using live Open-Meteo
/// atmospheric and meteorological APIs.
class EnvironmentalService {
  final RoutingService? routingService;
  final http.Client? client;
  DateTime? lastFetchedAt;
  String? lastDataSource;

  EnvironmentalService({this.routingService, this.client});

  /// 10 canonical Greater Jakarta metropolitan environmental zones.
  /// Default baselines use 0.0 mm rainfall (no synthetic rain) and neutral PM2.5.
  static final List<EnvironmentalZone> defaultZones = [
    // 1. Central Jakarta (Pusat) - High urban density & emissions
    const EnvironmentalZone(
      id: 'jkt_central',
      name: 'Jakarta Pusat',
      center: LatLng(latitude: -6.1800, longitude: 106.8280),
      radiusKm: 4.8,
      polygonBounds: [
        LatLng(latitude: -6.150, longitude: 106.800),
        LatLng(latitude: -6.150, longitude: 106.865),
        LatLng(latitude: -6.210, longitude: 106.865),
        LatLng(latitude: -6.210, longitude: 106.800),
      ],
      pm25: 30.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 2. South Jakarta (Selatan) - Traffic corridor & canyon entrapment
    const EnvironmentalZone(
      id: 'jkt_south',
      name: 'Jakarta Selatan',
      center: LatLng(latitude: -6.2600, longitude: 106.8150),
      radiusKm: 6.2,
      polygonBounds: [
        LatLng(latitude: -6.210, longitude: 106.775),
        LatLng(latitude: -6.210, longitude: 106.865),
        LatLng(latitude: -6.320, longitude: 106.865),
        LatLng(latitude: -6.320, longitude: 106.775),
      ],
      pm25: 45.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 3. West Jakarta (Barat) - Arterial freight & commercial hubs
    const EnvironmentalZone(
      id: 'jkt_west',
      name: 'Jakarta Barat',
      center: LatLng(latitude: -6.1650, longitude: 106.7650),
      radiusKm: 5.5,
      polygonBounds: [
        LatLng(latitude: -6.120, longitude: 106.680),
        LatLng(latitude: -6.120, longitude: 106.800),
        LatLng(latitude: -6.215, longitude: 106.800),
        LatLng(latitude: -6.215, longitude: 106.680),
      ],
      pm25: 35.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 4. East Jakarta (Timur) - Industrial & toll interchange
    const EnvironmentalZone(
      id: 'jkt_east',
      name: 'Jakarta Timur',
      center: LatLng(latitude: -6.2400, longitude: 106.8900),
      radiusKm: 6.5,
      polygonBounds: [
        LatLng(latitude: -6.170, longitude: 106.865),
        LatLng(latitude: -6.170, longitude: 106.945),
        LatLng(latitude: -6.335, longitude: 106.945),
        LatLng(latitude: -6.335, longitude: 106.865),
      ],
      pm25: 42.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 5. North Jakarta (Utara) - Coastal maritime & ports
    const EnvironmentalZone(
      id: 'jkt_north',
      name: 'Jakarta Utara',
      center: LatLng(latitude: -6.1300, longitude: 106.8600),
      radiusKm: 6.0,
      polygonBounds: [
        LatLng(latitude: -6.080, longitude: 106.720),
        LatLng(latitude: -6.080, longitude: 106.955),
        LatLng(latitude: -6.150, longitude: 106.955),
        LatLng(latitude: -6.150, longitude: 106.720),
      ],
      pm25: 32.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 6. Depok - Suburban university & commuter zone
    const EnvironmentalZone(
      id: 'depok',
      name: 'Depok',
      center: LatLng(latitude: -6.3850, longitude: 106.8250),
      radiusKm: 5.8,
      polygonBounds: [
        LatLng(latitude: -6.325, longitude: 106.750),
        LatLng(latitude: -6.325, longitude: 106.910),
        LatLng(latitude: -6.440, longitude: 106.910),
        LatLng(latitude: -6.440, longitude: 106.750),
      ],
      pm25: 40.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 7. Cibinong (Bogor Regency)
    const EnvironmentalZone(
      id: 'cibinong',
      name: 'Cibinong',
      center: LatLng(latitude: -6.4850, longitude: 106.8400),
      radiusKm: 5.2,
      polygonBounds: [
        LatLng(latitude: -6.440, longitude: 106.780),
        LatLng(latitude: -6.440, longitude: 106.905),
        LatLng(latitude: -6.535, longitude: 106.905),
        LatLng(latitude: -6.535, longitude: 106.780),
      ],
      pm25: 38.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 8. Kota Bogor ("Kota Hujan")
    const EnvironmentalZone(
      id: 'bogor_city',
      name: 'Kota Bogor',
      center: LatLng(latitude: -6.5950, longitude: 106.7950),
      radiusKm: 5.5,
      polygonBounds: [
        LatLng(latitude: -6.535, longitude: 106.740),
        LatLng(latitude: -6.535, longitude: 106.865),
        LatLng(latitude: -6.665, longitude: 106.865),
        LatLng(latitude: -6.665, longitude: 106.740),
      ],
      pm25: 35.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 9. Tangerang & South Tangerang (Tangsel / BSD)
    const EnvironmentalZone(
      id: 'tangerang',
      name: 'Tangerang / BSD',
      center: LatLng(latitude: -6.2950, longitude: 106.6750),
      radiusKm: 6.8,
      polygonBounds: [
        LatLng(latitude: -6.215, longitude: 106.600),
        LatLng(latitude: -6.215, longitude: 106.755),
        LatLng(latitude: -6.365, longitude: 106.755),
        LatLng(latitude: -6.365, longitude: 106.600),
      ],
      pm25: 42.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
      isRaining: false,
    ),

    // 10. Bekasi - Manufacturing & arterial freight corridor
    const EnvironmentalZone(
      id: 'bekasi',
      name: 'Bekasi',
      center: LatLng(latitude: -6.2450, longitude: 107.0000),
      radiusKm: 7.2,
      polygonBounds: [
        LatLng(latitude: -6.175, longitude: 106.945),
        LatLng(latitude: -6.175, longitude: 107.130),
        LatLng(latitude: -6.325, longitude: 107.130),
        LatLng(latitude: -6.325, longitude: 106.945),
      ],
      pm25: 45.0,
      rainfallMm: 0.0,
      rainProbability: 0.0,
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

  /// Fetches real, current PM2.5 particulate pollution and live rainfall precipitation
  /// for all Greater Jakarta zones directly from Open-Meteo Air Quality & Weather APIs
  /// via high-performance multi-coordinate batch queries.
  Future<List<EnvironmentalZone>> fetchLiveZoneData() async {
    final httpClient = client ?? (routingService?.client ?? http.Client());
    final shouldClose = client == null && routingService?.client == null;

    final lats = defaultZones
        .map((z) => z.center.latitude.toStringAsFixed(4))
        .join(',');
    final lons = defaultZones
        .map((z) => z.center.longitude.toStringAsFixed(4))
        .join(',');

    final aqUri = Uri.parse(
      'https://air-quality-api.open-meteo.com/v1/air-quality?'
      'latitude=$lats&longitude=$lons&current=pm2_5',
    );
    final wxUri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?'
      'latitude=$lats&longitude=$lons&current=precipitation,rain',
    );

    try {
      final results = await Future.wait([
        httpClient.get(aqUri).timeout(const Duration(seconds: 5)),
        httpClient.get(wxUri).timeout(const Duration(seconds: 5)),
      ]);

      final aqRes = results[0];
      final wxRes = results[1];

      List<dynamic> aqList = [];
      List<dynamic> wxList = [];

      if (aqRes.statusCode == 200) {
        final decoded = jsonDecode(aqRes.body);
        if (decoded is List) {
          aqList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          aqList = [decoded];
        }
      }

      if (wxRes.statusCode == 200) {
        final decoded = jsonDecode(wxRes.body);
        if (decoded is List) {
          wxList = decoded;
        } else if (decoded is Map<String, dynamic>) {
          wxList = [decoded];
        }
      }

      final updated = <EnvironmentalZone>[];
      for (int i = 0; i < defaultZones.length; i++) {
        final zone = defaultZones[i];
        double realPm = zone.pm25;
        double realRain = zone.rainfallMm;

        if (i < aqList.length && aqList[i] is Map<String, dynamic>) {
          final cur = aqList[i]['current'] as Map<String, dynamic>?;
          final pm = (cur?['pm2_5'] as num?)?.toDouble();
          if (pm != null && pm >= 0) {
            realPm = pm;
          }
        }

        if (i < wxList.length && wxList[i] is Map<String, dynamic>) {
          final cur = wxList[i]['current'] as Map<String, dynamic>?;
          final rain = (cur?['precipitation'] as num?)?.toDouble() ??
              (cur?['rain'] as num?)?.toDouble();
          if (rain != null && rain >= 0) {
            realRain = rain;
          }
        }

        updated.add(
          zone.copyWith(
            pm25: realPm,
            rainfallMm: realRain,
            isRaining: realRain > 0.5,
          ),
        );
      }

      lastFetchedAt = DateTime.now();
      lastDataSource = 'Open-Meteo Air Quality & Weather API';
      return updated;
    } catch (_) {
      // Fallback: if network fails or in offline tests, return default zones
      return defaultZones;
    } finally {
      if (shouldClose) httpClient.close();
    }
  }
}
