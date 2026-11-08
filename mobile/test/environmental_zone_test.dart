import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/environmental_zone.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/services/environmental_service.dart';
import 'package:supra_mobile_ui/widgets/interactive_location_map.dart';

void main() {
  group('EnvironmentalZone model tests', () {
    test('aqiCategory maps PM2.5 thresholds correctly', () {
      expect(
        const EnvironmentalZone(
          id: '1',
          name: 'Z1',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 8.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Good',
      );

      expect(
        const EnvironmentalZone(
          id: '2',
          name: 'Z2',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 25.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Moderate',
      );

      expect(
        const EnvironmentalZone(
          id: '3',
          name: 'Z3',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 48.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Unhealthy for Sensitive Groups',
      );

      expect(
        const EnvironmentalZone(
          id: '4',
          name: 'Z4',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 85.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Unhealthy',
      );

      expect(
        const EnvironmentalZone(
          id: '5',
          name: 'Z5',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 180.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Very Unhealthy',
      );

      expect(
        const EnvironmentalZone(
          id: '6',
          name: 'Z6',
          center: LatLng(latitude: -6.2, longitude: 106.8),
          pm25: 280.0,
          rainfallMm: 0.0,
        ).aqiCategory,
        'Hazardous',
      );
    });

    test('pm25Color darkens as PM2.5 severity increases', () {
      const mildUnhealthy = EnvironmentalZone(
        id: 'u1',
        name: 'Mild Unhealthy',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 60.0,
        rainfallMm: 0.0,
      );

      const severeUnhealthy = EnvironmentalZone(
        id: 'u2',
        name: 'Severe Unhealthy',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 145.0,
        rainfallMm: 0.0,
      );

      // Higher PM2.5 in Unhealthy band should have darker luminance or higher opacity
      final colorMild = mildUnhealthy.solidAqiColor;
      final colorSevere = severeUnhealthy.solidAqiColor;
      expect(colorSevere.computeLuminance(), lessThan(colorMild.computeLuminance()));
    });

    test('Rain detection and atmospheric color are accurate', () {
      const rainingZone = EnvironmentalZone(
        id: 'r1',
        name: 'Bogor Rain',
        center: LatLng(latitude: -6.6, longitude: 106.8),
        pm25: 35.0,
        rainfallMm: 4.5,
        isRaining: true,
      );

      expect(rainingZone.isRaining, isTrue);
      expect(rainingZone.rainColor, isNot(Colors.transparent));
      expect(rainingZone.rainColor.b, greaterThan(rainingZone.rainColor.r));
      // Heavier rain darkens in luminance or increases opacity
      const heavyRainZone = EnvironmentalZone(
        id: 'r2',
        name: 'Heavy Bogor Rain',
        center: LatLng(latitude: -6.6, longitude: 106.8),
        pm25: 35.0,
        rainfallMm: 9.5,
        isRaining: true,
      );
      expect(
        heavyRainZone.rainColor.computeLuminance(),
        lessThan(rainingZone.rainColor.computeLuminance()),
      );
      expect(rainingZone.descriptiveLabel, contains('🌧️ 4.5 mm'));
    });

    test('pm25Color and rainColor maintain ultra-low opacity to be barely visible', () {
      const goodZone = EnvironmentalZone(
        id: 'g',
        name: 'G',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 10.0,
        rainfallMm: 0.0,
      );
      const modZone = EnvironmentalZone(
        id: 'm',
        name: 'M',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 25.0,
        rainfallMm: 0.0,
      );
      const unhZone = EnvironmentalZone(
        id: 'u',
        name: 'U',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 80.0,
        rainfallMm: 0.0,
      );
      const hazZone = EnvironmentalZone(
        id: 'h',
        name: 'H',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 300.0,
        rainfallMm: 0.0,
      );
      const rainZone = EnvironmentalZone(
        id: 'r',
        name: 'R',
        center: LatLng(latitude: -6.2, longitude: 106.8),
        pm25: 20.0,
        rainfallMm: 5.0,
        isRaining: true,
      );

      // Verify opacity is barely visible (all single <= 0.08, composite <= 0.12)
      expect(goodZone.pm25Color.a, lessThanOrEqualTo(0.03));
      expect(modZone.pm25Color.a, lessThanOrEqualTo(0.04));
      expect(unhZone.pm25Color.a, lessThanOrEqualTo(0.06));
      expect(hazZone.pm25Color.a, lessThanOrEqualTo(0.08));
      expect(rainZone.rainColor.a, lessThanOrEqualTo(0.06));
      expect(rainZone.compositeAreaColor.a, lessThanOrEqualTo(0.12));
    });

    test('contains correctly checks polygon boundaries', () {
      const zone = EnvironmentalZone(
        id: 'poly_test',
        name: 'Polygon Zone',
        center: LatLng(latitude: -6.20, longitude: 106.82),
        pm25: 50.0,
        rainfallMm: 0.0,
        polygonBounds: [
          LatLng(latitude: -6.18, longitude: 106.80),
          LatLng(latitude: -6.18, longitude: 106.85),
          LatLng(latitude: -6.22, longitude: 106.85),
          LatLng(latitude: -6.22, longitude: 106.80),
        ],
      );

      // Inside
      expect(
        zone.contains(const LatLng(latitude: -6.20, longitude: 106.82)),
        isTrue,
      );

      // Outside
      expect(
        zone.contains(const LatLng(latitude: -6.10, longitude: 106.82)),
        isFalse,
      );
      expect(
        zone.contains(const LatLng(latitude: -6.20, longitude: 106.95)),
        isFalse,
      );
    });
  });

  group('EnvironmentalService tests', () {
    test('canonical zones cover Greater Jakarta subregions with 0.0mm initial rain baseline', () {
      final zones = EnvironmentalService.getCanonicalZones();
      expect(zones.length, greaterThanOrEqualTo(10));

      final names = zones.map((z) => z.name).toList();
      expect(names, contains('Jakarta Selatan'));
      expect(names, contains('Jakarta Pusat'));
      expect(names, contains('Jakarta Barat'));
      expect(names, contains('Jakarta Timur'));
      expect(names, contains('Jakarta Utara'));
      expect(names, contains('Depok'));
      expect(names, contains('Kota Bogor'));
      expect(names, contains('Cibinong'));
      expect(names, contains('Tangerang / BSD'));
      expect(names, contains('Bekasi'));

      // Ensure no synthetic rain is hardcoded in defaults
      for (final z in zones) {
        expect(z.rainfallMm, 0.0);
        expect(z.isRaining, isFalse);
      }
    });

    test('fetchLiveZoneData parses real Open-Meteo multi-coordinate responses', () async {
      final service = EnvironmentalService();
      final zones = await service.fetchLiveZoneData();
      expect(zones.length, 10);
      for (final z in zones) {
        expect(z.pm25, greaterThan(0));
      }
    });

    test('findZoneAt locates corresponding subregion for known landmarks', () {
      // Bundaran HI is in Jakarta Pusat (-6.1950, 106.8230)
      final central = EnvironmentalService.findZoneAt(
        const LatLng(latitude: -6.1950, longitude: 106.8230),
      );
      expect(central, isNotNull);
      expect(central!.name, 'Jakarta Pusat');

      // Kemang is in Jakarta Selatan (-6.2610, 106.8160)
      final south = EnvironmentalService.findZoneAt(
        const LatLng(latitude: -6.2610, longitude: 106.8160),
      );
      expect(south, isNotNull);
      expect(south!.name, 'Jakarta Selatan');

      // Kebun Raya Bogor is in Kota Bogor (-6.6000, 106.7970)
      final bogor = EnvironmentalService.findZoneAt(
        const LatLng(latitude: -6.6000, longitude: 106.7970),
      );
      expect(bogor, isNotNull);
      expect(bogor!.name, 'Kota Bogor');
    });
  });

  group('InteractiveLocationMap environmental indicators tests', () {
    testWidgets('Renders Eco Layers selector and AQI Guide button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InteractiveLocationMap(
              showEnvironmentalOverlays: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Eco Layers'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('AQI Guide'), findsOneWidget);
    });

    testWidgets('Tapping AQI Guide opens bottom sheet guide with scale descriptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InteractiveLocationMap(
              showEnvironmentalOverlays: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap AQI Guide
      await tester.tap(find.text('AQI Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Air Quality (PM2.5) & Rain Guide'), findsOneWidget);
      expect(find.textContaining('Open-Meteo & OpenAQ'), findsOneWidget);
      expect(find.text('0 – 12 µg/m³'), findsOneWidget);
      expect(find.text('55.5 – 150.4 µg/m³'), findsOneWidget);
      expect(find.text('Rain Active (>0.5 mm)'), findsOneWidget);
      expect(find.text('Precipitation Radar'), findsOneWidget);
    });
  });
}
