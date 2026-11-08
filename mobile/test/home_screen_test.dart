import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';

void main() {
  Widget buildTestableWidget({
    VoidCallback? onNavigateToTrip,
    VoidCallback? onNavigateToAlerts,
  }) {
    return MaterialApp(
      home: HomeScreen(
        onNavigateToTrip: onNavigateToTrip,
        onNavigateToAlerts: onNavigateToAlerts,
      ),
    );
  }

  group('HomeScreen UI Specifications Test Suite', () {
    testWidgets('Level 1: Top header renders logo, SUPRA graphic, location with arrow, and bell', (tester) async {
      bool alertsTapped = false;
      await tester.pumpWidget(
        buildTestableWidget(onNavigateToAlerts: () => alertsTapped = true),
      );
      await tester.pumpAndSettle();

      // App wordmark graphic
      expect(find.text('SUPRA'), findsOneWidget);

      // Default location and dropdown arrow
      expect(find.text('Kuningan, Jakarta'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

      // Notification bell
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // Tap notification bell
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pump();
      expect(alertsTapped, isTrue);
    });

    testWidgets('Level 1: Tapping location opens location picker sheet and changes location', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Tap location to open picker
      await tester.tap(find.text('Kuningan, Jakarta'));
      await tester.pumpAndSettle();

      // Verify bottom sheet appears
      expect(find.text('Change Location'), findsOneWidget);
      expect(find.text('Pick on Interactive Map'), findsOneWidget);
      expect(find.text('Monas (Central Jakarta)'), findsOneWidget);

      // Select Monas
      await tester.tap(find.text('Monas (Central Jakarta)'));
      await tester.pumpAndSettle();

      // Verify header updated
      expect(find.text('Monas (Central Jakarta)'), findsOneWidget);
    });

    testWidgets('Level 2: Today\'s Air Quality curved card displays all required metrics', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Card Header
      expect(find.text("TODAY'S AIR QUALITY"), findsOneWidget);

      // AQI Number (72 baseline)
      expect(find.text('72'), findsOneWidget);

      // Top right of number: Category badge (Moderate)
      expect(find.text('Moderate'), findsWidgets);

      // Bottom right of number: Source
      expect(find.text('US AQI · Station Sensors'), findsOneWidget);

      // Health advisory description below number
      expect(
        find.text('Air is acceptable. Sensitive groups should limit prolonged outdoor activity.'),
        findsOneWidget,
      );

      // Bottom Row Metric 1: Umbrella symbol + Weather (Rain) + Value (35% or mm)
      expect(find.byIcon(Icons.umbrella_rounded), findsWidgets);
      expect(find.text('Rain'), findsWidgets);
      expect(find.text('35%'), findsOneWidget);

      // Bottom Row Metric 2: Traffic symbol + Traffic + Value (Heavy/Moderate)
      expect(find.byIcon(Icons.traffic_rounded), findsOneWidget);
      expect(find.text('Traffic'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);

      // Bottom Row Metric 3: Wind symbol + Wind + Value
      expect(find.byIcon(Icons.air_rounded), findsOneWidget);
      expect(find.text('Wind'), findsOneWidget);
      expect(find.text('8 km/h'), findsOneWidget);
    });

    testWidgets('Level 3: Next few hours displays combined local forecast with hour boxes', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Titles
      expect(find.text('Next few hours'), findsOneWidget);
      expect(find.text('Combined local forecast'), findsOneWidget);

      // Filter chips: 2 hr, 4 hr, 6 hr
      expect(find.text('2 hr'), findsOneWidget);
      expect(find.text('4 hr'), findsOneWidget);
      expect(find.text('6 hr'), findsOneWidget);

      // Current hour box
      expect(find.text('Now'), findsOneWidget);

      // Temperature indicators (e.g. 29°, 31°, 32°)
      expect(find.textContaining('°'), findsWidgets);

      // AQI prediction badge
      expect(find.textContaining('AQI'), findsWidgets);

      // Switch hours filter to 2 hr
      await tester.tap(find.text('2 hr'));
      await tester.pumpAndSettle();
      expect(find.text('Now'), findsOneWidget);
    });

    testWidgets('Level 4: Plan your commute section navigates to trip planner', (tester) async {
      bool tripNavigated = false;
      await tester.pumpWidget(
        buildTestableWidget(onNavigateToTrip: () => tripNavigated = true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan your commute'), findsOneWidget);
      expect(find.text('Senayan · 8.4 km away'), findsOneWidget);

      final planTripFinder = find.text('Plan trip');
      await tester.ensureVisible(planTripFinder);
      await tester.pumpAndSettle();

      expect(planTripFinder, findsOneWidget);
      expect(find.text('Slow traffic'), findsOneWidget);
      expect(find.text('Transit'), findsOneWidget);
      expect(find.text('Car'), findsOneWidget);
      expect(find.text('Bike'), findsOneWidget);

      // Tap 'Plan trip'
      await tester.tap(planTripFinder);
      await tester.pump();
      expect(tripNavigated, isTrue);
    });
  });
}
