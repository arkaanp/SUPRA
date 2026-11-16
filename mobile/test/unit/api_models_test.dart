import 'package:flutter_test/flutter_test.dart';
import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/models/trip.dart';

void main() {
  test('Axum snake_case payloads and all severity values decode', () {
    final trip = Trip.fromJson({
      'id': 'trip',
      'user_id': 'user',
      'name': 'Commute',
      'start_location': 'A',
      'destination': 'B',
      'planned_departure': '2030-01-01T12:00:00Z',
    });
    expect(trip.startLocation, 'A');
    expect(trip.routes, isEmpty);
    for (final (wire, severity) in [
      ('low', NotificationSeverity.low),
      ('medium', NotificationSeverity.moderate),
      ('high', NotificationSeverity.high),
      ('critical', NotificationSeverity.critical),
    ]) {
      final alert = AppNotification.fromJson({
        'id': 'alert',
        'user_id': 'user',
        'title': 'Title',
        'message_body': 'Body',
        'severity': wire,
        'sent_at': '2030-01-01T12:00:00Z',
        'is_read': true,
      });
      expect(alert.severity, severity);
      expect(alert.isRead, true);
    }
    final flags = {
      'alert_unhealthy_aqi': true,
      'alert_heavy_rain': false,
      'alert_severe_traffic': true,
      'alert_relevant_news': true,
      'news_min_severity': 'low',
    };
    expect(NotificationPreference.fromJson(flags).toJson(), flags);
  });
}
