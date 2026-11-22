import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart' hide Route;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../config/app_config.dart';
import '../models/notification.dart';
import '../models/notification_preference.dart';
import '../models/trip.dart';
import '../models/location.dart';
import '../models/saved_trip.dart';
import 'ai_assistant_service.dart';
import '../models/user.dart';
import '../models/current_conditions.dart';
import '../models/commute.dart';
import 'authenticated_client.dart';
import 'backend_api.dart';

/// Supabase owns sessions; Axum owns profiles, trips, inbox and preferences.
/// No generated forecasts, routes or notifications are mixed with server data.
class SupraService extends ChangeNotifier {
  static final SupraService instance = SupraService();
  SupraService({
    this._apiBaseUrl = AppConfig.apiBaseUrl,
    this._httpClientFactory,
  });
  final String _apiBaseUrl;
  final http.Client Function()? _httpClientFactory;
  supabase.SupabaseClient? _supabase;
  StreamSubscription<supabase.AuthState>? _authSubscription;
  User? _currentUser;
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  final List<Trip> _trips = [];
  List<Trip> get trips => List.unmodifiable(_trips);
  final Set<String> _finishedTripIds = {};
  List<Trip> get activeTrips => _trips
      .where(
        (t) =>
            t.activeUntil?.isAfter(DateTime.now()) == true &&
            !_finishedTripIds.contains(t.id),
      )
      .toList();
  final List<AppNotification> _notifications = [];
  List<AppNotification> get notifications =>
      List.unmodifiable(_notifications.where(_preferences.allowsNotification));
  NotificationPreference _preferences = const NotificationPreference();
  NotificationPreference get preferences => _preferences;
  bool _ready = false;
  bool get backendReady => _ready;

  void initializeAuth(supabase.SupabaseClient client) {
    _authSubscription?.cancel();
    _supabase = client;
    _applySession(client.auth.currentSession);
    _authSubscription = client.auth.onAuthStateChange.listen(
      (event) => _applySession(event.session),
      onError: (Object error, StackTrace trace) {
        if (client.auth.currentSession == null) {
          _applySession(null);
        }
      },
    );
  }

  supabase.GoTrueClient get _auth {
    final client = _supabase;
    if (client == null) throw StateError('Supabase belum diinisialisasi.');
    return client.auth;
  }

  void _applySession(supabase.Session? session) {
    final previous = _currentUser?.id;
    final user = session?.user;
    _currentUser = user == null
        ? null
        : User(
            id: user.id,
            username:
                (previous == user.id ? _currentUser?.username : null) ??
                user.userMetadata?['username'] as String? ??
                '',
            avatarUrl:
                (previous == user.id ? _currentUser?.avatarUrl : null) ??
                user.userMetadata?['avatar_url'] as String?,
            createdAt: DateTime.parse(user.createdAt),
          );
    if (previous != _currentUser?.id) {
      TripHistoryStore.instance.bindUser(_currentUser?.id);
      AiAssistantService.instance.bindUser(_currentUser?.id);
      _trips.clear();
      _finishedTripIds.clear();
      _notifications.clear();
      _preferences = const NotificationPreference();
      _ready = false;
    }
    notifyListeners();
  }

  void _requireSameUser(String id) {
    if (_currentUser?.id != id) {
      throw StateError('Akun yang login berubah. Coba lagi.');
    }
  }

  Future<T> _withApi<T>(
    Future<T> Function(BackendApi api, String id) action,
  ) async {
    final id = _currentUser?.id;
    if (id == null) throw StateError('Login terlebih dahulu.');
    final client = AuthenticatedClient(
      baseUrl: Uri.parse(_apiBaseUrl),
      inner: _httpClientFactory?.call(),
      accessToken: () async {
        var session = _auth.currentSession;
        if (session == null) throw StateError('Login terlebih dahulu.');
        if (session.isExpired) session = (await _auth.refreshSession()).session;
        _requireSameUser(id);
        if (session == null || session.isExpired) {
          throw StateError('Login kembali.');
        }
        return session.accessToken;
      },
    );
    try {
      return await action(BackendApi(client: client, baseUrl: _apiBaseUrl), id);
    } finally {
      client.close();
    }
  }

