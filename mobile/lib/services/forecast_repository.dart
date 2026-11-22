import '../config/map_config.dart';
import '../models/location.dart';
import '../models/ml_forecast.dart';
import 'supra_api_service.dart';
import 'backend_api.dart';

class ForecastRepository {
  ForecastRepository({this.load, bool? useNetwork, DateTime Function()? now})
    : useNetwork = useNetwork ?? (load != null || !MapConfig.isTestEnvironment),
      now = now ?? DateTime.now;
  static final instance = ForecastRepository();
  final Future<Map<String, dynamic>> Function(LatLng)? load;
  final bool useNetwork;
  final DateTime Function() now;
  static String failureMessage(Object error) => error is ApiException
      ? 'ML forecast unavailable. ${error.message}'
      : 'ML forecast unavailable. Try refreshing.';

  final _cache = <String, (DateTime, MlForecast)>{};
  final _pending = <String, Future<MlForecast>>{};
  Future<MlForecast> at(LatLng point, {bool refresh = false}) async {
    if (!useNetwork) throw StateError('ML service unavailable offline');
    final scope = load != null
        ? 'test'
        : SupraService.instance.currentUser?.id ?? 'signed-out';
    final key = '$scope:${point.latitude},${point.longitude}';
    final cached = _cache[key];
    if (!refresh &&
        cached != null &&
        now().difference(cached.$1) < const Duration(minutes: 10) &&
        cached.$2.isCurrentAt(now())) {
      return cached.$2;
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final future =
        () async {
          final result = MlForecast.fromJson(
            await (load ?? SupraService.instance.hourlyForecast)(point),
          );
          if (!result.isCurrentAt(now()) ||
              (result.latitude - point.latitude).abs() > 0.0001 ||
              (result.longitude - point.longitude).abs() > 0.0001) {
            throw const FormatException('Stale or mismatched ML forecast');
          }
          if (load == null && SupraService.instance.currentUser?.id != scope) {
            throw StateError('Account changed');
          }
          if (_cache.length >= 16) _cache.clear();
          _cache[key] = (now(), result);
          return result;
        }().catchError((Object error, StackTrace trace) {
          // A failed refresh can still use this account and location's unexpired forecast.
          if ((load != null ||
                  SupraService.instance.currentUser?.id == scope) &&
              cached != null &&
              cached.$2.nextAt(now()) != null) {
            return cached.$2;
          }
          Error.throwWithStackTrace(error, trace);
        });
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }
}
