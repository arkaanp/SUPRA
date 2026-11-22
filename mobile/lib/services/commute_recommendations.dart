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
              (free != null &&
                  free >= 10.0 &&
                  speed != null &&
                  speed < free * 0.5));
    }

    double score(RouteOption r) =>
        r.estimatedDuration.inSeconds / 60 +
        (outdoor(r) && ((pm(r) ?? 0) >= 35.5 || (aqi(r) ?? 0) >= 101)
            ? 25
            : 0) +
        (outdoor(r) && (rain(r) ?? 0) > 0.2 ? 40 : 0) +
        (road(r) && congested(r) ? 20 : 0);

    final best = routes.reduce((a, b) => score(a) <= score(b) ? a : b);
    return routes.map((r) {
      final particulate = pm(r), precipitation = rain(r), airIndex = aqi(r);
      final isCongested = congested(r);
      final items = <String>{};
      final risks = <String>{...r.identifiedRisks};
      if (r.mode == TransportMode.motorcycle) {
        items.add('Gunakan helm berstandar dan pakaian pelindung berkendara.');
      }
      if (r.mode == TransportMode.walk) {
        items.add('Gunakan sepatu yang nyaman dan bawa air minum.');
      }
      if (r.mode == TransportMode.publicTransit) {
        items.add(
          'Siapkan alat pembayaran yang sesuai serta waktu untuk berjalan kaki dan berganti kendaraan.',
        );
      }
      if (precipitation != null && precipitation > 0.2) {
        items.add(
          r.mode == TransportMode.motorcycle
              ? 'Bawa perlengkapan berkendara tahan air.'
              : 'Bawa payung atau jas hujan untuk bagian perjalanan di luar ruangan.',
        );
        risks.add(
          'Hujan di lokasi awal dapat memengaruhi perjalanan luar ruangan. Data ini bukan prakiraan banjir.',
        );
      }
      if ((particulate != null && particulate >= 35.5) ||
          (airIndex != null && airIndex >= 101)) {
        items.add(
          'Pertimbangkan masker partikulat yang pas untuk paparan di luar ruangan.',
        );
        risks.add(
          'PM2.5 atau AQI stasiun dekat lokasi awal meningkat. Kabin kendaraan tidak menghilangkan seluruh paparan.',
        );
      }
      if (isCongested) {
        risks.add(
          'Lalu lintas jalan terdekat menunjukkan kemacetan atau penutupan dekat lokasi awal. Siapkan waktu tambahan.',
        );
      }
      final weather = r.conditions?.weather;
      if (weather?.isCurrentAt(now) == true &&
          (weather?.number('temperature_c') ?? 0) >= 32) {
        items.add('Bawa air minum dan pelindung dari sinar matahari.');
      }
      final incomplete = particulate == null || precipitation == null;
      final reason =
          '${r.recommendationReason}\n$version: '
          '${identical(best, r) ? 'Disarankan berdasarkan durasi, paparan luar ruangan, dan kemacetan dari pilihan rute yang tersedia.' : 'Pilihan rute alternatif dari penyedia.'} '
          '${incomplete ? 'Data lingkungan terkini belum lengkap atau sudah lama. Perhatikan keterbatasan data saat memilih rute.' : ''} '
          'Lalu lintas jalan terdekat digunakan untuk menilai lokasi awal, bukan menyesuaikan waktu tempuh seluruh rute.';
      return r.withAdvice(
        recommended: identical(best, r),
        reason: reason,
        risks: risks.toList(),
        items: items.toList(),
      );
    }).toList();
  }
}
