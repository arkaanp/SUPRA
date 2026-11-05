class ConditionSignal {
  const ConditionSignal({
    required this.status,
    required this.source,
    required this.message,
    this.kind,
    this.validAt,
    this.data,
  });
  final String status;
  final String source;
  final String message;
  final String? kind;
  final DateTime? validAt;
  final Map<String, dynamic>? data;

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
