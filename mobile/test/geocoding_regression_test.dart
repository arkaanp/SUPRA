import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/services/geocoding_service.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';

class _RealHttp extends HttpOverrides {}

class _DelayedGeocoder extends GeocodingService {
  final result = Completer<List<GeocodedPlace>>();
  int requests = 0;
  @override
  Future<List<GeocodedPlace>> searchPlaces(String query, {bool remote = true}) {
    if (!remote) return Future.value([]);
    requests++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Real HTTP lookup distinguishes no match, bad coordinates and provider outage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = IOClient(_RealHttp().createHttpClient(null));
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    var calls = 0;
    server.listen((request) async {
      calls++;
      expect(request.uri.path, '/search');
      if (request.uri.queryParameters['q'] == 'outage-xyz') {
        request.response.statusCode = 429;
      } else if (request.uri.queryParameters['q'] == 'malformed-xyz') {
        request.response.write(
          '[{"name":"Invalid place","lat":"not-latitude","lon":106.8}]',
        );
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    });
    final service = GeocodingService(
      client: client,
      useNetwork: true,
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    expect(await service.searchPlaces('unknown-xyz', remote: false), isEmpty);
    expect(calls, 0); // Typing does not hit public Nominatim.
    expect(await service.searchPlaces('unknown-xyz'), isEmpty);
    expect(await service.searchPlaces('malformed-xyz'), isEmpty);
    await expectLater(service.searchPlaces('outage-xyz'), throwsStateError);
    expect(calls, 3);
  });
  testWidgets(
    'Editing invalidates the old pin and ignores late remote results',
    (tester) async {
      final geocoder = _DelayedGeocoder();
      await tester.pumpWidget(
        MaterialApp(home: TripScreen(geocodingService: geocoder)),
      );
      await tester.tap(find.byTooltip('Select on map').last);
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Search destination') ?? false),
      );
      await tester.enterText(search, 'old query');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(geocoder.requests, 1);
      await tester.enterText(search, 'new query');
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Confirm location'),
            )
            .onPressed,
        isNull,
      );
      geocoder.result.complete(const [
        GeocodedPlace(
          name: 'Outdated result',
          displayName: 'Old place',
          point: LatLng(latitude: -6.2, longitude: 106.8),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Outdated result'), findsNothing);
      expect(tester.widget<TextField>(search).controller!.text, 'new query');
    },
  );
}
