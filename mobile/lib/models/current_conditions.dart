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
      return asStale('Last-known reading; freshness window exceeded.');
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

  double? number(String key) {
    final value = data?[key];
    return value is num && value.isFinite && value >= 0
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
    required this.traffic,
  });
  final double latitude;
  final double longitude;
  final DateTime retrievedAt;
  final ConditionSignal weather;
  final ConditionSignal airQuality;
  final ConditionSignal traffic;

  CurrentConditions agedAt(DateTime now) => CurrentConditions(
    latitude: latitude,
    longitude: longitude,
    retrievedAt: retrievedAt,
    weather: weather.agedAt(now),
    airQuality: airQuality.agedAt(now),
    traffic: traffic.agedAt(now),
  );

  /// Partial outages keep each signal's own last-known values and timestamps.
  CurrentConditions retaining(CurrentConditions? previous) {
    ConditionSignal signal(ConditionSignal next, ConditionSignal? old) {
      if (next.hasData) return next.withReceipt(retrievedAt);
      if (old?.hasData == true) {
        return old!.asStale(
          'Latest lookup unavailable. Showing last-known data. ${next.message}',
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
      traffic: signal(traffic, sameLocation ? previous.traffic : null),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'retrieved_at': retrievedAt.toUtc().toIso8601String(),
    'weather': weather.toJson(),
    'air_quality': airQuality.toJson(),
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
    traffic: ConditionSignal.fromJson(json['traffic'] as Map<String, dynamic>),
  );
}
