import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supra_mobile_ui/services/supra_api_service.dart';
import 'package:supra_mobile_ui/models/notification_preference.dart';

class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

void main() {
  test('Supabase signup awaits confirmation; login uses Auth UUID; logout clears state', () async {
    const uuid = 'a1b2c3d4-0000-4000-8000-000000000007';
    final user = {
      'id': uuid,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'rider@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {
        'provider': 'email',
        'providers': ['email'],
      },
      'user_metadata': {'full_name': 'Test Rider'},
    };
    final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'ES256', 'typ': 'JWT'})}.${part({'sub': uuid, 'exp': expiresAt})}.test-signature';
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-publishable-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/signup')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['data']['full_name'], 'Test Rider');
          return http.Response(jsonEncode(user), 200);
        }
        if (request.url.path.endsWith('/token')) {
          expect(request.url.queryParameters['grant_type'], 'password');
          return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'refresh-token',
              'token_type': 'bearer',
              'expires_in': 3600,
              'expires_at': expiresAt,
              'user': user,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/logout')) {
          expect(request.headers['Authorization'], 'Bearer $token');
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(client.dispose);
    var persisted = false;
    var read = false;
    var prefs = const NotificationPreference();
    final service = SupraService(
      apiBaseUrl: 'http://localhost:3000',
      httpClientFactory: () => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer $token');
        final path = request.url.path;
        if (path == '/api/users') {
          expect(jsonDecode(request.body), {'full_name': 'Test Rider'});
          return http.Response('{}', 200);
        }
        if (path == '/api/trips') {
          if (request.method == 'POST') {
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            expect(data.containsKey('user_id'), false);
            expect(data['planned_departure'], '2030-01-01T12:00:00.000Z');
            persisted = true;
          }
          final trip = {
            'id': 'trip-id',
            'user_id': uuid,
            'name': 'A → B',
            'start_location': 'A',
            'destination': 'B',
            'planned_departure': '2030-01-01T12:00:00Z',
          };
          return http.Response(
            jsonEncode(
              request.method == 'POST' ? trip : (persisted ? [trip] : []),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path == '/api/users/$uuid/preferences') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          if (data.isNotEmpty) prefs = NotificationPreference.fromJson(data);
          return http.Response(jsonEncode(prefs.toJson()), 200);
        }
        if (path == '/api/users/$uuid/notifications' ||
            path == '/api/notifications/alert-id/read') {
          if (request.method == 'PUT') read = true;
          final alert = {
            'id': 'alert-id',
            'user_id': uuid,
            'title': 'Existing alert',
            'message_body': 'From backend',
            'severity': 'medium',
            'sent_at': '2030-01-01T12:00:00Z',
            'is_read': read,
          };
          return http.Response(
            jsonEncode(request.method == 'PUT' ? alert : [alert]),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(service.dispose);
    service.initializeAuth(client);
    await service.register('Test Rider', 'rider@example.com', 'password123');
    expect(service.isLoggedIn, isFalse);

    final profile = await service.login('rider@example.com', 'password123');
    expect(profile.id, uuid);
    expect(profile.fullName, 'Test Rider');
    expect(service.isLoggedIn, isTrue);
    expect(client.auth.currentSession!.accessToken, token);
    expect(service.trips, isEmpty);

    await service.loadAccount();
    expect(service.backendReady, true);
    expect(service.notifications.single.isRead, false);
    await service.createTrip(
      start: 'A',
      destination: 'B',
      departure: DateTime.utc(2030, 1, 1, 12),
    );
    expect(service.trips.single.userId, uuid);
    await service.updatePreferences(
      const NotificationPreference(alertHeavyRain: false),
    );
    expect(service.preferences.alertHeavyRain, false);
    await service.markNotificationRead('alert-id');
    expect(service.notifications.single.isRead, true);
    await service.loadAccount();
    expect(service.trips.single.name, 'A → B');
    expect(service.preferences.alertHeavyRain, false);

    await service.logout();
    expect(service.isLoggedIn, isFalse);
    expect(service.trips, isEmpty);
    expect(service.notifications, isEmpty);
    expect(service.backendReady, isFalse);
  });
}
