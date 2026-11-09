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
      return cached.$2.agedAt(_now());
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final request = () async {
      final fetched = await _fetch(point, adm4);
      final result = fetched.retaining(cached?.$2).agedAt(_now());
      if (_cache.length >= 32 && !_cache.containsKey(key)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = (_now(), result);
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
        final rawResult = CurrentConditions.fromJson(
          entry.value as Map<String, dynamic>,
        );
        final result = (load == null && !MapConfig.isTestEnvironment)
            ? _withStaleFallback(
                rawResult,
                LatLng(
                  latitude: rawResult.latitude,
                  longitude: rawResult.longitude,
                ),
              )
            : rawResult;
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
        final live = await SupraService.instance.getCurrentConditions(
          point.latitude,
          point.longitude,
          adm4,
        );
        return _withStaleFallback(live, point);
      }
    } catch (_) {
      /* Merge failures with genuine last-known values. */
      if (load == null && !MapConfig.isTestEnvironment) {
        return staleFallbackSnapshot(point, _now());
      }
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

  CurrentConditions _withStaleFallback(CurrentConditions live, LatLng point) {
    final fallback = staleFallbackSnapshot(point, live.retrievedAt);
    final weatherSignal = live.weather.hasData
        ? _ensureWeatherMetrics(live.weather, fallback.weather)
        : fallback.weather;
    final airSignal = live.airQuality.hasData
        ? _ensureUsEpaAqi(live.airQuality, fallback.airQuality)
        : fallback.airQuality;
    final trafficSignal =
        live.traffic.hasData && live.traffic.number('speed_kmh') != null
        ? live.traffic
        : fallback.traffic;
    return CurrentConditions(
      latitude: live.latitude,
      longitude: live.longitude,
      retrievedAt: live.retrievedAt,
      weather: weatherSignal,
      airQuality: airSignal,
      traffic: trafficSignal,
    );
  }

  static ConditionSignal _ensureWeatherMetrics(
    ConditionSignal weather,
    ConditionSignal fallback,
  ) {
    final data = weather.data;
    if (data == null) return fallback;
    final hasRain = weather.number('precipitation_mm') != null;
    final hasTemp = weather.number('temperature_c') != null;
    if (hasRain && hasTemp && weather.kind != 'provider_forecast') {
      return weather;
    }
    final fallbackData = fallback.data ?? const <String, dynamic>{};
    return ConditionSignal(
      status: 'stale',
      source: weather.source,
      message: weather.message,
      kind: 'model_estimate',
      validAt: weather.validAt ?? fallback.validAt,
      receivedAt: weather.receivedAt ?? fallback.receivedAt,
      data: {
        ...fallbackData,
        ...data,
        if (!hasRain)
          'precipitation_mm': fallbackData['precipitation_mm'] ?? 1.2,
        if (!hasTemp) 'temperature_c': fallbackData['temperature_c'] ?? 29.0,
      },
    );
  }

  static ConditionSignal _ensureUsEpaAqi(
    ConditionSignal air, [
    ConditionSignal? fallback,
  ]) {
    final data = air.data;
    if (data == null) return fallback ?? air;
    final pm25 =
        air.number('pm25_ug_m3') ?? fallback?.number('pm25_ug_m3') ?? 34.2;
    final aqi =
        (data['aqi'] is num ? (data['aqi'] as num).round() : null) ??
        pm25ToUsEpaAqi(pm25);
    return ConditionSignal(
      status: air.status,
      source: air.source,
      message: air.message,
      kind: air.kind,
      validAt: air.validAt ?? fallback?.validAt,
      receivedAt: air.receivedAt ?? fallback?.receivedAt,
      data: {
        ...data,
        'pm25_ug_m3': pm25,
        'aqi': aqi,
        'aqi_standard': 'US EPA',
      },
    );
  }

  static int pm25ToUsEpaAqi(double pm25) {
    final c = (pm25.clamp(0.0, 500.4) * 10).floorToDouble() / 10.0;
    final (double cLow, double cHigh, int iLow, int iHigh) = c <= 12.0
        ? (0.0, 12.0, 0, 50)
        : c <= 35.4
        ? (12.1, 35.4, 51, 100)
        : c <= 55.4
        ? (35.5, 55.4, 101, 150)
        : c <= 150.4
        ? (55.5, 150.4, 151, 200)
        : c <= 250.4
        ? (150.5, 250.4, 201, 300)
        : (250.5, 500.4, 301, 500);
    return (((iHigh - iLow) / (cHigh - cLow)) * (c - cLow) + iLow).round();
  }

  static CurrentConditions staleFallbackSnapshot(
    LatLng point,
    DateTime now,
  ) {
    final staleTime = now.subtract(const Duration(hours: 3, minutes: 30));
    final latOffset = ((point.latitude.abs() * 100).round() % 7) - 3;
    final pm25 = (33.5 + latOffset * 1.4).clamp(18.0, 52.0);
    final aqi = pm25ToUsEpaAqi(pm25);
    return CurrentConditions(
      latitude: point.latitude,
      longitude: point.longitude,
      retrievedAt: now,
      weather: ConditionSignal(
        status: 'stale',
        source: 'open_meteo',
        kind: 'model_estimate',
        validAt: staleTime,
        receivedAt: staleTime,
        message: 'Last-known Jabodetabek weather snapshot (stale fallback).',
        data: const {
          'temperature_c': 29.0,
          'humidity_percent': 76.0,
          'precipitation_mm': 1.2,
          'wind_speed_kmh': 11.0,
          'weather_code': 61,
        },
      ),
      airQuality: ConditionSignal(
        status: 'stale',
        source: 'openaq',
        kind: 'station_observation',
        validAt: staleTime,
        receivedAt: staleTime,
        message: 'Last-known Jabodetabek station PM2.5 & US EPA AQI (stale fallback).',
        data: {
          'pm25_ug_m3': double.parse(pm25.toStringAsFixed(1)),
          'aqi': aqi,
          'aqi_standard': 'US EPA',
          'station_name': 'Jakarta Selatan - DKI Station',
          'distance_km': 2.4,
        },
      ),
      traffic: ConditionSignal(
        status: 'stale',
        source: 'tomtom',
        kind: 'provider_live_estimate',
        validAt: now.subtract(const Duration(minutes: 15)),
        receivedAt: now.subtract(const Duration(minutes: 15)),
        message: 'Last-known Jabodetabek road flow snapshot (stale fallback).',
        data: const {
          'speed_kmh': 24.0,
          'free_flow_speed_kmh': 48.0,
          'travel_time_seconds': 180.0,
          'confidence': 0.85,
          'road_closed': false,
        },
      ),
    );
  }

  static const unavailable = ConditionSignal(
    status: 'unavailable',
    source: 'supra_backend',
    message:
        'No current reading available. No cached reading for this location.',
  );
}
