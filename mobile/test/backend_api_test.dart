import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supra_mobile_ui/services/authenticated_client.dart';
import 'package:supra_mobile_ui/services/backend_api.dart';
import 'package:supra_mobile_ui/models/notification.dart';
import 'package:supra_mobile_ui/models/notification_preference.dart';
import 'package:supra_mobile_ui/models/trip.dart';

void main() {
  test(
    'Authenticated profile payload matches Axum and errors retain status',
    () async {
      final client = AuthenticatedClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        accessToken: () async => 'test-token',
        inner: MockClient((req) async {
          expect(req.headers['Authorization'], 'Bearer test-token');
          expect(req.followRedirects, false);
          expect(req.url.path, '/api/users');
          expect(jsonDecode(req.body), {'full_name': 'Test Rider'});
          return http.Response(
            '{"error":"Resource already exists","code":"conflict"}',
            409,
          );
        }),
      );
      addTearDown(client.close);
      final api = BackendApi(client: client, baseUrl: 'http://localhost:3000/');
      await expectLater(
        api.request('POST', '/api/users', {'full_name': 'Test Rider'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', 'Resource already exists'),
        ),
      );
    },
  );

  test('Trip and avatar timeouts preserve uncertain save outcome without raw exceptions', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    addTearDown(client.close);
    final api = BackendApi(
      client: client,
      baseUrl: 'http://localhost:3000',
      requestTimeout: const Duration(milliseconds: 10),
      uploadTimeout: const Duration(milliseconds: 10),
    );
    final expected = isA<ApiException>()
        .having((e) => e.status, 'status', 504)
        .having((e) => e.message, 'message', contains('Refresh to check'));
    await expectLater(api.request('POST', '/api/trips', {}), throwsA(expected));
    await expectLater(
      api.uploadBytes('/api/profile/avatar', [1]),
      throwsA(expected),
    );
  });

  test('Invalid backend responses are not accepted as data', () async {
    final client = MockClient((_) async => http.Response('not JSON', 502));
    addTearDown(client.close);
    await expectLater(
      BackendApi(
        client: client,
        baseUrl: 'http://localhost:3000',
      ).request('GET', '/api/trips'),
      throwsA(isA<ApiException>()),
    );
  });

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
    };
    expect(NotificationPreference.fromJson(flags).toJson(), flags);
  });
}
