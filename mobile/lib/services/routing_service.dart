import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/map_config.dart';
import '../models/location.dart';
import '../models/route_option.dart';
import 'conditions_repository.dart';
import 'supra_api_service.dart';

/// Driving geometry and provider duration only. Never invents a route on failure.
/// Motorcycle/transit require their own verified routing providers.
class RoutingService {
  RoutingService({
    this.client,
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
    if (!useNetwork) throw StateError('Routing unavailable offline.');
    final result = await SupraService.instance.planMobility(
      start,
      destination,
      mode.apiValue,
    );
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
    final snapshot = await conditions.at(start);
    return [
      RouteOption(
        mode: mode,
        title: mode.displayName,
        estimatedDuration: Duration(seconds: seconds.ceil()),
        distanceKm: distance,
        waypoints: points,
        turnSteps: (result['steps'] as List).cast<String>(),
        conditions: snapshot,
        pm25UgM3: snapshot.airQuality.number('pm25_ug_m3'),
        rainfallMm: snapshot.weather.kind == 'provider_forecast'
            ? null
            : snapshot.weather.number('precipitation_mm'),
        recommendationReason:
            '${result['source']} · fetched ${result['fetched_at']}. '
            '${mode == TransportMode.publicTransit ? 'GTFS itinerary; not a live arrival guarantee.' : 'Mode-specific geometry and provider duration; not a live-traffic ETA.'}',
        identifiedRisks: const [],
        protectiveMeasures: const [],
      ),
    ];
  }

  Future<List<RouteOption>> calculateRoutes({
    required LatLng start,
    required LatLng destination,
    String? startName,
    String? destinationName,
  }) async {
    if (!start.isInGreaterJakarta || !destination.isInGreaterJakarta) {
      throw StateError('Route endpoints must be in Greater Jakarta.');
    }
    if (!useNetwork) throw StateError('Routing unavailable offline.');
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
        throw StateError('Routing provider unavailable.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (data['code'] != 'Ok' || routes == null || routes.isEmpty) {
        throw StateError('No driving route found.');
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
      return [
        RouteOption(
          mode: TransportMode.car,
          title: 'Car / Taxi',
          estimatedDuration: Duration(seconds: seconds.ceil()),
          distanceKm: distance / 1000,
          waypoints: points,
          turnSteps: steps,
          conditions: snapshot,
          recommendationReason:
              'OSRM driving estimate — not a live-traffic ETA. '
              'Environmental data samples the origin, not the whole route. '
              'Motorcycle/transit routing is not configured.',
          identifiedRisks: [
            if (pm == null)
              'Current PM2.5 unavailable; exposure cannot be assessed.',
            if (rain == null)
              'Current rainfall unavailable; dry weather cannot be assumed.',
            if (snapshot.airQuality.isStale || snapshot.weather.isStale) 'Stale environmental data is shown for reference, not a current safety assessment.',
          ],
          protectiveMeasures: const [],
          pm25UgM3: pm,
          rainfallMm: rain,
        ),
      ];
    } finally {
      if (client == null) httpClient.close();
    }
  }
}
