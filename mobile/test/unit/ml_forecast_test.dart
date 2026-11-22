import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/ml_forecast.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/forecast_repository.dart';

Map<String, dynamic> forecastPayload(
  DateTime now, {
  double lat = -6.2297,
  double lon = 106.8295,
}) => {
  'latitude': lat,
  'longitude': lon,
  'framework': 'PyTorch',
  'model_id': 'test-trained-model',
  'generated_at': now.toIso8601String(),
  'input_through': now.subtract(const Duration(minutes: 10)).toIso8601String(),
  'expires_at': now.add(const Duration(hours: 1)).toIso8601String(),
  'sources': {'attribution': 'Open-Meteo / CAMS'},
  'validation': {
    'mae': {'aqi': 5.2},
  },
  'hourly': [
    for (var i = 1; i <= 12; i++)
      {
        'target_time': now.add(Duration(hours: i)).toIso8601String(),
        'temperature_c': 31.25,
        'precipitation_mm': 0.75,
        'pm25_ug_m3': 40.5,
        'aqi': 123.0,
        'rain_probability': 0.37,
        'traffic_density': null,
        'traffic_speed_kmh': null,
      },
  ],
};
ConditionsRepository availableConditions() => ConditionsRepository(
  load: (p) async => CurrentConditions(
    latitude: p.latitude,
    longitude: p.longitude,
    retrievedAt: DateTime.now(),
    weather: const ConditionSignal(
      status: 'available',
      source: 'bmkg',
      kind: 'provider_forecast',
      message: '',
      data: {'precipitation_mm': 0.0, 'temperature_c': 29},
    ),
    traffic: const ConditionSignal(
      status: 'available',
      source: 'tomtom',
      kind: 'provider_live_estimate',
      message: '',
      data: {'speed_kmh': 25, 'free_flow_speed_kmh': 45},
    ),
    airQuality: ConditionsRepository.unavailable,
  ),
);

void main() {
  test('Provider forecast parses, expires, and rejects invalid probability and traffic', () {
    final now = DateTime.now();
    final data = forecastPayload(now);
    final f = MlForecast.fromJson(data);
    expect(f.nextAt(now)!.aqi, 123);
    expect(f.nextAt(now.add(const Duration(hours: 2))), isNull);
    (data['hourly'] as List)[0]['rain_probability'] = 37;
    expect(() => MlForecast.fromJson(data), throwsFormatException);
    (data['hourly'] as List)[0]['rain_probability'] = 0.37;
    (data['hourly'] as List)[0]['traffic_density'] = 0.5;
    expect(() => MlForecast.fromJson(data), throwsFormatException);
  });
  test(
    'Repository coalesces, caches, rejects wrong locations and stale responses',
    () async {
      var now = DateTime.now();
      var calls = 0;
      const p = LatLng(latitude: -6.2297, longitude: 106.8295);
      final repository = ForecastRepository(
        now: () => now,
        load: (_) async {
          calls++;
          return forecastPayload(now);
        },
      );
      await Future.wait([repository.at(p), repository.at(p)]);
      await repository.at(p);
      expect(calls, 1);
      now = now.add(const Duration(minutes: 11));
      await repository.at(p);
      expect(calls, 2);
      final wrong = ForecastRepository(
        load: (_) async => forecastPayload(now, lat: -6.4),
      );
      await expectLater(wrong.at(p), throwsFormatException);
      final stale = ForecastRepository(
        load: (_) async =>
            forecastPayload(DateTime.now().subtract(const Duration(hours: 4))),
      );
      await expectLater(stale.at(p), throwsFormatException);
    },
  );
  test('Weather-only forecasts preserve unknown air values', () {
    final data = forecastPayload(DateTime.now());
    for (final row in data['hourly'] as List) {
      row['aqi'] = null;
      row['pm25_ug_m3'] = null;
    }
    data['scope'] = 'weather_only';
    final forecast = MlForecast.fromJson(data);
    expect(forecast.hourly.first.aqi, isNull);
    expect(forecast.hourly.first.precipitationMm, 0.75);
  });
  testWidgets('Trip keeps provider rain and traffic when the forecast fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripScreen(
            routingService: RoutingService(conditions: availableConditions()),
            forecasts: ForecastRepository(
              load: (_) async => throw StateError('offline'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prediksi ML').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'ML forecast unavailable. Try refreshing. · Rain · BMKG forecast 0.0 mm · Traffic 25 km/h',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'Home toggle renders actual returned values and model provenance',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ForecastRepository(
        load: (_) async => forecastPayload(DateTime.now()),
      );
      final conditions = availableConditions();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(conditions: conditions, forecasts: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('123'), findsOneWidget);
      expect(find.text('0.8 mm (37%)'), findsOneWidget);
      expect(find.text('25 km/h'), findsOneWidget);
      expect(find.textContaining('test-trained-model'), findsOneWidget);
      expect(find.textContaining('65%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Unavailable ML preserves provider rain and traffic and reports failure',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            conditions: availableConditions(),
            forecasts: ForecastRepository(
              load: (_) async => throw StateError('offline'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('ML forecast unavailable'), findsWidgets);
      expect(find.text('0.0 mm'), findsOneWidget);
      expect(find.text('25 km/h'), findsOneWidget);
      expect(find.text('BMKG forecast'), findsWidgets);
      expect(find.textContaining('65%'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
