import 'package:flutter/material.dart' hide Route;

import 'package:supra_mobile_ui/models/location.dart';
import 'package:supra_mobile_ui/models/prediction.dart';
import 'package:supra_mobile_ui/models/route.dart';
import 'package:supra_mobile_ui/theme/app_theme.dart';
import 'package:supra_mobile_ui/widgets/supra_map.dart';

/// Full-screen route map with rain/traffic overlays (UML: "Display Map with
/// Rain/Traffic Highlights").
class MapScreen extends StatefulWidget {
  final LatLng start;
  final LatLng destination;
  final Route? route;
  final List<Prediction> predictions;

  const MapScreen({
    super.key,
    required this.start,
    required this.destination,
    this.route,
    this.predictions = const [],
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _showTraffic = true;
  bool _showRain = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route map'),
        actions: [
          IconButton(
            icon: Icon(_showTraffic ? Icons.traffic : Icons.traffic_outlined),
            onPressed: () => setState(() => _showTraffic = !_showTraffic),
            tooltip: 'Traffic overlay',
          ),
          IconButton(
            icon: Icon(_showRain ? Icons.wb_cloudy : Icons.wb_cloudy_outlined),
            onPressed: () => setState(() => _showRain = !_showRain),
            tooltip: 'Rain overlay',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SupraMap(
              start: widget.start,
              destination: widget.destination,
              route: widget.route,
              predictions: widget.predictions,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.directions,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kemang → Sudirman CBD · 12.4 km · ~28 min',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Directions'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _toggleChip('Traffic', Icons.traffic, _showTraffic),
                    const SizedBox(width: 10),
                    _toggleChip('Rain', Icons.wb_cloudy, _showRain),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, IconData icon, bool active) => FilterChip(
    avatar: Icon(icon, size: 16, color: active ? SupraTheme.brand : null),
    label: Text(label),
    selected: active,
    onSelected: (v) {
      if (label == 'Traffic') setState(() => _showTraffic = v);
      if (label == 'Rain') setState(() => _showRain = v);
    },
  );
}
