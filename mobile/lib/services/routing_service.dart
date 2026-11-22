import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/map_config.dart';
import '../models/location.dart';
import '../models/route_option.dart';
import '../models/transit_journey.dart';
import 'conditions_repository.dart';
import 'supra_api_service.dart';

/// Driving geometry and provider duration only. Never invents a route on failure.
/// Motorcycle/transit require their own verified routing providers.
class RoutingService {
  RoutingService({
    this.client,
    this.planMobility,
    bool? useNetwork,
    ConditionsRepository? conditions,
    this.osrmBaseUrl = const String.fromEnvironment(
      'OSRM_BASE_URL',
      defaultValue: 'https://router.project-osrm.org',
    ),
  }) : useNetwork =
           useNetwork ?? (client != null || !MapConfig.isTestEnvironment),
       conditions = conditions ?? ConditionsRepository.instance;
  final http.Client? client;
  final Future<Map<String, dynamic>> Function(LatLng, LatLng, String)?
  planMobility;
  final bool useNetwork;
  final String osrmBaseUrl;
  final ConditionsRepository conditions;

  Future<double?> fetchLivePm25(LatLng point) async {
    final data = await conditions.at(point);
    return data.airQuality.isCurrentAt(DateTime.now())
        ? data.airQuality.number('pm25_ug_m3')
        : null;
  }

  Future<double?> fetchLiveRainfallMm(LatLng point) async {
    final data = await conditions.at(point);
    return data.weather.isCurrentAt(DateTime.now())
        ? data.weather.number('precipitation_mm')
        : null;
  }

  Future<List<RouteOption>> calculateMode({
    required LatLng start,
    required LatLng destination,
    required TransportMode mode,
  }) async {
    if (mode == TransportMode.car) {
      return calculateRoutes(start: start, destination: destination);
    }
    if (!useNetwork) {
      throw StateError('Rute tidak tersedia tanpa koneksi internet.');
    }
    final result = await (planMobility ?? SupraService.instance.planMobility)(
      start,
      destination,
      mode.apiValue,
    );
    final snapshot = await conditions.at(start);
    final trafficDensity = _computeTrafficDensity(snapshot);
    final candidates = <Map<String, dynamic>>[
      result,
      for (final alternative in result['alternatives'] as List? ?? const [])
        alternative as Map<String, dynamic>,
    ];
    final options = <RouteOption>[];
    for (final result in candidates) {
      if (result['mode'] != mode.apiValue) {
        throw const FormatException('Wrong routing mode');
      }
      final points = (result['waypoints'] as List)
          .map(
            (v) => LatLng(
              latitude: (v[0] as num).toDouble(),
              longitude: (v[1] as num).toDouble(),
            ),
          )
          .toList();
      final seconds = (result['duration_seconds'] as num).toDouble(),
          distance = (result['distance_km'] as num).toDouble();
      if (points.length < 2 ||
          points.any((p) => !p.latitude.isFinite || !p.longitude.isFinite) ||
          !seconds.isFinite ||
          seconds <= 0 ||
          !distance.isFinite ||
          distance <= 0 ||
          points.first.distanceTo(start) > 2 ||
          points.last.distanceTo(destination) > 2) {
        throw const FormatException('Invalid provider route');
      }
      final journey = result['transit'] is Map<String, dynamic>
          ? TransitJourney.fromJson(result['transit'] as Map<String, dynamic>)
          : null;
      options.add(
        RouteOption(
          mode: mode,
          transitJourney: journey,
          title: journey?.displayName ?? mode.displayName,
          estimatedDuration: Duration(seconds: seconds.ceil()),
          distanceKm: distance,
          waypoints: points,
          turnSteps: (result['steps'] as List).cast<String>(),
          conditions: snapshot,
          pm25UgM3: snapshot.airQuality.number('pm25_ug_m3'),
          rainfallMm: snapshot.weather.kind == 'provider_forecast'
              ? null
              : snapshot.weather.number('precipitation_mm'),
          trafficDensity: trafficDensity,
          routingSource:
              '${result['source']} · fetched ${result['fetched_at']}',
          recommendationReason: mode == TransportMode.publicTransit
              ? 'Perkiraan berdasarkan jadwal atau frekuensi layanan. Waktu kedatangan dapat berubah. Penghubung pejalan kaki dan stasiun dapat bersifat skematis.'
              : 'Rute dan durasi sesuai moda dari penyedia, tanpa kondisi lalu lintas terkini.',
          identifiedRisks: const [],
          protectiveMeasures: const [],
        ),
      );
    }
    return options;
  }

