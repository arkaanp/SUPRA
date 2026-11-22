import 'package:flutter/material.dart';

(String, IconData) weatherPresentation({
  int? code,
  String? symbol,
  String? description,
}) {
  final condition = switch (code ?? -1) {
    0 => ('Cerah', Icons.wb_sunny_rounded),
    1 || 2 => ('Cerah berawan', Icons.cloud_queue_rounded),
    3 => ('Berawan', Icons.cloud_rounded),
    45 || 48 => ('Berkabut', Icons.foggy),
    >= 51 && <= 57 => ('Gerimis', Icons.grain),
    >= 61 && <= 67 || >= 80 && <= 82 => ('Hujan', Icons.umbrella_rounded),
    >= 71 && <= 77 || 85 || 86 => ('Salju', Icons.ac_unit),
    >= 95 && <= 99 => ('Hujan petir', Icons.thunderstorm),
    _ => null,
  };
  if (condition != null) return condition;

  final text = (symbol ?? description ?? '').toLowerCase().split('_').first;
  final (label, icon) = switch (text) {
    _ when text.contains('thunder') || text.contains('petir') => (
      'Hujan petir',
      Icons.thunderstorm,
    ),
    _ when text.contains('snow') || text.contains('sleet') => (
      'Salju',
      Icons.ac_unit,
    ),
    _ when text.contains('rain') || text.contains('hujan') => (
      'Hujan',
      Icons.umbrella_rounded,
    ),
    _
        when text.contains('fog') ||
            text.contains('kabut') ||
            text.contains('asap') =>
      ('Berkabut', Icons.foggy),
    'fair' ||
    'partlycloudy' ||
    'partly cloudy' ||
    'cerah berawan' => ('Cerah berawan', Icons.cloud_queue_rounded),
    'cloudy' ||
    'overcast' ||
    'berawan' ||
    'berawan tebal' => ('Berawan', Icons.cloud_rounded),
    'clearsky' || 'clear' || 'sunny' || 'cerah' => (
      'Cerah',
      symbol?.endsWith('_night') == true
          ? Icons.nightlight_round
          : Icons.wb_sunny_rounded,
    ),
    _ => ('Cuaca tidak tersedia', Icons.cloud_off_outlined),
  };
  return (label, icon);
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
