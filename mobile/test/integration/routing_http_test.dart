import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const start = LatLng(latitude: -6.2, longitude: 106.8);
  const end = LatLng(latitude: -6.21, longitude: 106.82);
  CurrentConditions snapshot({bool stale = false}) => CurrentConditions(
    latitude: start.latitude,
    longitude: start.longitude,
    retrievedAt: DateTime.now(),
    weather: ConditionsRepository.unavailable,
    traffic: ConditionsRepository.unavailable,
    airQuality: ConditionSignal(
      status: stale ? 'stale' : 'available',
      source: 'openaq',
      message: 'Nearby station observation, not AQI',
      kind: 'station_observation',
      validAt: DateTime.now(),
      data: const {'pm25_ug_m3': 0},
    ),
  );

  group('Real HTTP routing adapter', () {
    late HttpServer server;
    late IOClient client;
    late String baseUrl;
    var status = 200;
    var body = '';
    var calls = 0;
    setUp(() async {
      status = 200;
      client = IOClient(_RealHttp().createHttpClient(null));
      calls = 0;
      body = jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'distance': 3200,
            'duration': 387,
            'geometry': {
              'coordinates': [
                [106.8, -6.2],
                [106.81, -6.205],
                [106.82, -6.21],
              ],
            },
            'legs': [
              {
                'steps': [
                  {'name': 'Provider street'},
                ],
              },
            ],
          },
        ],
      });
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        calls++;
        expect(request.uri.path, startsWith('/route/v1/driving/'));
        request.response.statusCode = status;
        request.response.write(body);
        await request.response.close();
      });
    });
    tearDown(() async {
      client.close();
      await server.close(force: true);
    });
    test('Uses provider geometry, distance and duration without shortcuts or guessed modes', () async {
      final service = RoutingService(
        client: client,
        useNetwork: true,
        osrmBaseUrl: baseUrl,
        conditions: ConditionsRepository(load: (_) async => snapshot()),
      );
      final route = (await service.calculateRoutes(
        start: start,
        destination: end,
      )).single;
      expect(calls, 1);
      expect(route.mode, TransportMode.car);
      expect(route.distanceKm, 3.2);
      expect(route.estimatedDuration, const Duration(seconds: 387));
      expect(route.waypoints.length, 3);
      expect(route.turnSteps, ['Provider street']);
      expect(route.pm25UgM3, 0); // Zero is a valid reading, not missing.
      expect(route.predictedAqi, isNull);
      expect(route.rainProbability, isNull);
      expect(route.rainfallMm, isNull);
      expect(route.trafficDensity, isNull);
      expect(route.trafficCategory, contains('unavailable'));
      expect(route.provenanceLabel, contains('openaq'));
      expect(route.recommendationReason, contains('not a live-traffic ETA'));
    });
    test(
      'Stale station data is preserved as evidence but not treated as current',
      () async {
        final route = (await RoutingService(
          client: client,
          useNetwork: true,
          osrmBaseUrl: baseUrl,
          conditions: ConditionsRepository(
            load: (_) async => snapshot(stale: true),
          ),
        ).calculateRoutes(start: start, destination: end)).single;
        expect(route.pm25UgM3, 0);
        expect(route.pm25Label, startsWith('STALE'));
        expect(route.provenanceLabel, contains('stale'));
      },
    );
    test(
      'HTTP 500, no route and malformed responses never produce fake geometry',
      () async {
        final service = RoutingService(
          client: client,
          useNetwork: true,
          osrmBaseUrl: baseUrl,
          conditions: ConditionsRepository(load: (_) async => snapshot()),
        );
        status = 500;
        await expectLater(
          service.calculateRoutes(start: start, destination: end),
          throwsStateError,
        );
        status = 200;
        body = '{"code":"NoRoute","routes":[]}';
        await expectLater(
          service.calculateRoutes(start: start, destination: end),
          throwsStateError,
        );
        body = '<html>proxy error</html>';
        await expectLater(
          service.calculateRoutes(start: start, destination: end),
          throwsFormatException,
        );
      },
    );
  });
}
