import 'dart:math';

import 'package:flutter/material.dart' hide Route;

import '../models/location.dart';
import '../models/prediction.dart';
import '../models/route.dart';
import '../theme/app_theme.dart';

/// Mock map view showing a route polyline color-coded by traffic density,
/// rain bubbles where rain probability is high, and start/destination pins.
///
/// This is a UI-only stand-in for a map tile provider; in production swap the
/// CustomPaint layer for flutter_map / Google Maps with real tile layers.
class SupraMap extends StatelessWidget {
  final Route? route;
  final List<Prediction> predictions;
  final LatLng start;
  final LatLng destination;
  final ValueChanged<LatLng>? onTapLocation;

  const SupraMap({
    super.key,
    this.route,
    this.predictions = const [],
    required this.start,
    required this.destination,
    this.onTapLocation,
  });

  List<LatLng> get _polyline => route?.waypoints ?? _mockPolyline();

  List<LatLng> _mockPolyline() {
    final List<LatLng> pts = [];
    for (int i = 0; i <= 24; i++) {
      final t = i / 24;
      pts.add(
        LatLng(
          latitude:
              start.latitude +
              (destination.latitude - start.latitude) * t +
              (i.isEven ? 0.0004 : -0.0004),
          longitude:
              start.longitude +
              (destination.longitude - start.longitude) * t -
              (i.isEven ? 0.0003 : 0.0003),
        ),
      );
    }
    return pts;
  }

  /// Traffic value per polyline segment (mocked from nearby predictions).
  double _trafficAt(int index) {
    if (predictions.isEmpty) return 0.5;
    final idx = (index / (_polyline.length / predictions.length)).round().clamp(
      0,
      predictions.length - 1,
    );
    return predictions[idx].predictedTrafficDensity.clamp(0, 1);
  }

  /// Where to draw rain bubbles along the route.
  List<Offset> _rainPoints(Size size) {
    if (predictions.isEmpty) return const [];
    final List<Offset> out = [];
    const rainThreshold = 0.5;
    Offset toPx(LatLng p) {
      // Simple equirectangular projection into the widget bounds.
      final x = 0.08 + (p.longitude - start.longitude) / 0.06 * 0.84;
      final y = 0.92 - (p.latitude - start.latitude) / 0.06 * 0.72;
      return Offset(x * size.width, y * size.height);
    }

    for (int i = 0; i < _polyline.length; i++) {
      final predIdx = (i / (_polyline.length / max(predictions.length, 1)))
          .round()
          .clamp(0, predictions.length - 1);
      if (predictions[predIdx].predictedRainfallProbability > rainThreshold) {
        out.add(toPx(_polyline[i]));
      }
    }
    return out;
  }

