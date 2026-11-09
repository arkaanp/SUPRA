import '../models/route_option.dart';

/// Versioned, explainable rules. Ranking penalties are preferences, never ETA
/// adjustments. Stale values remain visible but cannot establish current risk.
class CommuteRecommendations {
  static const version = 'commute-rules-v1';
  static List<RouteOption> rank(List<RouteOption> routes) {
    if (routes.isEmpty) return [];
    final now = DateTime.now();
    bool outdoor(RouteOption r) =>
        r.mode == TransportMode.walk || r.mode == TransportMode.motorcycle;
    bool road(RouteOption r) =>
        r.mode == TransportMode.car || r.mode == TransportMode.motorcycle;
    double? pm(RouteOption r) =>
        r.conditions?.airQuality.isCurrentAt(now) == true
        ? r.conditions!.airQuality.number('pm25_ug_m3')
        : null;
    double? aqi(RouteOption r) =>
        r.conditions?.airQuality.isCurrentAt(now) == true
        ? r.conditions!.airQuality.number('aqi')
        : r.predictedAqi;
    double? rain(RouteOption r) =>
        r.conditions?.weather.isCurrentAt(now) == true
        ? r.conditions!.weather.number('precipitation_mm')
        : null;
    bool congested(RouteOption r) {
      final traffic = r.conditions?.traffic;
      if (traffic == null || !traffic.isCurrentAt(now)) return false;
      final closed = traffic.data?['road_closed'] == true;
      final conf = traffic.number('confidence') ?? 0;
      final speed = traffic.number('speed_kmh');
      final free = traffic.number('free_flow_speed_kmh');
      return conf >= 0.5 &&
          (closed ||
              (free != null && free >= 10.0 && speed != null && speed < free * 0.5));
    }

    double score(RouteOption r) =>
        r.estimatedDuration.inSeconds / 60 +
        (outdoor(r) && ((pm(r) ?? 0) >= 35.5 || (aqi(r) ?? 0) >= 101) ? 25 : 0) +
        (outdoor(r) && (rain(r) ?? 0) > 0.2 ? 40 : 0) +
        (road(r) && congested(r) ? 20 : 0);

    final best = routes.reduce((a, b) => score(a) <= score(b) ? a : b);
    return routes.map((r) {
      final particulate = pm(r), precipitation = rain(r), airIndex = aqi(r);
      final isCongested = congested(r);
      final items = <String>{};
      final risks = <String>{...r.identifiedRisks};
      if (r.mode == TransportMode.motorcycle) {
        items.add('Wear an approved helmet and protective riding clothing.');
      }
      if (r.mode == TransportMode.walk) {
        items.add('Wear comfortable shoes and carry drinking water.');
      }
      if (r.mode == TransportMode.publicTransit) {
        items.add(
          'Bring a suitable fare/payment method; allow time for walking and transfers.',
        );
      }
      if (precipitation != null && precipitation > 0.2) {
        items.add(
          r.mode == TransportMode.motorcycle
              ? 'Bring waterproof riding gear.'
              : 'Bring a compact umbrella or raincoat for outdoor legs.',
        );
        risks.add(
          'Current origin precipitation may affect outdoor legs; this is not a flood forecast.',
        );
      }
      if ((particulate != null && particulate >= 35.5) ||
          (airIndex != null && airIndex >= 101)) {
        items.add(
          'Consider a well-fitting particulate respirator for outdoor exposure.',
        );
        risks.add(
          'Origin station PM2.5 / AQI is elevated; a cabin does not eliminate exposure.',
        );
      }
      if (isCongested) {
        risks.add(
          'Nearest-road traffic indicates congestion or closure near origin; allow buffer.',
        );
      }
      final weather = r.conditions?.weather;
      if (weather?.isCurrentAt(now) == true &&
          (weather?.number('temperature_c') ?? 0) >= 32) {
        items.add('Bring water and sun protection.');
      }
      final incomplete = particulate == null || precipitation == null;
      final reason =
          '${r.recommendationReason}\n$version: '
          '${identical(best, r) ? 'Preferred among the available provider routes using duration, outdoor-exposure, and road congestion preferences.' : 'Alternative provider route.'} '
          '${incomplete ? 'Current environmental coverage is incomplete/stale; no missing value is assumed safe.' : ''} '
          'Nearest-road traffic is an origin preference, not a whole-route ETA adjustment.';
      return r.withAdvice(
        recommended: identical(best, r),
        reason: reason,
        risks: risks.toList(),
        items: items.toList(),
      );
    }).toList();
  }
}
