import 'package:flutter/material.dart';

(String, IconData) weatherPresentation({
  int? code,
  String? symbol,
  String? description,
}) {
  final condition = switch (code ?? -1) {
    0 => ('Clear', Icons.wb_sunny_rounded),
    1 || 2 => ('Partly cloudy', Icons.cloud_queue_rounded),
    3 => ('Cloudy', Icons.cloud_rounded),
    45 || 48 => ('Fog', Icons.foggy),
    >= 51 && <= 57 => ('Drizzle', Icons.grain),
    >= 61 && <= 67 || >= 80 && <= 82 => ('Rain', Icons.umbrella_rounded),
    >= 71 && <= 77 || 85 || 86 => ('Snow', Icons.ac_unit),
    >= 95 && <= 99 => ('Thunderstorm', Icons.thunderstorm),
    _ => null,
  };
  if (condition != null) return condition;

  final text = (symbol ?? description ?? '').toLowerCase().split('_').first;
  final (label, icon) = switch (text) {
    _ when text.contains('thunder') || text.contains('petir') => (
      'Thunderstorm',
      Icons.thunderstorm,
    ),
    _ when text.contains('snow') || text.contains('sleet') => (
      'Snow',
      Icons.ac_unit,
    ),
    _ when text.contains('rain') || text.contains('hujan') => (
      'Rain',
      Icons.umbrella_rounded,
    ),
    _
        when text.contains('fog') ||
            text.contains('kabut') ||
            text.contains('asap') =>
      ('Fog', Icons.foggy),
    'fair' ||
    'partlycloudy' ||
    'partly cloudy' ||
    'cerah berawan' => ('Partly cloudy', Icons.cloud_queue_rounded),
    'cloudy' ||
    'overcast' ||
    'berawan' ||
    'berawan tebal' => ('Cloudy', Icons.cloud_rounded),
    'clearsky' || 'clear' || 'sunny' || 'cerah' => (
      'Clear',
      symbol?.endsWith('_night') == true
          ? Icons.nightlight_round
          : Icons.wb_sunny_rounded,
    ),
    _ => ('Weather unavailable', Icons.cloud_off_outlined),
  };
  return (symbol == null && description != null ? description : label, icon);
}

/// Uses a sun and a cloud together for partly cloudy conditions.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon(this.icon, {super.key, required this.size, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (icon != Icons.cloud_queue_rounded) {
      return Icon(icon, size: size, color: color);
    }
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Icon(
              Icons.wb_sunny_rounded,
              size: size * 0.66,
              color: Colors.amber.shade700,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Icon(Icons.cloud_rounded, size: size * 0.73, color: color),
          ),
        ],
      ),
    );
  }
}
