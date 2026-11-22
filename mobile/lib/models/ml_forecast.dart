/// Hourly outputs from the versioned Python/PyTorch model, with input provenance.
class MlForecastHour {
  const MlForecastHour({
    required this.targetTime,
    required this.temperatureC,
    required this.precipitationMm,
    required this.pm25,
    required this.aqi,
    required this.rainProbability,
    this.providerAqi,
    this.weatherSymbol,
    this.estimatedAqi,
    this.estimatedPm25,
  });
  final DateTime targetTime;
  final double temperatureC, precipitationMm, rainProbability;
  final double? pm25, aqi, providerAqi, estimatedAqi, estimatedPm25;
  final String? weatherSymbol;
  double? get displayAqi => aqi ?? providerAqi ?? estimatedAqi;
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
    if ((j['estimated_aqi'] != null || j['estimated_pm25'] != null) &&
        (!weatherOnly ||
            j['estimated_aqi'] == null ||
            j['estimated_pm25'] == null ||
            j['provider_aqi'] != null)) {
      throw const FormatException('Invalid estimated air forecast');
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
      providerAqi: weatherOnly && j['provider_aqi'] != null
          ? number('provider_aqi', 0, 2000)
          : null,
      weatherSymbol: j['weather_symbol'] as String?,
      estimatedAqi: weatherOnly && j['estimated_aqi'] != null
          ? number('estimated_aqi', 0, 4000)
          : null,
      estimatedPm25: weatherOnly && j['estimated_pm25'] != null
          ? number('estimated_pm25', 0, 2000)
          : null,
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
      attribution: [
        (j['sources'] as Map)['attribution'] as String,
        if (j['air_forecast'] is Map)
          [
            j['air_forecast']['model_id'],
            'Stasiun: ${j['air_forecast']['station']['station_name']}',
            'Jarak: ${(j['air_forecast']['station']['distance_km'] as num).toStringAsFixed(1)} km',
            'Data masukan hingga ${j['air_forecast']['input_through']}',
            j['air_forecast']['limitations'],
            'Penyedia: ${j['air_forecast']['station']['provider']}',
            'Lisensi: ${j['air_forecast']['station']['licenses']}',
          ].join('\n'),
        if (j['sources']['air_forecast'] is String)
          j['sources']['air_forecast'] as String,
        if (j['sources']['weather_symbols'] is String &&
            j['sources']['weather_symbols'] != j['sources']['attribution'])
          j['sources']['weather_symbols'] as String,
      ].join('\n'),
      validation: j['validation'] as Map<String, dynamic>,
    );
  }
}
