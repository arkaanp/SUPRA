import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/widgets/current_conditions_panel.dart';

Map<String, dynamic> sample() => {
  'latitude': -6.2,
  'longitude': 106.82,
  'retrieved_at': '2026-11-05T02:00:00Z',
  'weather': {
    'status': 'unavailable',
    'source': 'open_meteo',
    'kind': null,
    'valid_at': null,
    'message': 'Weather unavailable',
    'data': null,
  },
  'air_quality': {
    'status': 'stale',
    'source': 'openaq',
    'kind': 'station_observation',
    'valid_at': '2026-11-04T18:00:00Z',
    'message': 'Nearby station, not exact-point AQI.',
    'data': {
      'pm25_ug_m3': 18.5,
      'station_name': 'Test station',
      'distance_km': 2.3,
      'provider': {'name': 'Test provider'},
      'owner': {'name': 'Test owner'},
      'licenses': [
        {'name': 'Test license'},
      ],
    },
  },
  'traffic': {
    'status': 'available',
    'source': 'tomtom',
    'kind': 'provider_live_estimate',
    'valid_at': null,
    'message': 'Traffic data © TomTom.',
    'data': {
      'speed_kmh': 20,
      'free_flow_speed_kmh': 50,
      'travel_time_seconds': 120,
      'confidence': 0.9,
      'road_closed': false,
    },
  },
};

void main() {
  test('Decodes partial results without inventing times or an AQI', () {
    final data = CurrentConditions.fromJson(sample());
    expect(data.weather.data, isNull);
    expect(data.airQuality.status, 'stale');
    expect(data.airQuality.data!['pm25_ug_m3'], 18.5);
    expect(data.traffic.validAt, isNull);
  });

  testWidgets(
    'Lookup shows independent failures, stale station attribution, and traffic',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CurrentConditionsPanel(
                load: (lat, lon, code) async {
                  calls++;
                  expect(lat, -6.2);
                  expect(lon, 106.82);
                  expect(code, isNull);
                  return CurrentConditions.fromJson(sample());
                },
              ),
            ),
          ),
        ),
      );
      expect(calls, 0, reason: 'no automatic paid-provider polling');
      await tester.ensureVisible(find.text('Load conditions'));
      await tester.tap(find.text('Load conditions'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Weather unavailable'), findsOneWidget);
      expect(find.textContaining('STALE —'), findsOneWidget);
      expect(find.text('Station: Test station'), findsOneWidget);
      expect(find.text('Provider: Test provider'), findsOneWidget);
      expect(find.textContaining('Speed: 20'), findsOneWidget);
      expect(find.textContaining('WIB'), findsWidgets);
      expect(find.text('Source / attribution'), findsNWidgets(3));
    },
  );

  testWidgets('Rejects out-of-region coordinates before calling backend', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurrentConditionsPanel(
              load: (_, _, _) async {
                calls++;
                return CurrentConditions.fromJson(sample());
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.ensureVisible(find.text('Load conditions'));
    await tester.tap(find.text('Load conditions'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      find.textContaining('Enter coordinates in Greater Jakarta'),
      findsOneWidget,
    );
  });
}
