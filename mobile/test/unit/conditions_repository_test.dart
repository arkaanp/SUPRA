import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supra_mobile_ui/models/current_conditions.dart';
import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/services/conditions_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const point = LatLng(latitude: -6.2, longitude: 106.8);
  final time = DateTime.utc(2026, 11, 8, 12);
  CurrentConditions sample(LatLng p, {ConditionSignal? weather}) =>
      CurrentConditions(
        latitude: p.latitude,
        longitude: p.longitude,
        retrievedAt: time,
        weather:
            weather ??
            ConditionSignal(
              status: 'available',
              source: 'open_meteo',
              kind: 'model_estimate',
              validAt: time,
              message: 'Model',
              data: const {'temperature_c': 30},
            ),
        airQuality: ConditionSignal(
          status: 'available',
          source: 'openaq',
          kind: 'station_observation',
          validAt: time,
          message: 'Station',
          data: const {'pm25_ug_m3': 25},
        ),
        traffic: const ConditionSignal(
          status: 'available',
          source: 'tomtom',
          kind: 'provider_live_estimate',
          message: 'Road estimate',
          data: {'speed_kmh': 0},
        ),
      );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Partial failure retains only the failed signal with original times',
    () async {
      var now = time;
      var failWeather = false;
      final repository = ConditionsRepository(
        now: () => now,
        load: (p) async => sample(
          p,
          weather: failWeather ? ConditionsRepository.unavailable : null,
        ),
      );
      await repository.at(point);
      now = time.add(const Duration(minutes: 1));
      failWeather = true;
      final result = await repository.at(point, refresh: true);
      expect(result.weather.status, 'stale');
      expect(result.weather.number('temperature_c'), 30);
      expect(result.weather.validAt, time);
      expect(result.weather.receivedAt, time);
      expect(result.airQuality.status, 'available');
    },
  );
  test('Outage survives app restart without leaking across account, location or village', () async {
    final original = ConditionsRepository(
      userId: () => 'alice',
      now: () => time,
      load: (p) async => sample(p),
    );
    await original.at(point);
    String? account = 'alice';
    final restored = ConditionsRepository(
      userId: () => account,
      now: () => time.add(const Duration(days: 1)),
      load: (_) async => throw StateError('offline'),
    );
    final result = await restored.at(point);
    expect(result.airQuality.status, 'stale');
    expect(result.airQuality.number('pm25_ug_m3'), 25);
    expect(result.airQuality.receivedAt, time);
    expect(result.traffic.number('speed_kmh'), 0);
    expect(result.traffic.status, 'stale');
    expect(
      (await restored.at(point, adm4: '31.71.01.1001')).airQuality.data,
      isNull,
    );
    expect(
      (await restored.at(const LatLng(latitude: -6.3, longitude: 106.8)))
          .airQuality
          .data,
      isNull,
    );
    account = 'bob';
    expect((await restored.at(point)).airQuality.data, isNull);
  });
  test(
    'Years-old persisted readings are not retained after provider failure',
    () async {
      final original = ConditionsRepository(
        userId: () => 'old-user',
        now: () => time,
        load: (p) async => sample(p),
      );
      await original.at(point);
      final restored = ConditionsRepository(
        userId: () => 'old-user',
        now: () => time.add(const Duration(days: 730)),
        load: (_) async => throw StateError('offline'),
      );
      final result = await restored.at(point);
      expect(result.airQuality.data, isNull);
      expect(result.weather.data, isNull);
    },
  );

  test(
    'No cached reading stays empty, and expired traffic is visibly stale',
    () async {
      final empty = ConditionsRepository(
        load: (_) async => throw StateError('offline'),
      );
      expect((await empty.at(point)).airQuality.data, isNull);
      final aged = sample(point)
          .retaining(null)
          .agedAt(time.add(const Duration(minutes: 3)));
      expect(aged.traffic.status, 'stale');
      expect(aged.airQuality.status, 'available');
      expect(aged.traffic.receivedAt, time);
    },
  );
}
