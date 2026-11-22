import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/geocoding_service.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';
import 'package:supra_mobile_ui/widgets/route_planner_view.dart';

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

  test(
    'Offline routing fails explicitly and environmental failures stay unknown',
    () async {
      final service = RoutingService(
        useNetwork: false,
        conditions: ConditionsRepository(
          load: (_) async => throw StateError('offline'),
        ),
      );
      await expectLater(
        service.calculateRoutes(start: start, destination: end),
        throwsStateError,
      );
      expect(await service.fetchLivePm25(start), isNull);
      expect(await service.fetchLiveRainfallMm(start), isNull);
    },
  );
  test(
    'Conditions cache deduplicates and expires; forecasts are not observations',
    () async {
      var now = DateTime.now();
      var calls = 0;
      final repo = ConditionsRepository(
        now: () => now,
        load: (_) async {
          calls++;
          return snapshot();
        },
      );
      await Future.wait([repo.at(start), repo.at(start)]);
      expect(calls, 1);
      await repo.at(start);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 3));
      await repo.at(start);
      expect(calls, 2);
      final forecast = ConditionSignal(
        status: 'available',
        source: 'bmkg',
        message: 'Prakiraan',
        kind: 'provider_forecast',
        validAt: now,
        data: const {'precipitation_mm': 0},
      );
      expect(forecast.isCurrentAt(now), false);
    },
  );
  test('Search never fabricates places; offline reverse lookup retains exact coordinates', () async {
    final service = GeocodingService(useNetwork: false);
    expect(await service.searchPlaces('nonexistent-xyz-123'), isEmpty);
    expect(await service.searchPlaces('Sudirman'), isNotEmpty);
    expect(await service.reverseGeocode(start), 'Titik (-6.20000, 106.80000)');
    expect(
      () => GeocodedPlace.fromJson({
        'name': 'Broken',
        'lat': 'bad',
        'lon': 106.8,
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'Unknown environmental values are not shown as clear weather or free flow',
    (tester) async {
      const route = RouteOption(
        mode: TransportMode.car,
        title: 'Mobil',
        estimatedDuration: Duration(minutes: 10),
        distanceKm: 3,
        waypoints: [],
        recommendationReason: 'Provider estimate',
        identifiedRisks: [],
        protectiveMeasures: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoutePlannerView(
                options: const [route],
                selectedOption: route,
                onOptionSelected: (_) {},
                onConfirmRoute: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('PM2.5 tidak tersedia'), findsOneWidget);
      expect(find.text('Curah hujan tidak tersedia'), findsOneWidget);
      expect(find.text('Lalu lintas rute tidak tersedia'), findsOneWidget);
      expect(find.text('Weather: Clear'), findsNothing);
    },
  );
}
