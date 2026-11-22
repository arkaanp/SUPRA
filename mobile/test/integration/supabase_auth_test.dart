import 'dart:convert';

import 'package:supra_mobile_ui/models/location.dart';

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
  test('Username registration and sign-in retain the Auth UUID and account state', () async {
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
      'user_metadata': {'username': 'test_rider'},
    };
    final expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'ES256', 'typ': 'JWT'})}.${part({'sub': uuid, 'exp': expiresAt})}.test-signature';
    var password = 'password123';
    final client = SupabaseClient(
      'https://test.supabase.co',
      'test-publishable-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/user') && request.method == 'PUT') {
          expect(request.headers['Authorization'], 'Bearer $token');
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          if (data['password'] is String) password = data['password'] as String;
          return http.Response(jsonEncode(user), 200);
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
    var registered = false;
    var username = 'test_rider';
    var read = false;
    var deletedAlert = false;
    var prefs = const NotificationPreference();
    final service = SupraService(
      apiBaseUrl: 'http://localhost:3000',
      httpClientFactory: () => MockClient((request) async {
        if (request.url.path == '/api/auth/register') {
          expect(jsonDecode(request.body), {
            'username': 'test_rider',
            'password': 'password123',
          });
          registered = true;
          return http.Response('{"username":"test_rider"}', 201);
        }
        if (request.url.path == '/api/auth/username-login') {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          if (!registered ||
              (data['username'] as String).toLowerCase() != username ||
              data['password'] != password) {
            return http.Response(
              '{"error":"Invalid username or password"}',
              401,
            );
          }
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
        expect(request.headers['Authorization'], 'Bearer $token');
        final path = request.url.path;
        if (path == '/api/users') {
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'id': uuid,
              'username': username,
              'created_at': user['created_at'],
            }),
            200,
          );
        }
        if (path == '/api/profile' && request.method == 'PUT') {
          username = (jsonDecode(request.body)['username'] as String)
              .toLowerCase();
          return http.Response(
            jsonEncode({
              'id': uuid,
              'username': username,
              'created_at': user['created_at'],
            }),
            200,
          );
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
        if (path == '/api/notifications/read') {
          if (request.method == 'DELETE') {
            final count = read && !deletedAlert ? 1 : 0;
            if (read) deletedAlert = true;
            return http.Response(jsonEncode({'deleted': count}), 200);
          }
          expect(request.method, 'PUT');
          final count = read ? 0 : 1;
          read = true;
          return http.Response(jsonEncode({'updated': count}), 200);
        }
        if (path == '/api/notifications/unread') {
          expect(request.method, 'PUT');
          expect(jsonDecode(request.body), {
            'ids': ['alert-id'],
          });
          final count = read ? 1 : 0;
          read = false;
          return http.Response(jsonEncode({'updated': count}), 200);
        }
        if (path == '/api/users/$uuid/notifications' ||
            path == '/api/notifications/alert-id/read' ||
            path == '/api/notifications/alert-id/unread') {
          if (request.method == 'PUT') read = path.endsWith('/read');
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
            jsonEncode(
              request.method == 'PUT' ? alert : (deletedAlert ? [] : [alert]),
            ),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(service.dispose);
    service.initializeAuth(client);
    await service.register(' Test_Rider ', 'password123');
    expect(registered, isTrue);
    expect(service.isLoggedIn, isFalse);

    await expectLater(
      service.login('rider@example.com', 'password123'),
      throwsStateError,
    );
    final profile = await service.login('test_rider', 'password123');
    expect(profile.id, uuid);
    expect(profile.username, 'test_rider');
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
      startPoint: const LatLng(latitude: -6.2, longitude: 106.8),
      destPoint: const LatLng(latitude: -6.3, longitude: 106.9),
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
    await service.markNotificationUnread('alert-id');
    expect(service.notifications.single.isRead, false);
    expect(await service.markAllRead(), 1);
    expect(service.notifications.single.isRead, true);
    expect(await service.markNotificationsUnread(['alert-id']), 1);
    expect(service.notifications.single.isRead, false);
    await service.markAllRead();
    final snapshot = await service.getNotifications();
    expect(() => snapshot.removeWhere((n) => n.isRead), throwsUnsupportedError);
    expect(await service.deleteReadNotifications(), 1);
    expect(service.notifications, isEmpty);
    expect(await service.getNotifications(), isEmpty);

    await service.updateProfile('renamed_rider');
    await expectLater(
      service.changePassword('wrong123', 'newpassword123'),
      throwsException,
    );
    await service.changePassword('password123', 'newpassword123');
    await service.logout();
    expect(service.isLoggedIn, isFalse);
    expect(service.trips, isEmpty);
    expect(service.notifications, isEmpty);
    expect(service.backendReady, isFalse);
    await expectLater(
      service.login('test_rider', 'newpassword123'),
      throwsException,
    );
    await expectLater(
      service.login('renamed_rider', 'password123'),
      throwsException,
    );
    await service.login(' Renamed_Rider ', 'newpassword123');
    expect(client.auth.currentSession?.user.id, uuid);
    await service.loadAccount();
    expect(service.currentUser?.username, 'renamed_rider');
  });
}
