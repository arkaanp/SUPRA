import 'package:flutter/material.dart';

import '../models/route_option.dart';
import '../theme/app_theme.dart';

/// Google-Maps-style multi-modal route planner view displaying road-accurate route choices,
/// estimated travel times, environmental exposure, and protective health measures.
class RoutePlannerView extends StatelessWidget {
  final List<RouteOption> options;
  final RouteOption selectedOption;
  final ValueChanged<RouteOption> onOptionSelected;
  final VoidCallback? onConfirmRoute;

  const RoutePlannerView({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.onOptionSelected,
    this.onConfirmRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Google-Maps-style Mode Selector Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: options.map((opt) {
              final isSelected = opt.mode == selectedOption.mode;
              return Expanded(
                child: InkWell(
                  onTap: () => onOptionSelected(opt),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isSelected
                          ? const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              opt.mode.iconEmoji,
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (opt.isRecommended) ...[
                              const SizedBox(width: 4),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: SupraTheme.brand,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt.formattedDuration,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 12,
                            color: isSelected
                                ? SupraTheme.brand
                                : SupraTheme.textSecondary,
                          ),
                        ),
                        Text(
                          '${opt.distanceKm.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 10,
                            color: SupraTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        // 2. Active Mode Recommendation Banner
        if (selectedOption.isRecommended)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: SupraTheme.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: SupraTheme.brand.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: SupraTheme.brand, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    selectedOption.recommendationReason,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: SupraTheme.brandDark,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SupraTheme.divider),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: SupraTheme.textSecondary,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    selectedOption.recommendationReason,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 10),

        // 3. Environmental Conditions Ribbon
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildEnvChip(
              icon: Icons.air,
              color: _aqiColor(selectedOption.pm25UgM3),
              label:
                  'PM2.5: ${selectedOption.pm25UgM3.toStringAsFixed(0)} µg/m³ · ${selectedOption.aqiCategory}',
            ),
            _buildEnvChip(
              icon: selectedOption.rainfallMm > 0
                  ? Icons.water_drop
                  : Icons.wb_sunny_outlined,
              color: selectedOption.rainfallMm > 0
                  ? SupraTheme.rain
                  : SupraTheme.aqiGood,
              label: selectedOption.rainfallMm > 0
                  ? 'Rain: ${selectedOption.rainfallMm.toStringAsFixed(1)} mm (${(selectedOption.rainProbability * 100).round()}%)'
                  : 'Weather: Clear',
            ),
            _buildEnvChip(
              icon: Icons.traffic,
              color: _trafficColor(selectedOption.trafficDensity),
              label: selectedOption.trafficCategory,
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 4. Contextual Health Advisory & Protective Measures Card
        Card(
          elevation: 0,
          color:
              selectedOption.mode == TransportMode.motorcycle &&
                  selectedOption.pm25UgM3 >= 35.0
              ? const Color(0xFFFFFBEB)
              : const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color:
                  selectedOption.mode == TransportMode.motorcycle &&
                      selectedOption.pm25UgM3 >= 35.0
                  ? const Color(0xFFFDE68A)
                  : SupraTheme.divider,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selectedOption.mode == TransportMode.motorcycle
                          ? Icons.health_and_safety_outlined
                          : Icons.shield_outlined,
                      size: 18,
                      color:
                          selectedOption.mode == TransportMode.motorcycle &&
                              selectedOption.pm25UgM3 >= 35.0
                          ? const Color(0xFFB45309)
                          : SupraTheme.brand,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${selectedOption.mode.displayName} Health & Safety Advisory',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color:
                              selectedOption.mode == TransportMode.motorcycle &&
                                  selectedOption.pm25UgM3 >= 35.0
                              ? const Color(0xFF92400E)
                              : SupraTheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Identified Environmental & Traffic Risks
                if (selectedOption.identifiedRisks.isNotEmpty) ...[
                  const Text(
                    'Identified Risks:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final risk in selectedOption.identifiedRisks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(
                              color: Color(0xFF991B1B),
                              fontSize: 11,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              risk,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                ],

                // Required / Recommended Protective Measures
                const Text(
                  'Recommended Protective Measures:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: SupraTheme.brandDark,
                  ),
                ),
                const SizedBox(height: 4),
                for (final measure in selectedOption.protectiveMeasures)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: SupraTheme.brand,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            measure,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: SupraTheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 5. Road Steps Corridor (OSRM Road Names)
        if (selectedOption.turnSteps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                dense: true,
                tilePadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.alt_route,
                  size: 18,
                  color: SupraTheme.textSecondary,
                ),
                title: Text(
                  'Road Corridor (${selectedOption.turnSteps.length} thoroughfares)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SupraTheme.onSurface,
                  ),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          int i = 0;
                          i < selectedOption.turnSteps.length;
                          i++
                        )
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Text(
                                  '${i + 1}. ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: SupraTheme.textSecondary,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    selectedOption.turnSteps[i],
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
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
          ),
        ],

        if (onConfirmRoute != null) ...[
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.navigation, size: 18),
            label: Text('Select ${selectedOption.mode.displayName} Route'),
            onPressed: onConfirmRoute,
          ),
        ],
      ],
    );
  }

  Widget _buildEnvChip({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _aqiColor(double pm25) {
    if (pm25 <= 12.0) return SupraTheme.aqiGood;
    if (pm25 <= 35.4) return SupraTheme.aqiModerate;
    if (pm25 <= 55.4) return SupraTheme.aqiUsg;
    return SupraTheme.aqiUnhealthy;
  }

  Color _trafficColor(double density) {
    if (density < 0.35) return SupraTheme.trafficFree;
    if (density < 0.65) return SupraTheme.trafficModerate;
    return SupraTheme.trafficHeavy;
  }
}
