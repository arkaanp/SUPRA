import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/environmental_zone.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/widgets/route_environment_samples.dart';

EnvironmentalZone sample(int i, {double? aqi, double? rain = 1.2}) =>
    EnvironmentalZone(
      id: '$i',
      name: i == 4 ? 'Destination' : 'Sample $i',
      center: const LatLng(latitude: -6.2, longitude: 106.8),
      rainfallMm: rain,
      conditions: CurrentConditions(
        latitude: -6.2,
        longitude: 106.8,
        retrievedAt: DateTime.now(),
        weather: ConditionSignal(
          status: 'available',
          source: 'open_meteo',
          message: 'Weather model',
          data: {'temperature_c': 30, 'precipitation_mm': rain},
        ),
        airQuality: ConditionSignal(
          status: 'available',
          source: 'open_meteo_cams',
          message: 'Air model',
          data: {'aqi': aqi},
        ),
        traffic: const ConditionSignal(
          status: 'unavailable',
          source: 'tomtom',
          message: 'Unavailable',
        ),
      ),
    );

void main() {
  test(
    'AQI colors use the existing categories and missing values remain neutral',
    () {
      expect(sample(0, aqi: 40).solidAqiColor, const Color(0xFF22C55E));
      expect(sample(0, aqi: 80).solidAqiColor, const Color(0xFFEAB308));
      expect(sample(0, aqi: 120).colorBandLabel, 'Unhealthy for Sensitive');
      expect(sample(0, aqi: 180).solidAqiColor, const Color(0xFFEF4444));
      expect(sample(0).solidAqiColor, Colors.grey);
      expect(sample(0).colorBandLabel, 'Unavailable');
    },
  );

  testWidgets(
    'Detailed cards scroll below transport options without map-sized labels',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: ListView(
                children: [
                  const SizedBox(height: 120, child: Text('Car')),
                  const SizedBox(height: 120, child: Text('Motorcycle')),
                  RouteEnvironmentSamples(
                    samples: [for (var i = 0; i < 5; i++) sample(i, aqi: 120)],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sample-card-4')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Compact marker distinguishes rain, zero and missing precipitation',
    (tester) async {
      for (final rain in [1.2, 0.0, null]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 54,
                height: 54,
                child: EnvironmentalSampleMarker(
                  sample: sample(0, aqi: 120, rain: rain),
                ),
              ),
            ),
          ),
        );
        expect(
          find.text(rain == null ? '—' : '${rain.toStringAsFixed(1)} mm'),
          findsOneWidget,
        );
        expect(find.text('Sample 0'), findsNothing);
        expect(
          find.byIcon(
            rain == null
                ? Icons.cloud_off_outlined
                : rain > 0
                ? Icons.water_drop
                : Icons.cloud_outlined,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
