import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';
import 'package:supra_mobile_ui/widgets/route_planner_view.dart';

void main() {
  group('RouteOption model & formatting tests', () {
    test('TransportMode properties match expectations', () {
      expect(TransportMode.motorcycle.displayName, 'Motorcycle');
      expect(TransportMode.motorcycle.iconEmoji, '🏍️');

      expect(TransportMode.car.displayName, 'Car / Taxi');
      expect(TransportMode.car.iconEmoji, '🚗');

      expect(TransportMode.publicTransit.displayName, 'Public Transit');
      expect(TransportMode.publicTransit.iconEmoji, '🚆');
    });

    test('Formatted duration handles minutes and hours properly', () {
      final opt1 = RouteOption(
        mode: TransportMode.motorcycle,
        title: 'Motorcycle',
        estimatedDuration: const Duration(minutes: 24),
        distanceKm: 12.0,
        waypoints: const [],
        turnSteps: const [],
        isRecommended: true,
        recommendationReason: 'Fastest route',
        identifiedRisks: const [],
        protectiveMeasures: const [],
        predictedAqi: 50.0,
        pm25UgM3: 20.0,
        rainfallMm: 0.0,
        rainProbability: 0.1,
        trafficDensity: 0.3,
      );
      expect(opt1.formattedDuration, '24 min');

      final opt2 = RouteOption(
        mode: TransportMode.car,
        title: 'Car',
        estimatedDuration: const Duration(minutes: 85),
        distanceKm: 30.0,
        waypoints: const [],
        turnSteps: const [],
        isRecommended: false,
        recommendationReason: 'Heavy traffic',
        identifiedRisks: const [],
        protectiveMeasures: const [],
        predictedAqi: 120.0,
        pm25UgM3: 65.0,
        rainfallMm: 5.0,
        rainProbability: 0.8,
        trafficDensity: 0.9,
      );
      expect(opt2.formattedDuration, '1 hr 25 min');
      expect(opt2.aqiCategory, 'Unhealthy');
      expect(opt2.trafficCategory, 'Heavy Gridlock');
    });
  });

  group('RoutingService multi-modal & health recommendation logic tests', () {
    final start = const LatLng(
      latitude: -6.2600,
      longitude: 106.8150,
    ); // Kemang
    final destination = const LatLng(
      latitude: -6.2250,
      longitude: 106.8080,
    ); // Sudirman

    test('Returns 3 multi-modal options (Motorcycle, Car, Transit)', () async {
      final service = RoutingService(useNetwork: false);
      final options = await service.calculateRoutes(
        start: start,
        destination: destination,
        pm25UgM3: 25.0,
        rainfallMm: 0.0,
        trafficDensity: 0.3,
      );

      expect(options.length, 3);
      final modes = options.map((o) => o.mode).toList();
      expect(modes, contains(TransportMode.motorcycle));
      expect(modes, contains(TransportMode.car));
      expect(modes, contains(TransportMode.publicTransit));
    });

    test(
      'High PM2.5 triggers motorcycle N95 mask advice & car AC recirculation',
      () async {
        final service = RoutingService(useNetwork: false);
        final options = await service.calculateRoutes(
          start: start,
          destination: destination,
          pm25UgM3: 75.0, // High air pollution
          rainfallMm: 0.0,
          trafficDensity: 0.5,
        );

        final motor = options.firstWhere(
          (o) => o.mode == TransportMode.motorcycle,
        );
        expect(
          motor.identifiedRisks.any(
            (r) => r.contains('High PM2.5 Inhalation Risk'),
          ),
          isTrue,
        );
        expect(
          motor.protectiveMeasures.any((m) => m.contains('N95 or KN95')),
          isTrue,
        );

        final car = options.firstWhere((o) => o.mode == TransportMode.car);
        expect(
          car.protectiveMeasures.any(
            (m) => m.contains('AC air recirculation ON'),
          ),
          isTrue,
        );
      },
    );

    test('Heavy rain and elevated PM2.5 favors public transit over open-air motorcycle', () async {
      final service = RoutingService(useNetwork: false);
      final options = await service.calculateRoutes(
        start: start,
        destination: destination,
        pm25UgM3: 50.0,
        rainfallMm: 8.5, // Rainstorm
        rainProbability: 0.85,
        trafficDensity: 0.6,
      );

      final recommended = options.firstWhere((o) => o.isRecommended);
      expect(recommended.mode, TransportMode.publicTransit);
      expect(
        recommended.recommendationReason,
        contains('shields from heavy PM2.5'),
      );

      final motor = options.firstWhere(
        (o) => o.mode == TransportMode.motorcycle,
      );
      expect(
        motor.identifiedRisks.any((r) => r.contains('Tropical Rain Hazard')),
        isTrue,
      );
      expect(
        motor.protectiveMeasures.any((m) => m.contains('rain gear')),
        isTrue,
      );
    });

    test('High traffic with moderate pollution recommends motorcycle speed filtering', () async {
      final service = RoutingService(useNetwork: false);
      final options = await service.calculateRoutes(
        start: start,
        destination: destination,
        pm25UgM3: 20.0,
        rainfallMm: 0.0,
        trafficDensity: 0.8, // Heavy congestion
      );

      final recommended = options.firstWhere((o) => o.isRecommended);
      expect(recommended.mode, TransportMode.motorcycle);
      expect(recommended.recommendationReason, contains('Fastest'));
    });
  });

  group('RoutePlannerView widget tests', () {
    testWidgets(
      'Renders mode selector, conditions, risks, and allows mode switching',
      (tester) async {
        final motor = RouteOption(
          mode: TransportMode.motorcycle,
          title: 'Motorcycle',
          estimatedDuration: const Duration(minutes: 18),
          distanceKm: 8.0,
          waypoints: const [],
          turnSteps: const ['Jalan Kemang Raya', 'Jalan Rasuna Said'],
          isRecommended: true,
          recommendationReason: 'Fastest commute through traffic.',
          identifiedRisks: const [
            'High PM2.5 Inhalation Risk: Open-air exposure to particulate fumes.',
          ],
          protectiveMeasures: const [
            'Wear an N95 or KN95 particulate respirator mask sealed securely.',
          ],
          predictedAqi: 95.0,
          pm25UgM3: 45.0,
          rainfallMm: 0.0,
          rainProbability: 0.1,
          trafficDensity: 0.5,
        );

        final car = RouteOption(
          mode: TransportMode.car,
          title: 'Car / Taxi',
          estimatedDuration: const Duration(minutes: 42),
          distanceKm: 9.5,
          waypoints: const [],
          turnSteps: const ['Jalan Kemang Raya', 'Jalan Sudirman'],
          isRecommended: false,
          recommendationReason: 'Heavy road congestion expected.',
          identifiedRisks: const ['Severe road congestion delay.'],
          protectiveMeasures: const [
            'Roll up windows and turn AC air recirculation ON.',
          ],
          predictedAqi: 95.0,
          pm25UgM3: 45.0,
          rainfallMm: 0.0,
          rainProbability: 0.1,
          trafficDensity: 0.75,
        );

        RouteOption selected = motor;
        RouteOption? tappedOption;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: RoutePlannerView(
                      options: [motor, car],
                      selectedOption: selected,
                      onOptionSelected: (newOpt) {
                        tappedOption = newOpt;
                        setState(() => selected = newOpt);
                      },
                      onConfirmRoute: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        // Mode Selector buttons
        expect(find.text('🏍️'), findsOneWidget);
        expect(find.text('🚗'), findsOneWidget);
        expect(find.text('18 min'), findsOneWidget);
        expect(find.text('42 min'), findsOneWidget);

        // Recommendation badge & reason
        expect(find.text('Fastest commute through traffic.'), findsOneWidget);

        // Environmental conditions ribbon
        expect(find.textContaining('PM2.5: 45 µg/m³'), findsOneWidget);

        // Health Advisory & Protective measures
        expect(
          find.text('Motorcycle Health & Safety Advisory'),
          findsOneWidget,
        );
        expect(
          find.textContaining('High PM2.5 Inhalation Risk'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Wear an N95 or KN95 particulate respirator mask',
          ),
          findsOneWidget,
        );

        // Tap Car mode tab
        await tester.tap(find.text('🚗'));
        await tester.pumpAndSettle();

        expect(tappedOption, isNotNull);
        expect(tappedOption!.mode, TransportMode.car);
        expect(
          find.text('Car / Taxi Health & Safety Advisory'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Roll up windows and turn AC air recirculation ON.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
