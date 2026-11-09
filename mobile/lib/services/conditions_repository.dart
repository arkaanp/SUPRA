import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/map_config.dart';
import '../models/current_conditions.dart';
import '../models/location.dart';
import 'supra_api_service.dart';

/// Account/location-scoped last-known readings. Outages mark cached values stale,
/// never replace them with baselines or advance their observation/fetch times.
class ConditionsRepository {
  static final instance = ConditionsRepository();
  ConditionsRepository({
    this.load,
    DateTime Function()? now,
    String? Function()? userId,
    this.ttl = const Duration(minutes: 2),
  }) : _now = now ?? DateTime.now,
       _userId = userId ?? (() => SupraService.instance.currentUser?.id);
  final Future<CurrentConditions> Function(LatLng)? load;
  final DateTime Function() _now;
  final String? Function() _userId;
  final Duration ttl;
  final _cache = <String, (DateTime, CurrentConditions)>{};
  final _pending = <String, Future<CurrentConditions>>{};
  final _restoring = <String, Future<void>>{};
  String? _latestScope;
  CurrentConditions? _latest;

  /// Most recent resolved snapshot for the signed-in account. Chat uses it as
  /// untrusted context; stale values stay labelled rather than becoming live.
  CurrentConditions? get latest {
    final user = _userId();
    if (user == null || user != _latestScope) return null;
    return _latest?.agedAt(_now());
  }

  Future<CurrentConditions> at(
    LatLng point, {
    String? adm4,
    bool refresh = false,
  }) async {
    final user = _userId();
    final scope = user ?? 'signed-out';
    if (user != null) {
      await _restoring.putIfAbsent(scope, () => _restore(scope));
    }
    final key = '$scope:${point.latitude},${point.longitude}:${adm4 ?? ""}';
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        _now().difference(cached.$1) >= Duration.zero &&
        _now().difference(cached.$1) < ttl) {
      final result = cached.$2.agedAt(_now());
      _latest = result;
      _latestScope = user;
      return result;
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final request = () async {
      final fetched = await _fetch(point, adm4);
      final result = fetched.retaining(cached?.$2).agedAt(_now());
      if (_cache.length >= 32 && !_cache.containsKey(key)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = (_now(), result);
      _latest = result;
      _latestScope = user;
      if (user != null) await _persist(scope);
      return result;
    }();
    _pending[key] = request;
    try {
      return await request;
    } finally {
      _pending.remove(key);
    }
  }

  Future<void> _restore(String scope) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(
        'supra_conditions_v1:$scope',
      );
      if (raw == null) return;
      final values = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in values.entries.take(32)) {
        if (!entry.key.startsWith('$scope:')) continue;
        final result = CurrentConditions.fromJson(
          entry.value as Map<String, dynamic>,
        );
        // Restored readings require revalidation; failed revalidation retains them as stale.
        if (_cache.length >= 32 && !_cache.containsKey(entry.key)) {
          _cache.remove(_cache.keys.first);
        }
        _cache[entry.key] = (DateTime.fromMillisecondsSinceEpoch(0), result);
      }
    } catch (_) {
      /* A corrupt/unavailable cache is not a reading. */
    }
  }

  Future<void> _persist(String scope) async {
    try {
      final values = {
        for (final e in _cache.entries)
          if (e.key.startsWith('$scope:') &&
              [
                e.value.$2.weather,
                e.value.$2.airQuality,
                e.value.$2.traffic,
              ].any((s) => s.hasData))
            e.key: e.value.$2.toJson(),
      };
      await (await SharedPreferences.getInstance()).setString(
        'supra_conditions_v1:$scope',
        jsonEncode(values),
      );
    } catch (_) {
      /* Keep in-memory readings if persistence is unavailable. */
    }
  }

  Future<CurrentConditions> _fetch(LatLng point, String? adm4) async {
    try {
      if (load != null) return await load!(point);
      if (!MapConfig.isTestEnvironment) {
        return await SupraService.instance.getCurrentConditions(
          point.latitude,
          point.longitude,
          adm4,
        );
      }
    } catch (_) {
      /* Merge failures with genuine last-known values. */
    }
    return CurrentConditions(
      latitude: point.latitude,
      longitude: point.longitude,
      retrievedAt: _now(),
      weather: unavailable,
      airQuality: unavailable,
      traffic: unavailable,
    );
  }

  static const unavailable = ConditionSignal(
    status: 'unavailable',
    source: 'supra_backend',
    message:
        'No current reading available. No cached reading for this location.',
  );
}
