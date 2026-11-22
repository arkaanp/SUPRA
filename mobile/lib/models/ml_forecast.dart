/// Hourly outputs from the versioned Python/PyTorch model, with input provenance.
class MlForecastHour {
  const MlForecastHour({
    required this.targetTime,
    required this.temperatureC,
    required this.precipitationMm,
    required this.pm25,
    required this.aqi,
    required this.rainProbability,
  });
  final DateTime targetTime;
  final double temperatureC, precipitationMm, rainProbability;
  final double? pm25, aqi;
  factory MlForecastHour.fromJson(
    Map<String, dynamic> j, {
    bool weatherOnly = false,
  }) {
    double number(String key, double min, double max) {
      final value = (j[key] as num).toDouble();
      if (!value.isFinite || value < min || value > max) {
        throw FormatException('Invalid forecast $key');
      }
      return value;
    }

    if (weatherOnly && (j['pm25_ug_m3'] != null || j['aqi'] != null)) {
      throw const FormatException(
        'Unexpected air forecast in weather-only model',
      );
    }
    if (j['traffic_speed_kmh'] != null || j['traffic_density'] != null) {
      throw const FormatException('Unsupported traffic forecast');
    }
    return MlForecastHour(
      targetTime: DateTime.parse(j['target_time'] as String),
      temperatureC: number('temperature_c', -50, 60),
      precipitationMm: number('precipitation_mm', 0, 500),
      pm25: weatherOnly ? null : number('pm25_ug_m3', 0, 2000),
      aqi: weatherOnly ? null : number('aqi', 0, 1000),
      rainProbability: number('rain_probability', 0, 1),
    );
  }
}

class MlForecast {
  const MlForecast({
    required this.latitude,
    required this.longitude,
    required this.modelId,
    required this.generatedAt,
    required this.inputThrough,
    required this.expiresAt,
    required this.hourly,
    required this.attribution,
    required this.validation,
  });
  final double latitude, longitude;
  final String modelId, attribution;
  final DateTime generatedAt, inputThrough, expiresAt;
  final List<MlForecastHour> hourly;
  final Map<String, dynamic> validation;
  bool isCurrentAt(DateTime now) =>
      generatedAt.isBefore(now.add(const Duration(minutes: 5))) &&
      !inputThrough.isAfter(now) &&
      now.difference(inputThrough) <= const Duration(hours: 2) &&
      expiresAt.isAfter(now);
  MlForecastHour? nextAt(DateTime now) {
    if (!isCurrentAt(now)) return null;
    for (final h in hourly) {
      if (h.targetTime.isAfter(now)) return h;
    }
    return null;
  }

  factory MlForecast.fromJson(Map<String, dynamic> j) {
    if (j['framework'] != 'PyTorch' || (j['model_id'] as String).isEmpty) {
      throw const FormatException('Unidentified model');
    }
    final hours = (j['hourly'] as List)
        .map(
          (v) => MlForecastHour.fromJson(
            v as Map<String, dynamic>,
            weatherOnly: j['scope'] == 'weather_only',
          ),
        )
        .toList();
    if (hours.isEmpty || hours.length > 12) {
      throw const FormatException('Invalid forecast horizon');
    }
    for (var i = 1; i < hours.length; i++) {
      if (hours[i].targetTime.difference(hours[i - 1].targetTime) !=
          const Duration(hours: 1)) {
        throw const FormatException('Non-hourly forecast');
      }
    }
    return MlForecast(
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      modelId: j['model_id'] as String,
      generatedAt: DateTime.parse(j['generated_at'] as String),
      inputThrough: DateTime.parse(j['input_through'] as String),
      expiresAt: DateTime.parse(j['expires_at'] as String),
      hourly: hours,
      attribution: (j['sources'] as Map)['attribution'] as String,
      validation: j['validation'] as Map<String, dynamic>,
    );
  }
}