  Future<void> loadAccount() => _withApi((api, id) async {
    final profile = await api.request('POST', '/api/users', {});
    _requireSameUser(id);
    _currentUser = User.fromJson(profile as Map<String, dynamic>);
    notifyListeners();
    final trips = (await api.request('GET', '/api/trips') as List)
        .map((v) => Trip.fromJson(v as Map<String, dynamic>))
        .toList();
    try {
      await api.request('POST', '/api/alerts/evaluate');
    } catch (_) {}
    final alerts =
        (await api.request('GET', '/api/users/$id/notifications?limit=100')
                as List)
            .map((v) => AppNotification.fromJson(v as Map<String, dynamic>))
            .toList();
    // PUT {} creates defaults if absent and preserves existing preferences.
    final prefs = NotificationPreference.fromJson(
      await api.request('PUT', '/api/users/$id/preferences', {})
          as Map<String, dynamic>,
    );
    _requireSameUser(id);
    _trips
      ..clear()
      ..addAll(trips);
    TripHistoryStore.instance.syncWithServiceTrips(_trips);
    _notifications
      ..clear()
      ..addAll(alerts);
    _preferences = prefs;
    _ready = true;
    notifyListeners();
  });

  Future<User> updateProfile(String username) => _withApi((api, id) async {
    final trimmed = username.trim();
    if (!User.isValidUsername(trimmed)) throw StateError(User.usernameHint);
    final User updated;
    try {
      updated = User.fromJson(
        await api.request('PUT', '/api/profile', {'username': trimmed})
            as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      if (error.status == 409) throw StateError('Username sudah digunakan.');
      rethrow;
    }
    _requireSameUser(id);
    _currentUser = updated;
    notifyListeners();
    try {
      await _auth.updateUser(
        supabase.UserAttributes(data: {'username': updated.username}),
      );
    } catch (_) {
      // Best-effort sync with Supabase Auth metadata; DB is source of truth.
    }
    return updated;
  });

  Future<User> uploadAvatar(List<int> bytes, String fileName) => _withApi((
    api,
    id,
  ) async {
    final updated = User.fromJson(
      await api.uploadBytes('/api/profile/avatar', bytes, fileName: fileName)
          as Map<String, dynamic>,
    );
    _requireSameUser(id);
    _currentUser = updated;
    notifyListeners();
    try {
      if (updated.avatarUrl != null) {
        await _auth.updateUser(
          supabase.UserAttributes(data: {'avatar_url': updated.avatarUrl}),
        );
      }
    } catch (_) {
      // Best-effort sync with Supabase Auth metadata; DB is source of truth.
    }
    return updated;
  });

  Future<void> deleteAccount() async {
    await _withApi((api, id) async {
      await api.request('DELETE', '/api/account');
    });
    await logout();
  }

  Future<CurrentConditions> getCurrentConditions(
    double latitude,
    double longitude, [
    String? adm4,
  ]) => _withApi((api, id) async {
    final query = Uri(
      queryParameters: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        if (adm4 != null && adm4.trim().isNotEmpty) 'adm4': adm4.trim(),
      },
    ).query;
    final result = CurrentConditions.fromJson(
      await api.request('GET', '/api/conditions/current?$query')
          as Map<String, dynamic>,
    );
    _requireSameUser(id);
    return result;
  });

  Future<dynamic> _sendCredentials(
    String endpoint,
    String username,
    String password,
  ) async {
    if (kReleaseMode && Uri.parse(_apiBaseUrl).scheme != 'https') {
      throw StateError('Akses akun memerlukan alamat API HTTPS.');
    }
    final client = _httpClientFactory?.call() ?? http.Client();
    try {
      return await BackendApi(
        client: client,
        baseUrl: _apiBaseUrl,
      ).request('POST', endpoint, {'username': username, 'password': password});
    } finally {
      client.close();
    }
  }

  Future<User> login(String username, String password) async {
    final value = username.trim();
    if (value.isEmpty || value.contains('@') || password.isEmpty) {
      throw StateError('Masukkan username dan password.');
    }
    final session = await _sendCredentials(
      '/api/auth/username-login',
      value,
      password,
    );
    final result = await _auth.recoverSession(jsonEncode(session));
    if (result.session == null) {
      throw StateError('Login gagal membuat sesi.');
    }
    _applySession(result.session);
    return _currentUser!;
  }

  Future<void> register(String username, String password) async {
    if (!User.isValidUsername(username)) throw StateError(User.usernameHint);
    _validatePassword(password);
    try {
      await _sendCredentials(
        '/api/auth/register',
        username.trim().toLowerCase(),
        password,
      );
    } on ApiException catch (error) {
      if (error.status == 409) throw StateError('Username sudah digunakan.');
      rethrow;
    }
  }

