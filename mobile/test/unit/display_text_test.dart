import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/services/backend_api.dart';
import 'package:supra_mobile_ui/utils/display_text.dart';

void main() {
  test('WIB display converts the day and uses Indonesian month names', () {
    expect(
      formatWib(DateTime.parse('2026-12-31T18:05:00Z')),
      '1 Jan 2027, 01.05 WIB',
    );
    expect(
      formatWib(DateTime.parse('2026-08-04T12:05:00+07:00')),
      '4 Agu 2026, 12.05 WIB',
    );
  });

  test(
    'Indonesian display labels preserve API status, kind and error code',
    () {
      const signal = ConditionSignal(
        status: 'stale',
        source: 'openaq',
        message: '',
        kind: 'station_observation',
      );
      expect(signal.sourceDetails, contains('Data lama · Pengamatan stasiun'));
      expect(signal.toJson()['status'], 'stale');
      expect(signal.toJson()['kind'], 'station_observation');
      const error = ApiException(401, 'Invalid username or password');
      expect(error.status, 401);
      expect(error.message, 'Username atau password salah.');
      expect(travelModeLabel('public_transit'), 'Transportasi umum');
      expect(placeKindLabel('home'), 'Rumah');
    },
  );

  test('Older app alerts display Indonesian without changing stored text', () {
    final alert = AppNotification(
      id: 'a',
      userId: 'u',
      title: 'Rain near your trip',
      messageBody: 'Publisher report near Depok (area-level relevance). Check the article for current status.\nSource: https://example.com/news',
      severity: NotificationSeverity.moderate,
      sentAt: DateTime.now(),
      sourceUrl: 'https://example.com/news',
    );
    expect(alert.displayTitle, 'Hujan di dekat perjalanan Anda');
    expect(alert.displayBody, startsWith('Berita di sekitar Depok'));
    expect(alert.displayBody, isNot(contains('https://example.com/news')));
    expect(alert.title, 'Rain near your trip');
  });
}
