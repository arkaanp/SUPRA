import '../models/environmental_zone.dart';
import '../models/location.dart';
import 'conditions_repository.dart';

/// Named lookup anchors, not pollution baselines or area-wide measurements.
class EnvironmentalService {
  EnvironmentalService({ConditionsRepository? conditions})
    : conditions = conditions ?? ConditionsRepository.instance;
  final ConditionsRepository conditions;
  DateTime? lastFetchedAt;
  String? lastDataSource;

  static const defaultZones = [
    EnvironmentalZone(
      id: 'jkt_central',
      name: 'Jakarta Pusat',
      center: LatLng(latitude: -6.18, longitude: 106.83),
    ),
    EnvironmentalZone(
      id: 'jkt_south',
      name: 'Jakarta Selatan',
      center: LatLng(latitude: -6.26, longitude: 106.81),
    ),
    EnvironmentalZone(
      id: 'jkt_west',
      name: 'Jakarta Barat',
      center: LatLng(latitude: -6.17, longitude: 106.75),
    ),
    EnvironmentalZone(
      id: 'jkt_east',
      name: 'Jakarta Timur',
      center: LatLng(latitude: -6.23, longitude: 106.90),
    ),
    EnvironmentalZone(
      id: 'jkt_north',
      name: 'Jakarta Utara',
      center: LatLng(latitude: -6.12, longitude: 106.88),
    ),
    EnvironmentalZone(
      id: 'tangerang',
      name: 'Tangerang',
      center: LatLng(latitude: -6.18, longitude: 106.63),
    ),
    EnvironmentalZone(
      id: 'bekasi',
      name: 'Bekasi',
      center: LatLng(latitude: -6.24, longitude: 107.00),
    ),
    EnvironmentalZone(
      id: 'depok',
      name: 'Depok',
      center: LatLng(latitude: -6.40, longitude: 106.82),
    ),
    EnvironmentalZone(
      id: 'cibinong',
      name: 'Cibinong',
      center: LatLng(latitude: -6.48, longitude: 106.85),
    ),
    EnvironmentalZone(
      id: 'bogor',
      name: 'Kota Bogor',
      center: LatLng(latitude: -6.60, longitude: 106.80),
    ),
  ];
  static List<EnvironmentalZone> getCanonicalZones() => defaultZones;
  static EnvironmentalZone? findZoneAt(LatLng point) {
    EnvironmentalZone? nearest;
    var distance = 15.0;
    for (final zone in defaultZones) {
      final candidate = zone.center.distanceTo(point);
      if (candidate < distance) {
        distance = candidate;
        nearest = zone;
      }
    }
    return nearest;
  }

  static EnvironmentalZone? findZone(LatLng point) => findZoneAt(point);

  /// No background polling of ten anchors/paid providers. Refresh only the
  /// explicitly selected sample; other anchors remain unavailable.
  Future<List<EnvironmentalZone>> fetchLiveZoneData({LatLng? point}) async {
    if (point == null) return defaultZones;
    final snapshot = await conditions.at(point);
    final now = DateTime.now();
    final pm = snapshot.airQuality.number('pm25_ug_m3');
    final rain = snapshot.weather.kind == 'provider_forecast'
        ? null
        : snapshot.weather.number('precipitation_mm');
    lastFetchedAt = snapshot.retrievedAt;
    lastDataSource =
        '${snapshot.airQuality.source}: ${snapshot.airQuality.status}; '
        '${snapshot.weather.source}: ${snapshot.weather.status}';
    return [
      EnvironmentalZone(
        id: 'selected',
        name: 'Selected location sample',
        center: point,
        pm25: pm,
        rainfallMm: rain,
        isRaining: rain != null && rain > 0,
        conditions: snapshot,
        windSpeedKmh: snapshot.weather.isCurrentAt(now)
            ? snapshot.weather.number('wind_speed_kmh')
            : null,
      ),
    ];
  }
}
