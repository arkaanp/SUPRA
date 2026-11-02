import 'package:flutter/material.dart';

import '../models/prediction.dart';

/// Color-coded AQI chip used on condition cards and forecast rows.
class AqiBadge extends StatelessWidget {
  final double aqi;
  final double size;

  const AqiBadge({super.key, required this.aqi, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final band = aqiLevel(aqi);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: band.color().withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: band.color(), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        aqi.round().toString(),
        style: TextStyle(
          color: band.color(),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.5,
        ),
      ),
    );
  }
}
