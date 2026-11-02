import 'package:flutter/material.dart';

import '../models/prediction.dart';
import '../theme/app_theme.dart';

/// One hourly forecast row in the trip forecast screen.
class ForecastCard extends StatelessWidget {
  final Prediction prediction;

  const ForecastCard({super.key, required this.prediction});

  @override
  Widget build(BuildContext context) {
    final band = prediction.aqiBand;
    final traffic = prediction.predictedTrafficDensity;
    final trafficColor = traffic <= 0.4
        ? SupraTheme.trafficFree
        : traffic <= 0.7
        ? SupraTheme.trafficModerate
        : SupraTheme.trafficHeavy;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: band.color().withValues(alpha: 0.12),
          child: Text(
            prediction.timeLabel,
            style: TextStyle(
              color: band.color(),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          '${prediction.predictedAqi.round()} AQI · ${band.label()}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                _miniBar(
                  'Rain',
                  prediction.predictedRainfallProbability,
                  SupraTheme.rain,
                ),
                const SizedBox(width: 12),
                _miniBar('Traffic', traffic, trafficColor),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Rain ${prediction.rainLabel} · ${prediction.trafficLabel}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: band.color().withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            band.label(),
            style: TextStyle(
              color: band.color(),
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 5,
            backgroundColor: const Color(0xFFE2E8F0),
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(value * 100).round()}% $label',
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}
