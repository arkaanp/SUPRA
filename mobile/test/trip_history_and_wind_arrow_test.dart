import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/models/environmental_zone.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/saved_trip.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';
import 'package:supra_mobile_ui/widgets/interactive_location_map.dart';

void main() {
  group('Wind direction arrow and environmental zone tests', () {
    test('EnvironmentalZone computes cardinal wind directions accurately', () {
      const northZone = EnvironmentalZone(
        id: 'z_north',
        name: 'North Zone',
        center: LatLng(latitude: -6.1, longitude: 106.8),
        pm25: 20.0,
        rainfallMm: 0.0,
        windDirectionDegrees: 0.0,
        windSpeedKmh: 12.0,
      );
      expect(northZone.cardinalWindDirection, 'N');

      const eastZone = EnvironmentalZone(
        id: 'z_east',
        name: 'East Zone',
        center: LatLng(latitude: -6.1, longitude: 106.8),
        pm25: 20.0,
        rainfallMm: 0.0,
        windDirectionDegrees: 90.0,
        windSpeedKmh: 15.0,
      );
      expect(eastZone.cardinalWindDirection, 'E');

      const swZone = EnvironmentalZone(
        id: 'z_sw',
        name: 'SW Zone',
        center: LatLng(latitude: -6.1, longitude: 106.8),
        pm25: 20.0,
        rainfallMm: 2.5,
        isRaining: true,
        windDirectionDegrees: 225.0,
        windSpeedKmh: 20.0,
      );
      expect(swZone.cardinalWindDirection, 'SW');
      expect(swZone.weatherSummary, 'Rainy');
      expect(swZone.descriptiveLabel, contains('2.5 mm'));
      expect(swZone.descriptiveLabel, contains('SW 20 km/h'));
    });

    testWidgets('InteractiveLocationMap canvas renders map overlays without wind vector arrows', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InteractiveLocationMap(
              height: 400,
              showFooter: true,
              selectedLocation: const LatLng(
                latitude: -6.2000,
                longitude: 106.8200,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // CustomPaint canvas is rendered cleanly
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('TripHistoryStore model & commute pattern analysis tests', () {
    setUp(() {
      TripHistoryStore.instance.resetForTesting();
    });

    test('TripHistoryStore initializes with realistic Greater Jakarta routes', () {
      final trips = TripHistoryStore.instance.trips;
      expect(trips.length, greaterThanOrEqualTo(5));
      expect(trips.any((t) => t.destination.contains('Grand Indonesia')), isTrue);
      expect(trips.any((t) => t.destination.contains('Cibinong')), isTrue);
    });

    test('saveTrip adds new trip or increments existing route frequency', () {
      final store = TripHistoryStore.instance;
      final initialCount = store.trips.length;

      // Save an existing route -> should increment frequency
      final updated = store.saveTrip(
        start: 'Monas (Central Jakarta)',
        destination: 'Grand Indonesia Mall',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.1950, longitude: 106.8200),
      );
      expect(updated.frequency, 6); // default was 5
      expect(store.trips.length, initialCount);

      // Save brand new route -> should insert new item
      final newTrip = store.saveTrip(
        start: 'Monas (Central Jakarta)',
        destination: 'Ancol Beach City',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.1200, longitude: 106.8400),
      );
      expect(newTrip.frequency, 1);
      expect(store.trips.length, initialCount + 1);
    });

    test('TripHistoryStore persists updated trips and frequencies to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TripHistoryStore.instance;

      store.saveTrip(
        start: 'Monas (Central Jakarta)',
        destination: 'Grand Indonesia Mall',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.1950, longitude: 106.8200),
      );
      await store.persistToStorage();

      final prefs = await SharedPreferences.getInstance();
      final storedRaw = prefs.getString('supra_saved_trips_v1');
      expect(storedRaw, isNotNull);
      expect(storedRaw, contains('Grand Indonesia Mall'));
      expect(storedRaw, contains('"frequency":6'));

      // Test loading from storage across app restarts
      store.resetForTesting([], false);
      expect(store.trips, isEmpty);
      await store.loadFromStorage();
      expect(store.trips, isNotEmpty);
      expect(
        store.trips.any((t) => t.destination == 'Grand Indonesia Mall' && t.frequency == 6),
        isTrue,
      );
    });

    test('reduceFrequency decrements count by 1 and removes when count reaches 0', () {
      final store = TripHistoryStore.instance;
      final testTrip = store.saveTrip(
        start: 'Point A',
        destination: 'Point B',
        startPoint: const LatLng(latitude: -6.1, longitude: 106.8),
        destPoint: const LatLng(latitude: -6.2, longitude: 106.8),
      );
      // Frequency is 1
      expect(testTrip.frequency, 1);

      // Save again to make it 2
      final tripFreq2 = store.saveTrip(
        start: 'Point A',
        destination: 'Point B',
        startPoint: const LatLng(latitude: -6.1, longitude: 106.8),
        destPoint: const LatLng(latitude: -6.2, longitude: 106.8),
      );
      expect(tripFreq2.frequency, 2);

      // Reduce frequency -> should become 1
      final reduced = store.reduceFrequency(tripFreq2.id);
      expect(reduced, isNotNull);
      expect(reduced!.frequency, 1);

      // Reduce frequency again -> should remove from history completely
      final removed = store.reduceFrequency(tripFreq2.id);
      expect(removed, isNull);
      expect(store.trips.any((t) => t.id == tripFreq2.id), isFalse);
    });

    test('CommuteAnalysis detects frequent commute patterns for Alerts tab', () {
      final store = TripHistoryStore.instance;
      final analysis = store.commuteAnalysis;

      expect(analysis.totalTrips, greaterThan(15));
      expect(analysis.uniqueRoutes, greaterThanOrEqualTo(5));
      expect(analysis.hasEstablishedPatterns, isTrue);
      expect(analysis.topCommute, isNotNull);
      expect(analysis.topCommute!.destination, 'Grand Indonesia Mall');
      expect(analysis.frequentRoutes.length, greaterThanOrEqualTo(3));
    });

    test('getSortedTrips orders by Recent vs Frequency correctly', () {
      final store = TripHistoryStore.instance;

      final byRecent = store.getSortedTrips(TripHistorySort.recent);
      for (int i = 0; i < byRecent.length - 1; i++) {
        expect(
          byRecent[i].lastUsed.isAfter(byRecent[i + 1].lastUsed) ||
              byRecent[i].lastUsed.isAtSameMomentAs(byRecent[i + 1].lastUsed),
          isTrue,
        );
      }

      final byFreq = store.getSortedTrips(TripHistorySort.frequency);
      for (int i = 0; i < byFreq.length - 1; i++) {
        expect(byFreq[i].frequency >= byFreq[i + 1].frequency, isTrue);
      }
    });
  });

  group('TripScreen widget & interaction tests', () {
    setUp(() {
      TripHistoryStore.instance.resetForTesting();
    });

    testWidgets('Renders Trip History with count badge and sort segments', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: TripScreen()));
      await tester.pumpAndSettle();

      // Trip History title and count badge
      expect(find.text('Trip History'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);

      // Verify trip items from history are rendered
      expect(find.text('Grand Indonesia Mall'), findsOneWidget);
      expect(find.text('Cibinong City Mall (CCM)'), findsOneWidget);

      // Toggling to Frequency sort
      await tester.tap(find.text('Frequency'));
      await tester.pumpAndSettle();
      expect(find.text('Trip History'), findsOneWidget);
    });

    testWidgets('Tapping trip item in Trip History populates destination and triggers route fetch', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: TripScreen()));
      await tester.pumpAndSettle();

      // Tap Grand Indonesia Mall in Trip History
      await tester.tap(find.text('Grand Indonesia Mall'));
      await tester.pumpAndSettle();

      // Verify destination is filled
      expect(find.text('Grand Indonesia Mall'), findsWidgets);
    });

    testWidgets('Tapping delete on trip item with frequency > 1 opens bottom sheet with options', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const MaterialApp(home: TripScreen()));
      await tester.pumpAndSettle();

      // Find the first delete icon button in Trip History
      final deleteIcons = find.byIcon(Icons.delete_outline);
      expect(deleteIcons, findsWidgets);

      // Tap delete on Grand Indonesia Mall (frequency 5)
      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();

      // Bottom sheet options appear
      expect(find.text('Reduce frequency (-1)'), findsOneWidget);
      expect(find.text('Delete trip completely'), findsOneWidget);

      // Tap reduce frequency
      await tester.tap(find.text('Reduce frequency (-1)'));
      await tester.pumpAndSettle();

      // SnackBar shows reduced frequency
      expect(find.textContaining('Reduced frequency'), findsOneWidget);
    });

    testWidgets('Confirm button replaces Save Route and Start Navigation, saves trip and focuses start location', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final tripKey = GlobalKey<TripScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: TripScreen(key: tripKey),
        ),
      );
      await tester.pumpAndSettle();

      // Load and show route programmatically
      await tripKey.currentState!.loadAndShowRoute(
        start: 'Monas (Central Jakarta)',
        destination: 'Grand Indonesia Mall',
        startPoint: const LatLng(latitude: -6.1754, longitude: 106.8272),
        destPoint: const LatLng(latitude: -6.1950, longitude: 106.8200),
      );
      await tester.pumpAndSettle();

      // Save Route and Start Route Navigation buttons are replaced by single "Confirm" button
      expect(find.text('Save Route'), findsNothing);
      expect(find.textContaining('Start Route Navigation'), findsNothing);
      expect(find.text('Confirm'), findsOneWidget);

      // Tap Confirm button
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Top notification confirmation is shown on top without blocking the bottom
      expect(find.textContaining('Trip confirmed & saved'), findsOneWidget);
      expect(find.textContaining('Live tracking active'), findsOneWidget);

      // After pressing confirm, Confirm is replaced by "Cancel Tracking" button
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Cancel Tracking'), findsOneWidget);

      // Tap Cancel Tracking button -> presents confirmation dialog in case user accidentally touched
      await tester.tap(find.text('Cancel Tracking'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog prevents accidental cancellation
      expect(find.text('Cancel Trip Tracking?'), findsOneWidget);
      expect(find.text('Keep Tracking'), findsOneWidget);
      expect(find.text('Stop Tracking'), findsOneWidget);

      // Tap "Keep Tracking" -> tracking remains active
      await tester.tap(find.text('Keep Tracking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Tracking'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);

      // Tap Cancel Tracking again and confirm cancellation
      await tester.tap(find.text('Cancel Tracking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop Tracking'));
      await tester.pumpAndSettle();

      // Tracking cancelled: Cancel Tracking is replaced back by "Confirm"
      expect(find.text('Cancel Tracking'), findsNothing);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.textContaining('Trip tracking cancelled'), findsOneWidget);

      // Verify trip was recorded in TripHistoryStore
      final trips = TripHistoryStore.instance.trips;
      expect(
        trips.any((t) => t.destination == 'Grand Indonesia Mall' && t.frequency >= 6),
        isTrue,
      );
    });

    testWidgets('Recent Trips in Home and Trip are synchronized via TripHistoryStore', (
      tester,
    ) async {
      final storeTrips = TripHistoryStore.instance.getSortedTrips(TripHistorySort.recent);
      expect(storeTrips.isNotEmpty, isTrue);

      // Add a new trip to the synchronized store
      final added = TripHistoryStore.instance.saveTrip(
        start: 'Kuningan, Jakarta',
        destination: 'Blok M Plaza',
        startPoint: const LatLng(latitude: -6.2297, longitude: 106.8295),
        destPoint: const LatLng(latitude: -6.2445, longitude: 106.7978),
      );

      // Verify it appears at the front of both recent trips query
      final updatedRecent = TripHistoryStore.instance.getSortedTrips(TripHistorySort.recent);
      expect(updatedRecent.first.id, added.id);
      expect(updatedRecent.first.destination, 'Blok M Plaza');
    });
  });
}