  Future<List<RouteOption>> calculateRoutes({
    required LatLng start,
    required LatLng destination,
    String? startName,
    String? destinationName,
  }) async {
    if (!start.isInGreaterJakarta || !destination.isInGreaterJakarta) {
      throw StateError('Lokasi awal dan tujuan harus berada di Jabodetabek.');
    }
    if (!useNetwork) {
      throw StateError('Rute tidak tersedia tanpa koneksi internet.');
    }
    final snapshotFuture = conditions.at(start);
    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse(
        '${osrmBaseUrl.replaceAll(RegExp(r"/+$"), "")}/route/v1/driving/'
        '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );
      final response = await httpClient
          .get(url)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw StateError('Penyedia rute tidak tersedia.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (data['code'] != 'Ok' || routes == null || routes.isEmpty) {
        throw StateError('Rute berkendara tidak ditemukan.');
      }
      final route = routes.first as Map<String, dynamic>;
      final distance = (route['distance'] as num).toDouble();
      final seconds = (route['duration'] as num).toDouble();
      if (!distance.isFinite ||
          distance <= 0 ||
          !seconds.isFinite ||
          seconds <= 0) {
        throw const FormatException('Invalid route metrics');
      }
      final points = ((route['geometry'] as Map)['coordinates'] as List).map((
        entry,
      ) {
        final pair = entry as List;
        final lon = (pair[0] as num).toDouble();
        final lat = (pair[1] as num).toDouble();
        if (!lat.isFinite ||
            lat.abs() > 90 ||
            !lon.isFinite ||
            lon.abs() > 180) {
          throw const FormatException('Invalid route coordinate');
        }
        return LatLng(latitude: lat, longitude: lon);
      }).toList();
      if (points.length < 2 ||
          points.first.distanceTo(start) > 2 ||
          points.last.distanceTo(destination) > 2) {
        throw const FormatException('Invalid route geometry');
      }
      final steps = <String>[];
      for (final leg in route['legs'] as List? ?? []) {
        for (final step in (leg as Map)['steps'] as List? ?? []) {
          final name = (step as Map)['name'];
          if (name is String &&
              name.trim().isNotEmpty &&
              !steps.contains(name)) {
            steps.add(name);
          }
        }
      }
      final snapshot = await snapshotFuture;
      final pm = snapshot.airQuality.number('pm25_ug_m3');
      final rain = snapshot.weather.kind == 'provider_forecast'
          ? null
          : snapshot.weather.number('precipitation_mm');
      final trafficDensity = _computeTrafficDensity(snapshot);
      return [
        RouteOption(
          mode: TransportMode.car,
          title: 'Mobil / Taksi',
          estimatedDuration: Duration(seconds: seconds.ceil()),
          distanceKm: distance / 1000,
          waypoints: points,
          turnSteps: steps,
          conditions: snapshot,
          routingSource: 'OSRM',
          recommendationReason:
              'Perkiraan waktu berkendara tanpa lalu lintas terkini. '
              'Data lingkungan mewakili titik awal, bukan seluruh rute. '
              'Pilih moda lain untuk membandingkan perkiraan rute.',
          identifiedRisks: [
            if (pm == null)
              'PM2.5 terkini tidak tersedia; paparan belum dapat dinilai.',
            if (rain == null) 'Curah hujan terkini tidak tersedia; kondisi kering belum dapat dipastikan.',
            if (snapshot.airQuality.isStale || snapshot.weather.isStale) 'Data lama ditampilkan sebagai referensi, bukan penilaian keselamatan terkini.',
          ],
          protectiveMeasures: const [],
          pm25UgM3: pm,
          rainfallMm: rain,
          trafficDensity: trafficDensity,
        ),
      ];
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static double? _computeTrafficDensity(dynamic snapshot) {
    final traffic = snapshot.traffic;
    if (traffic == null || !traffic.hasData) return null;
    final speed = traffic.number('speed_kmh');
    if (speed == null) return null;
    final freeFlow = traffic.number('free_flow_speed_kmh') ?? 48.0;
    if (freeFlow <= 0) return null;
    return (1.0 - (speed / freeFlow)).clamp(0.05, 0.95);
  }
}
