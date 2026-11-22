import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/saved_trip.dart';
import 'package:supra_mobile_ui/screens/home_screen.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/widgets/current_conditions_panel.dart';
import 'package:supra_mobile_ui/utils/display_text.dart';

void main() {
  setUp(() => TripHistoryStore.instance.resetForTesting());
  testWidgets('Home shows the weather issue time rather than future validity', (
    tester,
  ) async {
    final fetched = DateTime.now();
    final issued = fetched.subtract(const Duration(hours: 2));
    final valid = fetched.add(const Duration(hours: 1));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          conditions: ConditionsRepository(
            load: (point) async => CurrentConditions(
              latitude: point.latitude,
              longitude: point.longitude,
              retrievedAt: fetched,
              weather: ConditionSignal(
                status: 'available',
                source: 'bmkg',
                message: '',
                kind: 'provider_forecast',
                validAt: valid,
                data: {
                  'temperature_c': 29,
                  'precipitation_mm': 0,
                  'issued_at': issued.toIso8601String(),
                },
              ),
              airQuality: ConditionsRepository.unavailable,
              traffic: ConditionsRepository.unavailable,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cuaca: ${formatWib(issued)}'), findsOneWidget);
    expect(find.text('Cuaca: ${formatWib(valid)}'), findsNothing);
    expect(find.text('Kualitas udara: Belum tersedia'), findsOneWidget);
  });
  testWidgets('Home accepts device coordinates after requesting permission', (
    tester,
  ) async {
    const channel = MethodChannel('flutter.baseflow.com/geolocator');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'isLocationServiceEnabled' => true,
        'checkPermission' => 0,
        'requestPermission' => 2,
        'getCurrentPosition' => {'latitude': -6.18, 'longitude': 106.83},
        _ => throw MissingPluginException(),
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kuningan, Jakarta'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.text('Gunakan lokasi saat ini'));
    await tester.pumpAndSettle();
    expect(calls, [
      'isLocationServiceEnabled',
      'checkPermission',
      'requestPermission',
      'getCurrentPosition',
    ]);
    expect(find.text('Lokasi saat ini'), findsOneWidget);
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
      expect(find.text('KUALITAS UDARA HARI INI'), findsOneWidget);
      expect(find.byType(CurrentConditionsPanel), findsNothing);
      expect(find.text('72'), findsNothing);
      expect(find.text('35%'), findsNothing);
      expect(find.text('Belum ada data tersimpan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Prakiraan 12 jam ke depan'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Prakiraan 12 jam ke depan'), findsOneWidget);
      expect(find.textContaining('Aktifkan prediksi ML'), findsOneWidget);
      expect(find.text('Prediksi ML nonaktif'), findsWidgets);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      expect(alerts, true);
      await tester.tap(find.text('Kuningan, Jakarta'));
      await tester.pumpAndSettle();
      expect(find.text('Ubah lokasi'), findsOneWidget);
      await tester.tap(find.text('Monas (Jakarta Pusat)'));
      await tester.pumpAndSettle();
      expect(find.text('Monas (Jakarta Pusat)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Perjalanan terakhir'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Belum ada perjalanan tersimpan'), findsOneWidget);
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
      final fetched = DateTime.now();
      final repository = ConditionsRepository(
        load: (point) async {
          if (fail) throw StateError('provider offline');
          return CurrentConditions(
            latitude: point.latitude,
            longitude: point.longitude,
            retrievedAt: fetched,
            airQuality: ConditionSignal(
              status: 'available',
              source: 'openaq',
              message: 'Stasiun',
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
      expect(find.text('Cuaca —'), findsWidgets);
      expect(find.text('AQI —'), findsWidgets);
      expect(find.text('Suhu —'), findsWidgets);
      expect(find.text('Prediksi ML nonaktif'), findsWidgets);
      expect(find.text('Pembaruan data terakhir'), findsOneWidget);
      expect(
        find.text('Kualitas udara: ${formatWib(observed)}'),
        findsOneWidget,
      );
      expect(find.text('Cuaca: ${formatWib(observed)}'), findsOneWidget);
      expect(find.text('Lalu lintas: ${formatWib(fetched)}'), findsOneWidget);
      fail = true;
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('42.5'), findsOneWidget);
      expect(find.text('DATA LAMA · PM2.5'), findsOneWidget);
      expect(find.text('Hujan · DATA LAMA'), findsOneWidget);
      expect(find.text('Lalu lintas · DATA LAMA'), findsOneWidget);
      expect(find.text('Suhu · DATA LAMA'), findsOneWidget);
      expect(find.textContaining('Valid:'), findsNothing);
      expect(
        find.textContaining('Data terakhir tersimpan — bukan kondisi terkini.'),
        findsOneWidget,
      );
      expect(
        find.text('Kualitas udara: ${formatWib(observed)} · data lama'),
        findsOneWidget,
      );
      expect(
        find.text('Cuaca: ${formatWib(observed)} · data lama'),
        findsOneWidget,
      );
      expect(
        find.text('Lalu lintas: ${formatWib(fetched)} · data lama'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
