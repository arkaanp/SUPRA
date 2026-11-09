import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/saved_trip.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/display_preferences.dart';
import 'package:supra_mobile_ui/widgets/current_conditions_panel.dart';

void main() {
  setUp(() {
    TripHistoryStore.instance.resetForTesting();
    DisplayPreferences.instance.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
    'Original Home cards, location picker and forecast strip are retained',
    (tester) async {
      var alerts = false;
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(onNavigateToAlerts: () => alerts = true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('SUPRA'), findsOneWidget);
      expect(find.text('Kuningan, Jakarta'), findsOneWidget);
      expect(find.text("TODAY'S AIR QUALITY"), findsOneWidget);
      expect(find.byType(CurrentConditionsPanel), findsNothing);
      expect(find.text('72'), findsNothing);
      expect(find.text('35%'), findsNothing);
      expect(find.text('No cached data'), findsOneWidget);
      expect(find.text('Next 12 Hours Forecast'), findsOneWidget);
      expect(find.textContaining('Live readings first'), findsOneWidget);
      expect(find.text('ML pending'), findsWidgets);
      expect(find.text('Show ML predictions'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      expect(alerts, true);
      await tester.tap(find.text('Kuningan, Jakarta'));
      await tester.pumpAndSettle();
      expect(find.text('Change Location'), findsOneWidget);
      await tester.tap(find.text('Monas (Central Jakarta)'));
      await tester.pumpAndSettle();
      expect(find.text('Monas (Central Jakarta)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Recent trips'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No saved trips yet'), findsOneWidget);
    },
  );

  testWidgets(
    'Last-known values stay in original card and are visibly stale after outage',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var fail = false;
      final observed = DateTime.now().subtract(const Duration(minutes: 10));
      final repository = ConditionsRepository(
        load: (point) async {
          if (fail) throw StateError('provider offline');
          return CurrentConditions(
            latitude: point.latitude,
            longitude: point.longitude,
            retrievedAt: DateTime.now(),
            airQuality: ConditionSignal(
              status: 'available',
              source: 'openaq',
              message: 'Station',
              kind: 'station_observation',
              validAt: observed,
              data: const {'pm25_ug_m3': 42.5},
            ),
            weather: ConditionSignal(
              status: 'available',
              source: 'open_meteo',
              message: 'Model estimate',
              kind: 'model_estimate',
              validAt: observed,
              data: const {'temperature_c': 29, 'precipitation_mm': 1.2},
            ),
            traffic: const ConditionSignal(
              status: 'available',
              source: 'tomtom',
              message: 'Nearest road',
              kind: 'provider_live_estimate',
              data: {'speed_kmh': 18},
            ),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(conditions: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('42.5'), findsOneWidget);
      expect(find.text('1.2 mm'), findsOneWidget);
      expect(find.text('29°C'), findsNWidgets(2));
      // Three separate forecast fields: temp, AQI, weather
      expect(find.text('Weather —'), findsWidgets);
      expect(find.text('AQI —'), findsWidgets);
      expect(find.text('Temp —'), findsWidgets);
      expect(find.text('ML pending'), findsWidgets);
      fail = true;
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('42.5'), findsOneWidget);
      expect(find.text('STALE · PM2.5'), findsOneWidget);
      expect(find.text('Rain · STALE'), findsOneWidget);
      expect(find.text('Traffic · STALE'), findsOneWidget);
      expect(find.text('Temp · STALE'), findsOneWidget);
      expect(find.textContaining('Observed'), findsOneWidget);
      expect(find.textContaining('Last-known reading'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ML predictions are opt-in and never fabricated when the model is absent',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(find.text('ML pending'), findsWidgets);
      expect(find.text('ML unavailable'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(DisplayPreferences.instance.showMlPredictions, isTrue);
      expect(find.text('ML unavailable'), findsWidgets);
      expect(find.textContaining('ML predictions requested'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home renders without overlap at a 16:9 phone ratio',
    (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Kuningan, Jakarta'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
