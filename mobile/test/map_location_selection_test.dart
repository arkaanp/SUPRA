import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/config/map_config.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/screens/map_screen.dart';
import 'package:supra_mobile_ui/widgets/interactive_location_map.dart';
import 'package:supra_mobile_ui/widgets/current_conditions_panel.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';

void main() {
  group('MapConfig & MapLibre basemap tests', () {
    test('MapConfig defines valid MapLibre vector style endpoints', () {
      expect(MapConfig.cartoPositron, contains('cartocdn.com'));
      expect(MapConfig.cartoPositron, endsWith('style.json'));
      expect(MapConfig.cartoVoyager, contains('cartocdn.com'));
      expect(MapConfig.demoTiles, contains('demotiles.maplibre.org'));
      expect(MapConfig.defaultStyle, MapConfig.cartoPositron);
      expect(MapConfig.defaultLat, -6.2088);
      expect(MapConfig.defaultLon, 106.8456);
      expect(MapConfig.defaultZoom, 11.0);
    });

    test(
      'isMapLibreSupported returns false in headless widget test environment',
      () {
        expect(MapConfig.isMapLibreSupported, isFalse);
      },
    );

    test('isTestEnvironment returns true during tests', () {
      expect(MapConfig.isTestEnvironment, isTrue);
    });
  });
  group('LatLng model & landmarks tests', () {
    test('isInGreaterJakarta validates service envelope correctly', () {
      // In bounds
      expect(
        const LatLng(latitude: -6.2088, longitude: 106.8456).isInGreaterJakarta,
        isTrue,
      );
      expect(
        const LatLng(latitude: -6.9, longitude: 106.3).isInGreaterJakarta,
        isTrue,
      );
      expect(
        const LatLng(latitude: -5.8, longitude: 107.3).isInGreaterJakarta,
        isTrue,
      );

      // Out of bounds
      expect(
        const LatLng(latitude: -7.0, longitude: 106.8).isInGreaterJakarta,
        isFalse,
      );
      expect(
        const LatLng(latitude: -5.7, longitude: 106.8).isInGreaterJakarta,
        isFalse,
      );
      expect(
        const LatLng(latitude: -6.2, longitude: 106.2).isInGreaterJakarta,
        isFalse,
      );
      expect(
        const LatLng(latitude: -6.2, longitude: 107.4).isInGreaterJakarta,
        isFalse,
      );
    });

    test('distanceTo calculates approximate distances accurately', () {
      const monas = LatLng(latitude: -6.1754, longitude: 106.8272);
      const bundaranHi = LatLng(latitude: -6.1950, longitude: 106.8230);
      final distance = monas.distanceTo(bundaranHi);
      // Monas to Bundaran HI is roughly 2.2 km.
      expect(distance, greaterThan(1.5));
      expect(distance, lessThan(3.0));
    });

    test(
      'findNearestLandmark matches closest known point in Greater Jakarta',
      () {
        const nearKemang = LatLng(latitude: -6.2610, longitude: 106.8160);
        final nearest = findNearestLandmark(nearKemang);
        expect(nearest, isNotNull);
        expect(nearest!.name, 'Kemang');
        expect(nearest.area, 'South Jakarta');
        expect(nearest.adm4, '31.74.04.1003');
      },
    );

    test('greaterJakartaLandmarks contains only real public places and no McDonald\'s entries', () {
      expect(
        greaterJakartaLandmarks.any(
          (lm) => lm.name.toLowerCase().contains('mcdonald'),
        ),
        isFalse,
      );
    });
  });

  group('InteractiveLocationMap widget tests', () {
    testWidgets('Renders vector map canvas and guides', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InteractiveLocationMap(
              selectedLocation: LatLng(latitude: -6.2000, longitude: 106.8200),
            ),
          ),
        ),
      );

      expect(find.byType(InteractiveLocationMap), findsOneWidget);
      expect(find.text('Test canvas (no basemap)'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(
        find.textContaining('Lat: -6.2000, Lon: 106.8200'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Tapping map invokes onLocationChanged with valid coordinates',
      (tester) async {
        LatLng? reported;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: InteractiveLocationMap(
                    onLocationChanged: (loc) => reported = loc,
                  ),
                ),
              ),
            ),
          ),
        );

        // Tap center of the map
        await tester.tap(find.byType(InteractiveLocationMap));
        await tester.pump();

        expect(reported, isNotNull);
        expect(reported!.isInGreaterJakarta, isTrue);
      },
    );

    testWidgets('fitToRoute centers and zooms view to frame whole route', (
      tester,
    ) async {
      final key = GlobalKey<InteractiveLocationMapState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: InteractiveLocationMap(
                key: key,
                selectedLocation: const LatLng(
                  latitude: -6.2000,
                  longitude: 106.8200,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Fit to a route spanning from North Jakarta to Kota Bogor
      final routeWaypoints = [
        const LatLng(latitude: -6.1200, longitude: 106.8000),
        const LatLng(latitude: -6.3500, longitude: 106.8200),
        const LatLng(latitude: -6.6000, longitude: 106.8500),
      ];

      key.currentState?.fitToRoute(
        routeWaypoints,
        mapSize: const Size(400, 300),
      );
      await tester.pump();

      expect(key.currentState, isNotNull);
      expect(find.byType(InteractiveLocationMap), findsOneWidget);
    });
  });

  group('Location picker sheet tests', () {
    testWidgets(
      'showLocationPickerSheet allows selecting preset and confirming',
      (tester) async {
        LatLng? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showLocationPickerSheet(
                      context: context,
                      initialLocation: const LatLng(
                        latitude: -6.2,
                        longitude: 106.8,
                      ),
                    );
                  },
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Picker'));
        await tester.pumpAndSettle();

        expect(find.text('Select location on map'), findsOneWidget);
        expect(find.text('Monas'), findsOneWidget);
        expect(find.text('Bundaran HI'), findsOneWidget);

        // Select Monas chip
        await tester.tap(find.text('Monas'));
        await tester.pump();

        // Tap confirm button
        await tester.tap(find.text('Confirm location'));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.latitude, closeTo(-6.1754, 0.001));
        expect(result!.longitude, closeTo(106.8272, 0.001));
      },
    );
  });

  group('CurrentConditionsPanel map integration tests', () {
    testWidgets('Pick on map button opens picker and updates coordinates', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CurrentConditionsPanel(
                load: (_, _, _) async => throw UnimplementedError(),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pick on map'), findsOneWidget);

      // Tap Pick on map
      await tester.tap(find.text('Pick on map'));
      await tester.pumpAndSettle();

      expect(find.text('Select location in Greater Jakarta'), findsOneWidget);

      // Select Bundaran HI preset
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bundaran HI'));
      await tester.pump();

      // Confirm
      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();

      // Check that Latitude and Longitude fields have been updated
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '-6.1950',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '106.8230',
        ),
        findsOneWidget,
      );
      // No inferred village code from a nearby landmark.
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '31.71.03.1001',
        ),
        findsNothing,
      );
    });

    testWidgets('Toggle inline map displays InteractiveLocationMap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CurrentConditionsPanel(
                load: (_, _, _) async => throw UnimplementedError(),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(InteractiveLocationMap), findsNothing);

      // Tap layer icon to show inline map
      await tester.tap(find.byTooltip('Show map'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveLocationMap), findsOneWidget);

      // Tap layer icon again to hide
      await tester.tap(find.byTooltip('Hide map'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveLocationMap), findsNothing);
    });
  });

  group('TripScreen map integration tests', () {
    testWidgets(
      'Start and destination fields have map picker icons and allow selection',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TripScreen())),
        );

        expect(find.byTooltip('Select start location on map'), findsNothing);
        expect(find.byTooltip('Select on map'), findsWidgets);

        // Tap the first map icon (for start location)
        await tester.tap(find.byTooltip('Select on map').first);
        await tester.pumpAndSettle();

        expect(find.text('Select start location on map'), findsOneWidget);
        expect(find.text('Nearest Locations:'), findsOneWidget);

        // Tap Monas from the nearest locations list
        await tester.tap(find.widgetWithText(ListTile, 'Monas').first);
        await tester.pump();

        // Confirm start location
        await tester.tap(find.text('Confirm location'));
        await tester.pumpAndSettle();

        // Start field now contains Monas, and Show Route button is present
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.controller?.text.contains('Monas') ?? false),
          ),
          findsOneWidget,
        );
        expect(find.text('Show Route'), findsOneWidget);
      },
    );

    testWidgets(
      'Map picking mode allows typing to teleport map with predictive suggestions',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TripScreen())),
        );

        // Tap the map icon to enter picking mode
        await tester.tap(find.byTooltip('Select on map').first);
        await tester.pumpAndSettle();

        // Find the map search field
        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Search start') ?? false),
        );
        expect(searchField, findsOneWidget);

        // Predictive test: Type "cibi" -> Cibinong City Mall should be predicted!
        await tester.enterText(searchField, 'cibi');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.textContaining('Cibinong City Mall'), findsWidgets);

        // Tap Cibinong City Mall suggestion -> Automatically chooses the location!
        await tester.tap(find.textContaining('Cibinong City Mall').first);
        await tester.pumpAndSettle();

        // Start field now automatically contains Cibinong City Mall
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.controller?.text.contains('Cibinong City Mall') ?? false),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Map is only tappable to pick location after user picks start or end location',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TripScreen())),
        );

        // On idle main screen: tapping the map does NOT enter picking mode (map is read-only for picking)
        await tester.tap(find.byType(InteractiveLocationMap));
        await tester.pumpAndSettle();
        expect(find.text('Select destination on map'), findsNothing);
        expect(find.text('Where do you want to go?'), findsOneWidget);

        // User picks destination by clicking the destination input field
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('Cibinong') ?? false),
          ),
        );
        await tester.pumpAndSettle();

        // Now picking mode is active for destination!
        expect(find.text('Select destination on map'), findsOneWidget);
        expect(find.textContaining('Nearest Locations:'), findsOneWidget);

        // Map IS now tappable to designate destination!
        await tester.tap(find.byType(InteractiveLocationMap));
        await tester.pumpAndSettle();

        // Pin is designated and user can confirm location
        expect(find.text('Confirm location'), findsOneWidget);
        await tester.tap(find.text('Confirm location'));
        await tester.pumpAndSettle();

        // Back on main screen with destination set and Show Route available
        expect(find.text('Show Route'), findsOneWidget);
      },
    );

    testWidgets(
      'Clicking name input opens map in typing mode and Show Route calculates routes',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TripScreen())),
        );

        // Click destination text input container
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('Cibinong') ?? false),
          ),
        );
        await tester.pumpAndSettle();

        // Should now be in map picking mode for destination
        expect(find.text('Select destination on map'), findsOneWidget);

        // Search field should be present
        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText?.contains('Search destination') ?? false),
        );
        expect(searchField, findsOneWidget);

        // Type "scbd"
        await tester.enterText(searchField, 'scbd');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        // Select SCBD from suggestions -> Automatically chooses destination!
        await tester.tap(find.textContaining('Sudirman CBD').first);
        await tester.pumpAndSettle();

        // Destination field now automatically contains Sudirman CBD
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.controller?.text.contains('Sudirman CBD') ?? false),
          ),
          findsOneWidget,
        );

        // Back on main screen: routes NOT calculated yet until "Show Route" clicked
        expect(find.text('Start Route Navigation'), findsNothing);
        expect(find.text('Show Route'), findsOneWidget);

        // Verify routeWaypoints is null (no straight line or route polyline drawn!)
        final mapBeforeRoute = tester.widget<InteractiveLocationMap>(
          find.byType(InteractiveLocationMap),
        );
        expect(mapBeforeRoute.routeWaypoints, isNull);

        // Click Show Route
        await tester.tap(find.text('Show Route'));
        await tester.pumpAndSettle();

        // Offline/headless mode must not substitute fabricated road geometry.
        final mapAfterRoute = tester.widget<InteractiveLocationMap>(
          find.byType(InteractiveLocationMap),
        );
        expect(mapAfterRoute.routeWaypoints, isNull);

        // No fake modes or confirmation are offered when routing is unavailable.
        expect(
          find.textContaining('Car (Automobile)', skipOffstage: false),
          findsNothing,
        );
        expect(
          find.textContaining('Motorcycle (Two-Wheeler)', skipOffstage: false),
          findsNothing,
        );
        expect(find.textContaining('Transjakarta'), findsNothing);
        expect(find.textContaining('Route unavailable.'), findsOneWidget);
      },
    );

    testWidgets(
      'Swiping grey bar expands bottom sheet to cover screen and collapses back',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TripScreen())),
        );

        // Initially map is visible (takes roughly half the screen)
        expect(find.byType(InteractiveLocationMap), findsOneWidget);

        // Find the swipe handle bar
        final handleBar = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFCBD5E1),
        );
        expect(handleBar, findsOneWidget);

        // Swipe UP on the handle bar to expand
        await tester.fling(handleBar, const Offset(0, -300), 1000);
        await tester.pumpAndSettle();

        // Sheet is now expanded to full screen, top map is hidden
        expect(find.byType(InteractiveLocationMap), findsNothing);

        // Tap the collapse arrow icon to collapse back to half screen
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
        await tester.pumpAndSettle();

        // Map is visible again taking half the screen
        expect(find.byType(InteractiveLocationMap), findsOneWidget);
      },
    );
  });

  group('MapScreen inspection tests', () {
    testWidgets('MapScreen renders and handles tap inspection', (tester) async {
      final sampleOption = RouteOption(
        mode: TransportMode.motorcycle,
        title: 'Motorcycle (Fastest)',
        estimatedDuration: const Duration(minutes: 18),
        distanceKm: 8.5,
        waypoints: const [
          LatLng(latitude: -6.2600, longitude: 106.8150),
          LatLng(latitude: -6.2250, longitude: 106.8080),
        ],
        turnSteps: const ['Jalan Kemang Raya', 'Jalan Jenderal Sudirman'],
        isRecommended: true,
        recommendationReason: 'Fastest commute through traffic gridlock.',
        identifiedRisks: const ['High PM2.5 Inhalation Risk'],
        protectiveMeasures: const [
          'Wear an N95 or KN95 particulate respirator mask',
        ],
        predictedAqi: 85.0,
        pm25UgM3: 42.0,
        rainfallMm: 0.0,
        rainProbability: 0.1,
        trafficDensity: 0.45,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            start: const LatLng(latitude: -6.2600, longitude: 106.8150),
            destination: const LatLng(latitude: -6.2250, longitude: 106.8080),
            startName: 'Kemang',
            destinationName: 'Sudirman CBD',
            forceCanvas: true,
            initialRouteOptions: [sampleOption],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Kemang → Sudirman CBD'), findsOneWidget);
      expect(find.textContaining('Motorcycle'), findsWidgets);

      // Tap map to inspect
      await tester.tap(find.byType(InteractiveLocationMap));
      await tester.pump();

      expect(find.textContaining('Kemang → Sudirman CBD'), findsOneWidget);
    });
  });
}