  LatLng _pxToLatLng(Offset pos, Size size) {
    final normX = (pos.dx / size.width - 0.08) / 0.84;
    final normY = (0.92 - pos.dy / size.height) / 0.72;
    final lon = start.longitude + normX * 0.06;
    final lat = start.latitude + normY * 0.06;
    return LatLng(
      latitude: double.parse(lat.toStringAsFixed(4)),
      longitude: double.parse(lon.toStringAsFixed(4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onTapLocation != null
              ? (details) =>
                    onTapLocation!(_pxToLatLng(details.localPosition, size))
              : null,
          child: Stack(
            children: [
              // Map canvas: subtle street grid + land.
              CustomPaint(
                size: size,
                painter: _MapCanvasPainter(start, destination, size),
              ),
              // Rain bubbles.
              ..._rainPoints(size).map(
                (p) => Positioned(
                  left: p.dx - 14,
                  top: p.dy - 14,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: SupraTheme.rain.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(color: SupraTheme.rain, width: 1.5),
                    ),
                  ),
                ),
              ),
              // Route polyline with traffic-colored segments.
              CustomPaint(
                size: size,
                painter: _RoutePolylinePainter(
                  polyline: _polyline,
                  toPx: (LatLng p) {
                    final x =
                        0.08 + (p.longitude - start.longitude) / 0.06 * 0.84;
                    final y =
                        0.92 - (p.latitude - start.latitude) / 0.06 * 0.72;
                    return Offset(x * size.width, y * size.height);
                  },
                  trafficAt: _trafficAt,
                ),
              ),
              // Start / destination pins.
              Positioned(
                left: _toPx(start, size).dx - 10,
                top: _toPx(start, size).dy - 26,
                child: _pin(SupraTheme.aqiGood, 'S'),
              ),
              Positioned(
                left: _toPx(destination, size).dx - 10,
                top: _toPx(destination, size).dy - 26,
                child: _pin(SupraTheme.aqiUnhealthy, 'D'),
              ),
              // Legend.
              Positioned(left: 12, bottom: 12, child: _legend),
            ],
          ),
        );
      },
    );
  }

  Offset _toPx(LatLng p, Size size) {
    final x = 0.08 + (p.longitude - start.longitude) / 0.06 * 0.84;
    final y = 0.92 - (p.latitude - start.latitude) / 0.06 * 0.72;
    return Offset(x * size.width, y * size.height);
  }

  Widget _pin(Color color, String letter) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ),
        Container(width: 4, height: 14, color: color),
      ],
    );
  }

  Widget get _legend => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 6,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendItem(Color(0xFF22C55E), 'Free flow'),
        SizedBox(width: 10),
        _legendItem(Color(0xFFF59E0B), 'Moderate'),
        SizedBox(width: 10),
        _legendItem(Color(0xFFEF4444), 'Heavy'),
        SizedBox(width: 10),
        _legendItem(Color(0xFF3B82F6), 'Rain'),
      ],
    ),
  );

  static Widget _legendItem(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

/// Draws the subtle map canvas (land + street grid).
class _MapCanvasPainter extends CustomPainter {
  final LatLng start;
  final LatLng destination;
  final Size size;

  _MapCanvasPainter(this.start, this.destination, this.size);

  Offset _toPx(LatLng p) {
    final x = 0.08 + (p.longitude - start.longitude) / 0.06 * 0.84;
    final y = 0.92 - (p.latitude - start.latitude) / 0.06 * 0.72;
    return Offset(x * size.width, y * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Offset.zero & size, paint);

    // Street grid.
    final street = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 2;
    final path = Path();
    for (
      double x = 0.08 * size.width;
      x <= size.width;
      x += 0.22 * size.width
    ) {
      path.moveTo(x, 0);
      path.lineTo(x, size.height);
    }
    for (
      double y = 0.08 * size.height;
      y <= size.height;
      y += 0.20 * size.height
    ) {
      path.moveTo(0, y);
      path.lineTo(size.width, y);
    }
    canvas.drawPath(path, street..style = PaintingStyle.stroke);

    // Subtle route corridor hint.
    final corridor = Path();
    final pts = <LatLng>[];
    for (int i = 0; i <= 24; i++) {
      final t = i / 24;
      pts.add(
        LatLng(
          latitude:
              start.latitude + (destination.latitude - start.latitude) * t,
          longitude:
              start.longitude + (destination.longitude - start.longitude) * t,
        ),
      );
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final a = _toPx(pts[i]);
      final b = _toPx(pts[i + 1]);
      corridor.moveTo(a.dx, a.dy);
      corridor.lineTo(b.dx, b.dy);
    }
    canvas.drawPath(
      corridor,
      Paint()
        ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.5)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MapCanvasPainter old) => false;
}

/// Draws the traffic-colored route polyline.
class _RoutePolylinePainter extends CustomPainter {
  final List<LatLng> polyline;
  final Offset Function(LatLng) toPx;
  final double Function(int) trafficAt;

  _RoutePolylinePainter({
    required this.polyline,
    required this.toPx,
    required this.trafficAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < polyline.length - 1; i++) {
      final a = toPx(polyline[i]);
      final b = toPx(polyline[i + 1]);
      final traffic = trafficAt(i);
      final paint = Paint()
        ..color = _color(traffic)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // Draw each segment with a slight dash so the line reads as "measured".
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
    // Pulse dot at current position along route.
    final now = DateTime.now().millisecondsSinceEpoch % 4000 / 4000.0;
    final idx = (now * (polyline.length - 1)).round().clamp(
      0,
      polyline.length - 1,
    );
    final pos = toPx(polyline[idx]);
    canvas.drawCircle(
      pos,
      5 + 2 * sin(now * 2 * pi),
      Paint()..color = SupraTheme.brand.withValues(alpha: 0.45),
    );
    canvas.drawCircle(pos, 4, Paint()..color = SupraTheme.brand);
  }

  Color _color(double traffic) {
    if (traffic <= 0.4) return SupraTheme.trafficFree;
    if (traffic <= 0.7) return SupraTheme.trafficModerate;
    return SupraTheme.trafficHeavy;
  }

  @override
  bool shouldRepaint(covariant _RoutePolylinePainter old) =>
      old.polyline != polyline || old.trafficAt != trafficAt;
}
