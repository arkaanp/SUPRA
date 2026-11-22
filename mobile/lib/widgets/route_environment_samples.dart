import 'package:flutter/material.dart';

import 'source_info_button.dart';
import 'weather_icon.dart';

import '../models/environmental_zone.dart';

/// Compact sample footprint; the detailed reading lives in the route sheet.
class EnvironmentalSampleMarker extends StatelessWidget {
  const EnvironmentalSampleMarker({super.key, required this.sample});
  final EnvironmentalZone sample;
  @override
  Widget build(BuildContext context) {
    final rain = sample.rainfallMm;
    return Tooltip(
      message: sample.mapLabel,
      child: Container(
        decoration: BoxDecoration(
          color: sample.solidAqiColor.withValues(alpha: 0.20),
          border: Border.all(
            color: sample.solidAqiColor.withValues(alpha: 0.75),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  rain == null
                      ? Icons.cloud_off_outlined
                      : rain > 0
                      ? Icons.water_drop
                      : Icons.cloud_outlined,
                  size: rain != null && rain > 5 ? 20 : 15,
                  color: rain != null && rain > 0
                      ? Colors.blue.shade700
                      : Colors.blueGrey,
                ),
                Text(
                  rain == null ? '—' : '${rain.toStringAsFixed(1)} mm',
                  style: const TextStyle(fontSize: 9, color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placed after transport cards inside their existing scroll view.
class RouteEnvironmentSamples extends StatelessWidget {
  const RouteEnvironmentSamples({super.key, required this.samples});
  final List<EnvironmentalZone> samples;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Kondisi di sepanjang rute',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final band in [
            (Colors.green, 'Baik'),
            (Colors.amber, 'Sedang'),
            (Colors.orange, 'Sensitif'),
            (Colors.red, 'Tidak sehat'),
            (Colors.purple, 'Sangat tidak sehat'),
            (const Color(0xFF7F1D1D), 'Berbahaya'),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.square, size: 9, color: band.$1),
                const SizedBox(width: 3),
                Text(band.$2, style: const TextStyle(fontSize: 9)),
              ],
            ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Kotak menandai titik data. Warna PM2.5 bukan kategori AQI resmi. Simbol biru menunjukkan curah hujan dalam mm.',
          style: TextStyle(fontSize: 10, color: Colors.blueGrey),
        ),
      ),
      if (samples.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Memuat kondisi rute…'),
        ),
      for (final sample in samples) _RouteSampleCard(sample: sample),
    ],
  );
}

class _RouteSampleCard extends StatelessWidget {
  const _RouteSampleCard({required this.sample});
  final EnvironmentalZone sample;

  @override
  Widget build(BuildContext context) {
    final conditions = sample.conditions?.agedAt(DateTime.now());
    final weather = conditions?.weather;
    final aqi = sample.usAqi?.round();
    final temperature = weather?.number('temperature_c')?.round();
    final rainfall = sample.rainfallMm;
    final (weatherLabel, icon) = weatherPresentation(
      code: weather?.number('weather_code')?.toInt(),
      symbol: weather?.data?['weather_symbol'] as String?,
      description:
          sample.weatherDescription ?? weather?.data?['description'] as String?,
    );

    return Container(
      key: ValueKey('sample-card-${sample.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        color: sample.solidAqiColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sample.solidAqiColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sample.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              SourceInfoButton(
                title: 'Sumber untuk ${sample.name}',
                details: conditions?.sourceDetails ?? sample.healthAdvisory,
                compact: true,
              ),
            ],
          ),
          _SampleReading(
            icon: Icons.air_rounded,
            label: 'Kualitas udara',
            value: aqi == null
                ? 'AQI tidak tersedia'
                : 'AQI AS $aqi · ${sample.colorBandLabel}${conditions?.aqiSignal.kind == 'calculated_index' ? ' · perkiraan NowCast' : ''}',
            stale: aqi != null && conditions?.aqiSignal.isStale == true,
          ),
          if (sample.pm25 != null) ...[
            const SizedBox(height: 2),
            Text(
              'PM2.5 ${sample.pm25!.toStringAsFixed(1)} µg/m³'
              '${conditions?.airQuality.isStale == true ? ' · data lama' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _SampleReading(
                icon: icon,
                label: weather?.kind == 'provider_forecast'
                    ? 'Prakiraan cuaca'
                    : 'Cuaca',
                value: weatherLabel,
                stale: weather?.isStale == true,
              ),
              _SampleReading(
                icon: Icons.thermostat_rounded,
                label: 'Suhu',
                value: temperature == null
                    ? 'Tidak tersedia'
                    : '$temperature°C',
                stale: weather?.isStale == true,
              ),
              _SampleReading(
                icon: Icons.water_drop_outlined,
                label: 'Hujan',
                value: rainfall == null
                    ? 'Tidak tersedia'
                    : '${rainfall.toStringAsFixed(1)} mm',
                stale: weather?.isStale == true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SampleReading extends StatelessWidget {
  const _SampleReading({
    required this.icon,
    required this.label,
    required this.value,
    required this.stale,
  });

  final IconData icon;
  final String label, value;
  final bool stale;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      WeatherIcon(icon, size: 19, color: const Color(0xFF475569)),
      const SizedBox(width: 6),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label${stale ? ' · data lama' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );
}
