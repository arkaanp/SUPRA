import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/services/geocoding_service.dart';
import 'package:supra_mobile_ui/screens/trip_screen.dart';

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
  testWidgets(
    'Editing invalidates the old pin and ignores late remote results',
    (tester) async {
      final geocoder = _DelayedGeocoder();
      await tester.pumpWidget(
        MaterialApp(home: TripScreen(geocodingService: geocoder)),
      );
      await tester.tap(find.byTooltip('Pilih di peta').last);
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText?.contains('Cari tujuan') ?? false),
      );
      await tester.enterText(search, 'old query');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(geocoder.requests, 1);
      await tester.enterText(search, 'new query');
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Konfirmasi lokasi'),
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
