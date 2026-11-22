import '../utils/display_text.dart';

class ConditionSignal {
  const ConditionSignal({
    required this.status,
    required this.source,
    required this.message,
    this.kind,
    this.validAt,
    this.data,
    this.receivedAt,
  });
  final String status;
  final String source;
  final String message;
  final String? kind;
  final DateTime? validAt;
  final Map<String, dynamic>? data;

  /// When these particular values were fetched, not the latest refresh attempt.
  final DateTime? receivedAt;

  String get providerLabel => switch (source) {
    'bmkg' => 'BMKG',
    'met_norway' => 'MET Norway',
    'open_meteo' => 'Open-Meteo',
    'open_meteo_cams' => 'Open-Meteo / CAMS',
    'openaq' => 'OpenAQ',
    'tomtom' => 'TomTom',
    'supra_backend' => 'Server SUPRA',
    _ => source,
  };

  String get unavailableLabel => switch (message) {
    'not_configured' => 'Belum dikonfigurasi',
    'provider_invalid_credentials' => 'API key penyedia tidak valid',
    'provider_access_denied' => 'Akses ditolak',
    'provider_rate_limited' => 'Batas permintaan tercapai',
    'provider_timeout' => 'Waktu tunggu habis',
    'invalid_provider_response' => 'Respons penyedia tidak valid',
    'stale_provider_data' => 'Data penyedia sudah lama',
    _ => 'Tidak tersedia',
  };

  String get sourceDetails => [
    '$providerLabel · ${signalStatusLabel(status)}${kind == null ? '' : ' · ${signalKindLabel(kind)}'}',
    if (validAt != null) 'Berlaku: ${formatWib(validAt!)}',
    if (receivedAt != null) 'Diambil: ${formatWib(receivedAt!)}',
    if (data?['station_name'] != null) 'Stasiun: ${data!['station_name']}',
    if (data?['distance_km'] is num)
      'Jarak: ${(data!['distance_km'] as num).toStringAsFixed(1)} km',
    if (data?['provider']?['name'] != null)
      'Penyedia: ${data!['provider']['name']}',
    if (data?['owner']?['name'] != null) 'Pemilik: ${data!['owner']['name']}',
    for (final l in data?['licenses'] as List? ?? [])
      'Lisensi: ${l['name'] ?? 'Lihat ketentuan sumber'}${l['attribution']?['name'] == null ? '' : ' · ${l['attribution']['name']}'}',
    if (source == 'tomtom' && message == 'provider_invalid_credentials')
      'TomTom menolak API key server (HTTP 401). Perbarui TOMTOM_API_KEY di server.'
    else if (source == 'tomtom' && message == 'provider_access_denied')
      'Periksa akses Flow Segment Data dan pembatasan API key server di TomTom.'
    else if (message.startsWith('provider_') ||
        message == 'not_configured' ||
        message == 'invalid_provider_response' ||
        message == 'stale_provider_data')
      unavailableLabel
    else if (message.isNotEmpty)
      message,
  ].join('\n');

  bool get hasData => data != null && data!.isNotEmpty;
  bool get isStale => status == 'stale';
  ConditionSignal withReceipt(DateTime time) => ConditionSignal(
    status: status,
    source: source,
    message: message,
    kind: kind,
    validAt: validAt,
    data: data,
    receivedAt: receivedAt ?? time,
  );
  ConditionSignal asStale(String reason) => ConditionSignal(
    status: 'stale',
    source: source,
    message: reason,
    kind: kind,
    validAt: validAt,
    data: data,
    receivedAt: receivedAt,
  );
  ConditionSignal agedAt(DateTime now) {
    if (!hasData || isStale || status != 'available') return this;
    final time = validAt ?? receivedAt;
    final maxAge = kind == 'provider_live_estimate'
        ? const Duration(minutes: 2)
        : const Duration(hours: 3);
    if (time != null && now.toUtc().difference(time.toUtc()) > maxAge) {
      return asStale(
        'Data terakhir tersimpan; batas waktu kesegaran data terlampaui.',
      );
    }
    return this;
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'source': source,
    'message': message,
    'kind': kind,
    'valid_at': validAt?.toUtc().toIso8601String(),
    'received_at': receivedAt?.toUtc().toIso8601String(),
    'data': data,
  };

  bool isCurrentAt(DateTime now, {Duration maxAge = const Duration(hours: 3)}) {
    if (status != 'available' || data == null || kind == 'provider_forecast') {
      return false;
    }
    if (validAt == null) return kind == 'provider_live_estimate';
    final age = now.toUtc().difference(validAt!.toUtc());
    return age >= const Duration(minutes: -10) && age <= maxAge;
  }

