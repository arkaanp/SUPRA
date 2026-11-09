import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/environmental_zone.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/environmental_service.dart';

void main() {
  const point = LatLng(latitude: -6.2, longitude: 106.8);
  test('Geographic anchors have no readings, wind, or reassuring defaults', () {
    expect(EnvironmentalService.defaultZones.length, 10);
    for (final zone in EnvironmentalService.defaultZones) {
      expect(zone.pm25, isNull);
      expect(zone.rainfallMm, isNull);
      expect(zone.windSpeedKmh, isNull);
      expect(zone.weatherSummary, contains('unavailable'));
      expect(zone.healthAdvisory, contains('unavailable'));
    }
  });
  test('Station sample does not imply AQI or a measured city polygon', () {
    const zone = EnvironmentalZone(
      id: 'sample',
      name: 'Sample',
      center: point,
      pm25: 20,
      rainfallMm: 0,
    );
    expect(zone.aqiCategory, 'PM2.5, not AQI');
    expect(zone.pm25Color, Colors.transparent);
    expect(zone.compositeAreaColor, Colors.transparent);
    expect(zone.weatherSummary, 'Precipitation 0.0 mm');
  });
  test('Only explicit selected sample is fetched; partial/stale signals stay unknown', () async {
    var calls = 0;
    final service = EnvironmentalService(
      conditions: ConditionsRepository(
        load: (p) async {
          calls++;
          return CurrentConditions(
            latitude: p.latitude,
            longitude: p.longitude,
            retrievedAt: DateTime.now(),
            weather: ConditionSignal(
              status: 'available',
              source: 'open_meteo',
              message: 'Model estimate',
              kind: 'model_estimate',
              validAt: DateTime.now(),
              data: const {'precipitation_mm': 0},
            ),
            airQuality: ConditionSignal(
              status: 'stale',
              source: 'openaq',
              message: 'Stale station',
              kind: 'station_observation',
              validAt: DateTime.now().subtract(const Duration(days: 1)),
              data: const {'pm25_ug_m3': 45},
            ),
            traffic: ConditionsRepository.unavailable,
          );
        },
      ),
    );
    await service.fetchLiveZoneData();
    expect(calls, 0);
    final sample = (await service.fetchLiveZoneData(point: point)).single;
    expect(calls, 1);
    expect(sample.pm25, 45);
    expect(sample.rainfallMm, 0);
    expect(sample.conditions!.airQuality.status, 'stale');
    expect(sample.descriptiveLabel, contains('openaq: stale'));
  });
  test('Polygon containment and missing wind remain explicit', () {
    const zone = EnvironmentalZone(
      id: 'polygon',
      name: 'Polygon',
      center: point,
      polygonBounds: [
        LatLng(latitude: -6.1, longitude: 106.7),
        LatLng(latitude: -6.1, longitude: 106.9),
        LatLng(latitude: -6.3, longitude: 106.9),
        LatLng(latitude: -6.3, longitude: 106.7),
      ],
    );
    expect(zone.contains(point), true);
    expect(
      zone.contains(const LatLng(latitude: -6.6, longitude: 106.8)),
      false,
    );
    expect(zone.cardinalWindDirection, 'Unavailable');
    expect(zone.copyWith(windDirectionDegrees: 90).cardinalWindDirection, 'E');
  });
}
