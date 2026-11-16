import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/services/commute_recommendations.dart';

void main() {
  test('CommuteRecommendations ranks by preferences without altering route duration or ETA', () {
    final now = DateTime.now();
    final freshWeather = ConditionSignal(
      status: 'available',
      source: 'open_meteo',
      message: 'Clear',
      validAt: now,
      data: {'precipitation_mm': 2.5, 'temperature_c': 33.0},
    );
    final freshAir = ConditionSignal(
      status: 'available',
      source: 'openaq',
      message: 'Station',
      validAt: now,
      data: {'pm25_ug_m3': 45.0, 'aqi': 120.0},
    );
    final freshTrafficCongested = ConditionSignal(
      status: 'available',
      source: 'tomtom',
      message: 'Congested',
      kind: 'provider_live_estimate',
      validAt: now,
      data: {
        'speed_kmh': 10.0,
        'free_flow_speed_kmh': 40.0,
        'confidence': 0.8,
        'road_closed': false,
      },
    );
    final conditions = CurrentConditions(
      latitude: -6.2,
      longitude: 106.8,
      retrievedAt: now,
      weather: freshWeather,
      airQuality: freshAir,
      traffic: freshTrafficCongested,
    );

    final car = RouteOption(
      mode: TransportMode.car,
      title: 'Drive',
      estimatedDuration: const Duration(minutes: 30),
      distanceKm: 12.0,
      waypoints: const [LatLng(latitude: -6.2, longitude: 106.8)],
      recommendationReason: 'Fastest direct road',
      identifiedRisks: [],
      protectiveMeasures: [],
      conditions: conditions,
    );

    final moto = RouteOption(
      mode: TransportMode.motorcycle,
      title: 'Ride',
      estimatedDuration: const Duration(minutes: 25),
      distanceKm: 11.0,
      waypoints: const [LatLng(latitude: -6.2, longitude: 106.8)],
      recommendationReason: 'Motorcycle route',
      identifiedRisks: [],
      protectiveMeasures: [],
      conditions: conditions,
    );

    final transit = RouteOption(
      mode: TransportMode.publicTransit,
      title: 'Transit',
      estimatedDuration: const Duration(minutes: 35),
      distanceKm: 14.0,
      waypoints: const [LatLng(latitude: -6.2, longitude: 106.8)],
      recommendationReason: 'MRT line',
      identifiedRisks: [],
      protectiveMeasures: [],
      conditions: conditions,
    );

    // Without penalties:
    // moto: 25 min -> + 25 (PM) + 40 (rain) + 20 (road traffic) = 110 min score
    // car: 30 min -> + 20 (road traffic) = 50 min score
    // transit: 35 min -> sheltered & rail, no outdoor/road traffic penalties = 35 min score
    // Transit should be preferred!
    final ranked = CommuteRecommendations.rank([car, moto, transit]);
    final recommended = ranked.firstWhere((r) => r.isRecommended);
    expect(recommended.mode, TransportMode.publicTransit);
    // Estimated durations must remain intact (no ETA modification)
    expect(recommended.estimatedDuration, const Duration(minutes: 35));

    final evaluatedMoto = ranked.firstWhere((r) => r.mode == TransportMode.motorcycle);
    expect(evaluatedMoto.protectiveMeasures, contains('Wear an approved helmet and protective riding clothing.'));
    expect(evaluatedMoto.protectiveMeasures, contains('Bring waterproof riding gear.'));
    expect(evaluatedMoto.protectiveMeasures, contains('Consider a well-fitting particulate respirator for outdoor exposure.'));
    expect(evaluatedMoto.protectiveMeasures, contains('Bring water and sun protection.'));
    expect(evaluatedMoto.identifiedRisks, anyElement(contains('Nearest-road traffic indicates congestion')));
  });
}
