import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/transit_journey.dart';
import 'package:supra_mobile_ui/widgets/transit_journey_details.dart';

import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/route_option.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';
import 'package:supra_mobile_ui/services/routing_service.dart';
import 'package:supra_mobile_ui/widgets/route_planner_view.dart';

Map<String, dynamic> payload() => {
  'source': 'commute_shiorilabs',
  'fare_idr': 4000,
  'attribution': 'Commute Data / Shiori Labs · ODbL-1.0',
  'legs': [
    {
      'mode': 'WALK',
      'line': '',
      'from': 'Start',
      'to': 'Gondangdia',
      'departure_at': '2026-11-16T01:00:00Z',
      'arrival_at': '2026-11-16T01:03:00Z',
      'distance_km': 0.2,
      'geometry_kind': 'schematic_walk_link',
      'estimated': true,
    },
    {
      'mode': 'KCI',
      'line': 'KCI:B',
      'from': 'Gondangdia',
      'to': 'Depok',
      'departure_at': '2026-11-16T01:08:00Z',
      'arrival_at': '2026-11-16T01:53:00Z',
      'distance_km': 25.9,
      'geometry_kind': 'schematic_station_sequence',
      'estimated': false,
    },
  ],
};
const start = LatLng(latitude: -6.1754, longitude: 106.8272);
const destination = LatLng(latitude: -6.365, longitude: 106.828);
Map<String, dynamic> routePayload(String mode) {
  final journey = payload();
  final ride = (journey['legs'] as List).last as Map<String, dynamic>;
  ride['mode'] = mode;
  ride['line'] = mode == 'BUS' ? 'Transjakarta 1' : 'KCI:B';
  return {
    'mode': 'public_transit',
    'source': journey['source'],
    'fetched_at': '2026-11-16T01:00:00Z',
    'duration_seconds': mode == 'BUS' ? 5400 : 3600,
    'distance_km': mode == 'BUS' ? 30 : 24,
    'waypoints': [
      [start.latitude, start.longitude],
      [mode == 'BUS' ? -6.25 : -6.26, 106.82],
      [destination.latitude, destination.longitude],
    ],
    'steps': ['Board provider service'],
    'transit': journey,
  };
}

RoutingService serviceFor(
  Map<String, dynamic> response, {
  void Function()? onCondition,
}) => RoutingService(
  useNetwork: true,
  planMobility: (_, _, _) async => response,
  conditions: ConditionsRepository(
    load: (p) async {
      onCondition?.call();
      return CurrentConditions(
        latitude: p.latitude,
        longitude: p.longitude,
        retrievedAt: DateTime.now(),
        weather: ConditionsRepository.unavailable,
        airQuality: ConditionsRepository.unavailable,
        traffic: ConditionsRepository.unavailable,
      );
    },
  ),
);
Future<List<RouteOption>> optionsFor(
  Map<String, dynamic> response, {
  void Function()? onCondition,
}) => serviceFor(response, onCondition: onCondition).calculateMode(
  start: start,
  destination: destination,
  mode: TransportMode.publicTransit,
);

void main() {
  test('Backend bus and KRL alternatives keep independent metrics and geometry; legacy response works', () async {
    var calls = 0;
    final bus = routePayload('BUS')..['alternatives'] = [routePayload('KCI')];
    final options = await optionsFor(bus, onCondition: () => calls++);
    expect(options.map((o) => o.title), ['Transjakarta', 'KRL Commuter Line']);
    expect(options.map((o) => o.distanceKm), [30, 24]);
    expect(options.map((o) => o.estimatedDuration.inMinutes), [90, 60]);
    expect(options.first.waypoints[1], isNot(options.last.waypoints[1]));
    expect(calls, 1);
    expect(
      (await optionsFor(routePayload('KCI'))).single.title,
      'KRL Commuter Line',
    );
    (bus['alternatives'] as List).first['mode'] = 'walk';
    expect(optionsFor(bus), throwsFormatException);
  });

  testWidgets(
    'Two transit options select independently despite sharing the same mode',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final options = await optionsFor(
        routePayload('BUS')..['alternatives'] = [routePayload('KCI')],
      );
      var selected = options.first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => RoutePlannerView(
                  options: options,
                  selectedOption: selected,
                  onOptionSelected: (o) => setState(() => selected = o),
                ),
              ),
            ),
          ),
        ),
      );
      Color? color(RouteOption o) =>
          (tester.widget<AnimatedContainer>(find.byKey(ValueKey(o))).decoration
                  as BoxDecoration)
              .color;
      expect(color(options.first), Colors.white);
      expect(color(options.last), Colors.transparent);
      await tester.tap(find.text('KRL Commuter Line'));
      await tester.pumpAndSettle();
      expect(identical(selected, options.last), isTrue);
      expect(color(options.first), Colors.transparent);
      expect(color(options.last), Colors.white);
      expect(tester.takeException(), isNull);
    },
  );

  test('Transit schedules and fare parse; inconsistent transfers and missing rides are rejected', () {
    final p = payload();
    final journey = TransitJourney.fromJson(p);
    expect(journey.fareIdr, 4000);
    expect(TransitLeg.wib(journey.legs.last.departure), '08:08 WIB');
    (p['legs'] as List)[1]['departure_at'] = '2026-11-16T00:00:00Z';
    expect(() => TransitJourney.fromJson(p), throwsFormatException);
    p['legs'] = [(payload()['legs'] as List).first];
    expect(() => TransitJourney.fromJson(p), throwsFormatException);
  });
  testWidgets(
    'Transit card shows boarding/alighting times, source, fare and walking limitation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: SingleChildScrollView(
                child: TransitJourneyDetails(
                  journey: TransitJourney.fromJson(payload()),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('KCI:B'), findsOneWidget);
      expect(find.text('Gondangdia → Depok'), findsOneWidget);
      expect(find.textContaining('Rp 4000'), findsOneWidget);
      expect(find.textContaining('08:08 WIB → 08:53 WIB'), findsOneWidget);
      expect(
        find.text('Jalur penghubung pejalan kaki; bukan navigasi jalan'),
        findsOneWidget,
      );
      expect(find.textContaining('ODbL-1.0'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Sumber transportasi umum'));
      await tester.tap(find.byTooltip('Sumber transportasi umum'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ODbL-1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
