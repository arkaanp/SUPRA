import 'package:flutter/material.dart';

import '../models/environmental_zone.dart';

/// Compact sample footprint; the detailed reading lives in the route sheet.
class EnvironmentalSampleMarker extends StatelessWidget {
  const EnvironmentalSampleMarker({super.key, required this.sample});
  final EnvironmentalZone sample;
  @override
  Widget build(BuildContext context) {
    final rain = sample.rainfallMm;
    return Tooltip(
      message: '${sample.mapLabel}\n${sample.healthAdvisory}',
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
        'Conditions along your route',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final band in [
            (Colors.green, 'Good'),
            (Colors.amber, 'Moderate'),
            (Colors.orange, 'Sensitive'),
            (Colors.red, 'Unhealthy'),
            (Colors.purple, 'Very unhealthy'),
            (const Color(0xFF7F1D1D), 'Hazardous'),
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
          'Squares mark samples. PM2.5 color bands are not an official AQI. Blue symbols show rain in mm.',
          style: TextStyle(fontSize: 10, color: Colors.blueGrey),
        ),
      ),
      if (samples.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Loading route samples…'),
        ),
      for (final sample in samples)
        Container(
          key: ValueKey('sample-card-${sample.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: sample.solidAqiColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sample.solidAqiColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 5, height: 50, color: sample.solidAqiColor),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      sample.mapLabel
                          .split('\n')
                          .first
                          .replaceFirst('${sample.name} · ', ''),
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      sample.colorBandLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sample.solidAqiColor,
                      ),
                    ),
                    Text(
                      sample.mapLabel.split('\n').last,
                      style: const TextStyle(fontSize: 11),
                    ),
                    Text(
                      '${sample.conditions?.airQuality.source ?? 'Unavailable'} · ${sample.conditions?.weather.source ?? 'Unavailable'}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                      ),
                    ),
                    Material(
                      type: MaterialType.transparency,
                      child: ExpansionTile(
                        title: const Text(
                          'Source & timestamps',
                          style: TextStyle(fontSize: 10),
                        ),
                        tilePadding: EdgeInsets.zero,
                        dense: true,
                        children: [
                          Text(
                            sample.healthAdvisory,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
