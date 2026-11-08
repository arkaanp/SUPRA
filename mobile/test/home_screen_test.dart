import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/trip.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';

void main() {
  Widget buildTestableWidget({
    void Function(Trip? trip)? onNavigateToTrip,
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

    testWidgets('Level 2: Today\'s Air Quality curved card displays all required metrics and (?) guides', (tester) async {
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

      // Bottom Row Metric 3: Thermometer symbol + Temp + Value (Replacing Wind)
      expect(find.byIcon(Icons.thermostat_rounded), findsOneWidget);
      expect(find.text('Temp'), findsOneWidget);
      expect(find.text('29°C'), findsOneWidget);

      // Verify question mark (?) icons exist for Air Quality and Rain
      expect(find.byIcon(Icons.question_mark_rounded), findsNWidgets(2));

      // Tap the first question mark (?) for Air Quality explanation
      await tester.tap(find.byIcon(Icons.question_mark_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Understanding Air Quality (AQI)'), findsOneWidget);
      expect(find.text('AQI Severity Bands & Health Advisory'), findsOneWidget);

      // Dismiss explanation sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Tap the second question mark (?) for Rain explanation
      await tester.tap(find.byIcon(Icons.question_mark_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('Understanding Rain & Commute Risk'), findsOneWidget);
      expect(find.text('Rainfall Rates & Commuter Precautions'), findsOneWidget);

      // Dismiss rain sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
    });

    testWidgets('Level 3: Always shows 12-hour forecast without 2h/4h/6h toggle', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // New descriptive titles matching 12 hours
      expect(find.text('Next 12 Hours Forecast'), findsOneWidget);
      expect(
        find.text('Combined local weather, air quality & temperature predictions'),
        findsOneWidget,
      );

      // Ensure 2h 4h 6h toggle option is removed
      expect(find.text('2 hr'), findsNothing);
      expect(find.text('4 hr'), findsNothing);
      expect(find.text('6 hr'), findsNothing);

      // Current hour box is present
      expect(find.text('Now'), findsOneWidget);

      // Temperature indicators (e.g. 29°, 31°, 32°)
      expect(find.textContaining('°'), findsWidgets);

      // AQI prediction badge
      expect(find.textContaining('AQI'), findsWidgets);

      // Navigation chevrons exist to scroll/slide through all 12 hours
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('Level 4: Plan your commute is removed and tapping saved trip navigates to Trip', (tester) async {
      Trip? selectedTrip;
      await tester.pumpWidget(
        buildTestableWidget(onNavigateToTrip: (trip) => selectedTrip = trip),
      );
      await tester.pumpAndSettle();

      // Ensure "Plan your commute" section is completely removed
      expect(find.text('Plan your commute'), findsNothing);
      expect(find.text('Slow traffic'), findsNothing);

      // Drag vertical scroll to reveal Recent trips
      final mainScrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Recent trips'),
        200,
        scrollable: mainScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent trips'), findsOneWidget);

      // Add a test trip and rebuild
      final testTrip = Trip(
        id: 'test_trip_1',
        userId: 'u1',
        name: 'Office Commute',
        startLocation: 'Kuningan, Jakarta',
        destination: 'Bundaran HI',
        plannedDeparture: DateTime.now(),
      );
      SupraService.instance.setTripsForTesting([testTrip]);

      await tester.pumpWidget(
        buildTestableWidget(onNavigateToTrip: (trip) => selectedTrip = trip),
      );
      await tester.pumpAndSettle();

      final tripFinder = find.text('Office Commute');
      await tester.scrollUntilVisible(
        tripFinder,
        100,
        scrollable: mainScrollable,
      );
      await tester.pumpAndSettle();
      expect(tripFinder, findsOneWidget);

      await tester.tap(tripFinder);
      await tester.pump();

      expect(selectedTrip, isNotNull);
      expect(selectedTrip!.name, 'Office Commute');
      expect(selectedTrip!.destination, 'Bundaran HI');
    });
  });
}
