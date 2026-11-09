import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/display_preferences.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DisplayPreferences.instance.resetForTesting();
  });

  testWidgets(
    'Trip planner exposes the same opt-in ML toggle and never invents values',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final conditions = ConditionsRepository(
        load: (point) async => CurrentConditions(
          latitude: point.latitude,
          longitude: point.longitude,
          retrievedAt: DateTime.now(),
          weather: ConditionsRepository.unavailable,
          traffic: ConditionsRepository.unavailable,
          airQuality: ConditionsRepository.unavailable,
        ),
      );
      final routing = RoutingService(
        useNetwork: true,
        conditions: conditions,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'distance': 3200,
                  'duration': 387,
                  'geometry': {
                    'coordinates': [
                      [106.8, -6.2],
                      [106.82, -6.21],
                    ],
                  },
                  'legs': [
                    {
                      'steps': [
                        {'name': 'Provider road'},
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TripScreen(routingService: routing),
        ),
      );
      await tester.pumpAndSettle();

      await tester.state<TripScreenState>(find.byType(TripScreen)).loadAndShowRoute(
        start: 'Start',
        destination: 'Destination',
        startPoint: const LatLng(latitude: -6.2, longitude: 106.8),
        destPoint: const LatLng(latitude: -6.21, longitude: 106.82),
      );
      await tester.pumpAndSettle();

      expect(find.text('Show ML predictions'), findsOneWidget);
      expect(DisplayPreferences.instance.showMlPredictions, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(DisplayPreferences.instance.showMlPredictions, isTrue);
      // The toggle only requests model output; the route carries no backend
      // prediction value, so the chip says unavailable rather than inventing one.
      expect(find.text('ML AQI unavailable'), findsOneWidget);
      expect(find.textContaining(RegExp(r'ML AQI \d')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