  void _validatePassword(String password) {
    if (password.runes.length < 8 || utf8.encode(password).length > 72) {
      throw StateError(
        'Gunakan password minimal 8 karakter dan maksimal 72 byte.',
      );
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _validatePassword(newPassword);
    final user = _currentUser;
    if (user == null) throw StateError('Login terlebih dahulu.');
    final session = await _sendCredentials(
      '/api/auth/username-login',
      user.username,
      currentPassword,
    ) as Map<String, dynamic>;
    _requireSameUser(user.id);
    if ((session['user'] as Map?)?['id'] != user.id) {
      throw StateError('Login dengan username saat ini, lalu coba lagi.');
    }
    await _auth.recoverSession(jsonEncode(session));
    _requireSameUser(user.id);
    await _auth.updateUser(supabase.UserAttributes(password: newPassword));
  }

  Future<void> logout() async {
    await _auth.signOut();
    _applySession(null);
  }

  Future<Trip> createTrip({
    required String start,
    required String destination,
    required DateTime departure,
    required LatLng startPoint,
    required LatLng destPoint,
    String mode = 'car',
    List<LatLng> routeWaypoints = const [],
  }) => _withApi((api, id) async {
    final trip = Trip.fromJson(
      await api.request('POST', '/api/trips', {
        'name': '$start → $destination',
        'start_location': start,
        'destination': destination,
        'planned_departure': departure.toUtc().toIso8601String(),
        'start_latitude': startPoint.latitude,
        'start_longitude': startPoint.longitude,
        'destination_latitude': destPoint.latitude,
        'destination_longitude': destPoint.longitude,
        'confirmed': true,
        'transport_mode': mode,
        if (routeWaypoints.isNotEmpty)
          'route_waypoints': [
            for (var i = 0; i < routeWaypoints.length; i++)
              if (i == 0 ||
                  i == routeWaypoints.length - 1 ||
                  i %
                          ((routeWaypoints.length / 998).ceil().clamp(
                            1,
                            routeWaypoints.length,
                          )) ==
                      0)
                {
                  'lat': routeWaypoints[i].latitude,
                  'lng': routeWaypoints[i].longitude,
                },
          ],
      }) as Map<String, dynamic>,
    );
    _requireSameUser(id);
    _trips.insert(0, trip);
    TripHistoryStore.instance.syncWithServiceTrips(_trips);
    notifyListeners();
    return trip;
  });

  Future<void> deleteTrip(String tripId) => _withApi((api, id) async {
    await api.request('DELETE', '/api/trips/$tripId');
    _requireSameUser(id);
    _trips.removeWhere((trip) => trip.id == tripId);
    TripHistoryStore.instance.syncWithServiceTrips(_trips);
    notifyListeners();
  });

  Future<void> finishTrip(String tripId) => _withApi((api, id) async {
    await api.request('PUT', '/api/trips/$tripId/finish');
    _requireSameUser(id);
    _finishedTripIds.add(tripId);
    notifyListeners();
  });
  Future<List<SavedPlace>> getSavedPlaces() => _withApi((api, id) async {
    final values = await api.request('GET', '/api/places') as List;
    _requireSameUser(id);
    return values
        .map((v) => SavedPlace.fromJson(v as Map<String, dynamic>))
        .toList();
  });
  Future<void> savePlace({
    String? placeId,
    required String label,
    required String kind,
    required LatLng point,
  }) => _withApi((api, id) async {
    await api.request(
      placeId == null ? 'POST' : 'PUT',
      placeId == null ? '/api/places' : '/api/places/$placeId',
      {
        'label': label.trim(),
        'kind': kind,
        'latitude': point.latitude,
        'longitude': point.longitude,
      },
    );
    _requireSameUser(id);
  });
  Future<void> deletePlace(String placeId) => _withApi((api, id) async {
    await api.request('DELETE', '/api/places/$placeId');
    _requireSameUser(id);
  });
  Future<List<RoutineTrip>> getRoutines() => _withApi((api, id) async {
    final values = await api.request('GET', '/api/routines') as List;
    _requireSameUser(id);
    return values
        .map((v) => RoutineTrip.fromJson(v as Map<String, dynamic>))
        .toList();
  });
  Future<void> saveRoutine(Map<String, dynamic> payload, {String? routineId}) =>
      _withApi((api, id) async {
        await api.request(
          routineId == null ? 'POST' : 'PUT',
          routineId == null ? '/api/routines' : '/api/routines/$routineId',
          payload,
        );
        _requireSameUser(id);
      });
  Future<void> deleteRoutine(String routineId) => _withApi((api, id) async {
    await api.request('DELETE', '/api/routines/$routineId');
    _requireSameUser(id);
  });
  Future<Map<String, dynamic>> planMobility(
    LatLng start,
    LatLng destination,
    String mode,
  ) => _withApi((api, id) async {
    final result = await api.request('POST', '/api/mobility/plan', {
      'mode': mode,
      'origin': {'latitude': start.latitude, 'longitude': start.longitude},
      'destination': {
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
    }) as Map<String, dynamic>;
    _requireSameUser(id);
    return result;
  });
  Future<Map<String, dynamic>> hourlyForecast(LatLng point) => _withApi((
    api,
    id,
  ) async {
    final result = await api.request(
      'GET',
      '/api/forecast/hourly?latitude=${point.latitude}&longitude=${point.longitude}',
    ) as Map<String, dynamic>;
    _requireSameUser(id);
    return result;
  });
  Future<Map<String, dynamic>> evaluateAlerts() => _withApi((api, id) async {
    final result = await api.request(
      'POST',
      '/api/alerts/evaluate',
    ) as Map<String, dynamic>;
    _requireSameUser(id);
    return result;
  });

  Future<List<AppNotification>> getNotifications({
    String? newsMinSeverity,
  }) => _withApi((api, id) async {
    final values = await api.request(
      'GET',
      '/api/users/$id/notifications?limit=100${newsMinSeverity == null ? '' : '&news_min_severity=${Uri.encodeQueryComponent(newsMinSeverity)}'}',
    ) as List;
    final alerts = values
        .map((v) => AppNotification.fromJson(v as Map<String, dynamic>))
        .toList();
    _requireSameUser(id);
    _notifications
      ..clear()
      ..addAll(alerts);
    notifyListeners();
    return notifications;
  });

  Future<void> markNotificationRead(String notificationId) =>
      _withApi((api, id) async {
        final alert = AppNotification.fromJson(
          await api.request('PUT', '/api/notifications/$notificationId/read')
              as Map<String, dynamic>,
        );
        _requireSameUser(id);
        final index = _notifications.indexWhere((n) => n.id == notificationId);
        if (index >= 0) _notifications[index] = alert;
        notifyListeners();
      });

  Future<void> markNotificationUnread(String notificationId) =>
      _withApi((api, id) async {
        final alert = AppNotification.fromJson(
          await api.request('PUT', '/api/notifications/$notificationId/unread')
              as Map<String, dynamic>,
        );
        _requireSameUser(id);
        final index = _notifications.indexWhere((n) => n.id == notificationId);
        if (index >= 0) _notifications[index] = alert;
        notifyListeners();
      });

  Future<int> markNotificationsUnread(List<String> ids) =>
      _withApi((api, id) async {
        final result = await api.request('PUT', '/api/notifications/unread', {
          'ids': ids,
        }) as Map<String, dynamic>;
        _requireSameUser(id);
        final selected = ids.toSet();
        for (var i = 0; i < _notifications.length; i++) {
          if (selected.contains(_notifications[i].id)) {
            _notifications[i] = _notifications[i].copyWith(isRead: false);
          }
        }
        notifyListeners();
        return result['updated'] as int;
      });

  Future<int> markAllRead() => _withApi((api, id) async {
    final result = await api.request(
      'PUT',
      '/api/notifications/read',
    ) as Map<String, dynamic>;
    _requireSameUser(id);
    for (var i = 0; i < _notifications.length; i++) {
      if (_preferences.allowsNotification(_notifications[i])) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
    return result['updated'] as int;
  });

  Future<int> deleteReadNotifications() => _withApi((api, id) async {
    final result = await api.request(
      'DELETE',
      '/api/notifications/read',
    ) as Map<String, dynamic>;
    _requireSameUser(id);
    final deleted = result['deleted'] as int;
    _notifications.removeWhere((n) => n.isRead);
    notifyListeners();
    return deleted;
  });

  Future<void> updatePreferences(NotificationPreference preferences) =>
      _withApi((api, id) async {
        final saved = NotificationPreference.fromJson(
          await api.request(
            'PUT',
            '/api/users/$id/preferences',
            preferences.toJson(),
          ) as Map<String, dynamic>,
        );
        _requireSameUser(id);
        _preferences = saved;
        notifyListeners();
      });

  Future<NotificationPreference> updateNewsSeverity(String severity) =>
      _withApi((api, id) async {
        final saved = NotificationPreference.fromJson(
          await api.request('PUT', '/api/users/$id/preferences', {
            'news_min_severity': severity,
          }) as Map<String, dynamic>,
        );
        _requireSameUser(id);
        _preferences = saved;
        notifyListeners();
        return saved;
      });

  /// Sends a conversational message to Agent 1 via backend POST /api/agent/chat.
  Future<Map<String, dynamic>> sendAgentChat({
    required String message,
    List<Map<String, dynamic>>? history,
    Map<String, dynamic>? context,
  }) => _withApi((api, id) async {
    final payload = <String, dynamic>{
      'message': message,
      if (history != null && history.isNotEmpty) 'history': history,
      if (context != null && context.isNotEmpty) 'context': context,
    };
    final response = await api.request(
      'POST',
      '/api/agent/chat',
      payload,
    ) as Map<String, dynamic>;
    _requireSameUser(id);
    return response;
  });

  @visibleForTesting
  void setTripsForTesting(List<Trip> trips) {
    _trips
      ..clear()
      ..addAll(trips);
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
