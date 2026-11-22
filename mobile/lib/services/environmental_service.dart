import '../models/environmental_zone.dart';
import '../models/location.dart';
import 'conditions_repository.dart';
import 'geocoding_service.dart';

/// Named lookup anchors, not pollution baselines or area-wide measurements.
class EnvironmentalService {
  EnvironmentalService({
    ConditionsRepository? conditions,
    Future<String> Function(LatLng)? resolveName,
  }) : conditions = conditions ?? ConditionsRepository.instance,
       resolveName = resolveName ?? GeocodingService().reverseGeocode;
  final Future<String> Function(LatLng) resolveName;
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

  /// Sample actual provider geometry, including both ends; never draw an area heatmap.
  static List<LatLng> routeSamplePoints(List<LatLng> path) {
    if (path.length < 2) return path;
    final lengths = <double>[0];
    for (var i = 1; i < path.length; i++) {
      lengths.add(lengths.last + path[i - 1].distanceTo(path[i]));
    }
    final total = lengths.last;
    if (total == 0) return [path.first];
    final count = (total / 5).ceil().clamp(2, 5);
    final points = <LatLng>[];
    for (var i = 0; i < count; i++) {
      final target = total * i / (count - 1);
      var j = 1;
      while (j < lengths.length - 1 && lengths[j] < target) {
        j++;
      }
      final span = lengths[j] - lengths[j - 1];
      final t = span == 0 ? 0.0 : (target - lengths[j - 1]) / span;
      points.add(
        LatLng(
          latitude:
              path[j - 1].latitude +
              (path[j].latitude - path[j - 1].latitude) * t,
          longitude:
              path[j - 1].longitude +
              (path[j].longitude - path[j - 1].longitude) * t,
        ),
      );
    }
    return points;
  }

  Future<String> _placeName(LatLng point) async {
    try {
      final address = (await resolveName(point)).trim();
      if (address.isNotEmpty && !address.startsWith('Point (')) {
        return address
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(3)
            .join(', ');
      }
    } catch (_) {}
    final area = findZoneAt(point)?.name;
    final coordinates =
        '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    return area == null ? coordinates : 'Near $area ($coordinates)';
  }

  Future<List<EnvironmentalZone>> fetchRouteData(
    List<LatLng> path, {
    String? startName,
    String? destinationName,
  }) async {
    final points = routeSamplePoints(path);
    final samples = <EnvironmentalZone>[];
    // Resolve names alongside readings, using the geocoder's shared rate limit/cache.
    final names = <Future<String>>[
      for (var i = 0; i < points.length; i++)
        i == 0 && startName?.trim().isNotEmpty == true
            ? Future.value(startName!.trim())
            : i == points.length - 1 &&
                  destinationName?.trim().isNotEmpty == true
            ? Future.value(destinationName!.trim())
            : _placeName(points[i]),
    ];
    // At most two concurrent condition lookups; repository cache reuses coordinates.
    for (var i = 0; i < points.length; i += 2) {
      final batch = await Future.wait(
        points.skip(i).take(2).map((p) => fetchLiveZoneData(point: p)),
      );
      for (final zones in batch) {
        final z = zones.single;
        final index = samples.length;
        final place = await names[index];
        samples.add(
          EnvironmentalZone(
            id: 'route_$index',
            name: index == 0
                ? 'Start · $place'
                : index == points.length - 1
                ? 'Destination · $place'
                : place,
            center: z.center,
            pm25: z.pm25,
            rainfallMm: z.rainfallMm,
            conditions: z.conditions,
            weatherDescription:
                z.conditions?.weather.data?['description'] as String?,
          ),
        );
      }
    }
    return samples;
  }

  /// No background polling of ten anchors/paid providers. Refresh only the
  /// explicitly selected sample; other anchors remain unavailable.
  Future<List<EnvironmentalZone>> fetchLiveZoneData({LatLng? point}) async {
    if (point == null) return defaultZones;
    final snapshot = await conditions.at(point);
    final now = DateTime.now();
    final pm = snapshot.airQuality.number('pm25_ug_m3');
    final rain = snapshot.weather.number('precipitation_mm');
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