  double? get usAqi => data?['aqi_standard'] == 'US EPA' ? number('aqi') : null;

  double? number(String key) {
    final value = data?[key];
    return value is num &&
            value.isFinite &&
            (value >= 0 || key == 'temperature_c')
        ? value.toDouble()
        : null;
  }

  factory ConditionSignal.fromJson(Map<String, dynamic> json) =>
      ConditionSignal(
        status: json['status'] as String,
        source: json['source'] as String,
        message: json['message'] as String,
        kind: json['kind'] as String?,
        validAt: json['valid_at'] == null
            ? null
            : DateTime.parse(json['valid_at'] as String),
        data: json['data'] as Map<String, dynamic>?,
        receivedAt: DateTime.tryParse(json['received_at'] as String? ?? ''),
      );
}

class CurrentConditions {
  const CurrentConditions({
    required this.latitude,
    required this.longitude,
    required this.retrievedAt,
    required this.weather,
    required this.airQuality,
    this.airIndex,
    required this.traffic,
  });
  final double latitude;
  final double longitude;
  final DateTime retrievedAt;
  final ConditionSignal weather;
  final ConditionSignal airQuality;
  final ConditionSignal? airIndex;
  ConditionSignal get aqiSignal => airIndex ?? airQuality;
  final ConditionSignal traffic;

  String get sourceDetails => [
    airQuality.sourceDetails,
    if (airIndex != null) airIndex!.sourceDetails,
    weather.sourceDetails,
    traffic.sourceDetails,
    'Diperiksa ${formatWib(retrievedAt)}',
  ].join('\n\n');

  CurrentConditions agedAt(DateTime now) => CurrentConditions(
    latitude: latitude,
    longitude: longitude,
    retrievedAt: retrievedAt,
    weather: weather.agedAt(now),
    airQuality: airQuality.agedAt(now),
    airIndex: airIndex?.agedAt(now),
    traffic: traffic.agedAt(now),
  );

  /// Partial outages keep each signal's own last-known values and timestamps.
  CurrentConditions retaining(CurrentConditions? previous) {
    ConditionSignal signal(ConditionSignal next, ConditionSignal? old) {
      if (next.hasData) return next.withReceipt(retrievedAt);
      final oldTime = old?.validAt ?? old?.receivedAt;
      if (old?.hasData == true &&
          oldTime != null &&
          retrievedAt.toUtc().difference(oldTime.toUtc()) <=
              const Duration(hours: 24)) {
        return old!.asStale(
          'Data terbaru tidak tersedia. Menampilkan data terakhir tersimpan. ${next.message}',
        );
      }
      return next;
    }

    final sameLocation =
        previous != null &&
        previous.latitude == latitude &&
        previous.longitude == longitude;
    return CurrentConditions(
      latitude: latitude,
      longitude: longitude,
      retrievedAt: retrievedAt,
      weather: signal(weather, sameLocation ? previous.weather : null),
      airQuality: signal(airQuality, sameLocation ? previous.airQuality : null),
      airIndex:
          airIndex?.withReceipt(retrievedAt) ??
          (airQuality.usAqi == null && sameLocation && previous.airIndex != null
              ? _retainedIndex(previous.airIndex!, retrievedAt)
              : null),
      traffic: signal(traffic, sameLocation ? previous.traffic : null),
    );
  }

  static ConditionSignal? _retainedIndex(
    ConditionSignal previous,
    DateTime now,
  ) {
    final time = previous.validAt ?? previous.receivedAt;
    return time != null && now.difference(time) <= const Duration(hours: 24)
        ? previous.asStale(
            'AQI terbaru tidak tersedia. Menampilkan indeks terakhir tersimpan.',
          )
        : null;
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'retrieved_at': retrievedAt.toUtc().toIso8601String(),
    'weather': weather.toJson(),
    'air_quality': airQuality.toJson(),
    if (airIndex != null) 'air_index': airIndex!.toJson(),
    'traffic': traffic.toJson(),
  };

  factory CurrentConditions.fromJson(
    Map<String, dynamic> json,
  ) => CurrentConditions(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    retrievedAt: DateTime.parse(json['retrieved_at'] as String),
    weather: ConditionSignal.fromJson(json['weather'] as Map<String, dynamic>),
    airQuality: ConditionSignal.fromJson(
      json['air_quality'] as Map<String, dynamic>,
    ),
    airIndex: json['air_index'] is Map<String, dynamic>
        ? ConditionSignal.fromJson(json['air_index'] as Map<String, dynamic>)
        : null,
    traffic: ConditionSignal.fromJson(json['traffic'] as Map<String, dynamic>),
  );
}
