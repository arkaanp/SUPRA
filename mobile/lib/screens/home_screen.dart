import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/current_conditions.dart';
import '../models/location.dart';
import '../models/saved_trip.dart';
import '../models/trip.dart';
import '../services/conditions_repository.dart';
import '../services/display_preferences.dart';
import '../services/supra_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_location_map.dart';

/// Hourly forecast data point for the 12-hour combined local forecast.
class HourlyForecast {
  final String time;
  final IconData weatherIcon;
  final Color weatherColor;
  final String weatherCondition;
  final int? temperatureC;
  final int? aqi;
  final String status;
  final String aqiCategory;
  final Color aqiBgColor;
  final Color aqiTextColor;

  const HourlyForecast({
    required this.time,
    required this.weatherIcon,
    required this.weatherColor,
    required this.weatherCondition,
    required this.temperatureC,
    required this.aqi,
    required this.aqiCategory,
    required this.aqiBgColor,
    required this.aqiTextColor,
    this.status = 'ML pending',
  });
}

/// Home screen dashboard implementing the GUI specifications from Part 3.6 of the
/// SWE Project Report:
/// 1. Top Header: Logo + SUPRA wordmark graphic, interactive location selector with 'v' arrow, and notification bell.
/// 2. Today's Air Quality Card: Curved-corner card with AQI number, category badge, source, health advisory,
///    interactive (?) explainability guides for air quality & rain, and 3 horizontal metrics (Rain, Traffic, Wind).
/// 3. Next 12 Hours Forecast: Combined local forecast with 12-hour horizontal prediction boxes (Time, Weather Symbol, Temperature, AQI).
/// 4. Recent Trips: Displays saved routes with direct tap-to-inspect in the Trip planner.
class HomeScreen extends StatefulWidget {
  final void Function(Trip? trip)? onNavigateToTrip;
  final VoidCallback? onNavigateToAlerts;
  final ConditionsRepository? conditions;

  const HomeScreen({
    super.key,
    this.onNavigateToTrip,
    this.onNavigateToAlerts,
    this.conditions,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Default to Kuningan, Jakarta as showcased in the Figma design specification.
  String _selectedLocationName = 'Kuningan, Jakarta';
  LatLng _selectedLocation = const LatLng(
    latitude: -6.2297,
    longitude: 106.8295,
  );
  String? _selectedAdm4 = '31.74.02.1001';

  bool _loading = false;
  CurrentConditions? _liveConditions;
  int _requestGeneration = 0;
  Timer? _freshnessTimer;
  final ScrollController _hourlyScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    DisplayPreferences.instance.addListener(_onDisplayPreferenceChanged);
    DisplayPreferences.instance.load();
    _refreshAll();
    _freshnessTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    TripHistoryStore.instance.addListener(_onTripHistoryStoreChanged);
  }

  void _onDisplayPreferenceChanged() {
    if (mounted) setState(() {});
  }

  bool get _showMl => DisplayPreferences.instance.showMlPredictions;

  void _onTripHistoryStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DisplayPreferences.instance.removeListener(_onDisplayPreferenceChanged);
    TripHistoryStore.instance.removeListener(_onTripHistoryStoreChanged);
    _hourlyScrollController.dispose();
    _freshnessTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    final generation = ++_requestGeneration;
    final point = _selectedLocation;
    setState(() => _loading = true);
    try {
      final conditions =
          await (widget.conditions ?? ConditionsRepository.instance).at(
            point,
            adm4: _selectedAdm4,
            refresh: true,
          );
      if (mounted && generation == _requestGeneration) {
        setState(() => _liveConditions = conditions);
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  String _wib(DateTime value) =>
      '${value.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 16).replaceAll('T', ' ')} WIB';

  /// Returns AQI styling and category details.
  (String category, Color badgeBg, Color badgeText, String advisory)
  _getAqiMeta(int aqi) {
    if (aqi <= 50) {
      return (
        'Good',
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
        'Air quality is satisfactory and poses little or no risk to health.',
      );
    } else if (aqi <= 100) {
      return (
        'Moderate',
        const Color(0xFFFEF08A),
        const Color(0xFF713F12),
        'Air is acceptable. Sensitive groups should limit prolonged outdoor activity.',
      );
    } else if (aqi <= 150) {
      return (
        'Unhealthy for Sensitive Groups',
        const Color(0xFFFFEDD5),
        const Color(0xFFC2410C),
        'Sensitive groups may experience health effects. General public not likely affected.',
      );
    } else if (aqi <= 200) {
      return (
        'Unhealthy',
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
        'Everyone may begin to experience health effects. Wear a mask and limit outdoor exertion.',
      );
    } else if (aqi <= 300) {
      return (
        'Very Unhealthy',
        const Color(0xFFF3E8FF),
        const Color(0xFF6B21A8),
        'Health alert: risk of health effects increased for everyone. Avoid prolonged outdoor exertion.',
      );
    } else {
      return (
        'Hazardous',
        const Color(0xFFFFE4E6),
        const Color(0xFF881337),
        'Health warning of emergency conditions: everyone is more likely to be affected.',
      );
    }
  }

  /// Retain the original forecast strip for future ML output. Only the Now slot
  /// may contain an observed/modelled temperature; future slots are not fabricated.
  List<HourlyForecast> _generateHourlyForecasts(
    int? currentAqi,
    int count, {
    bool showMl = false,
  }) {
    final now = DateTime.now();
    final forecasts = <HourlyForecast>[];

    for (int i = 0; i < count; i++) {
      final hourTime = now.add(Duration(hours: i));
      final hourNum = hourTime.hour;
      final timeStr = i == 0
          ? 'Now'
          : '${hourNum % 12 == 0 ? 12 : hourNum % 12} ${hourNum >= 12 ? 'PM' : 'AM'}';

      final current = i == 0;
      final weather = _liveConditions?.agedAt(now).weather;
      final description = weather?.data?['description'] as String?;
      final code = weather?.number('weather_code')?.toInt();
      final (weatherText, weatherIcon) = switch (code ?? -1) {
        0 => ('Clear', Icons.wb_sunny_rounded),
        1 || 2 => ('Partly cloudy', Icons.cloud_queue_rounded),
        3 => ('Cloudy', Icons.cloud_rounded),
        45 || 48 => ('Fog', Icons.foggy),
        >= 51 && <= 57 => ('Drizzle', Icons.grain),
        >= 61 && <= 67 || >= 80 && <= 82 => ('Rain', Icons.umbrella_rounded),
        >= 71 && <= 77 || 85 || 86 => ('Snow', Icons.ac_unit),
        >= 95 && <= 99 => ('Thunderstorm', Icons.thunderstorm),
        _ => (description ?? 'Weather —', Icons.help_outline),
      };
      final temp = current && weather?.kind != 'provider_forecast'
          ? weather?.number('temperature_c')?.round()
          : null;

      forecasts.add(
        HourlyForecast(
          time: timeStr,
          weatherIcon: current && weather?.kind != 'provider_forecast'
              ? weatherIcon
              : Icons.hourglass_empty_rounded,
          weatherColor: const Color(0xFF64748B),
          weatherCondition: current && weather?.kind != 'provider_forecast'
              ? weatherText
              : 'Weather —',
          temperatureC: temp,
          aqi: current ? currentAqi : null,
          aqiCategory: 'No prediction',
          aqiBgColor: const Color(0xFFF1F5F9),
          aqiTextColor: const Color(0xFF64748B),
          status: current
              ? (temp == null
                    ? 'No data'
                    : weather?.isStale == true
                    ? 'Stale'
                    : 'Latest')
              : showMl
              ? 'ML unavailable'
              : 'ML pending',
        ),
      );
    }

    return forecasts;
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: SupraTheme.brand),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Change Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: SupraTheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Select a key Greater Jakarta destination or pick custom coordinates on the interactive map.',
                  style: TextStyle(
                    color: SupraTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final picked = await showLocationPickerSheet(
                      context: context,
                      initialLocation: _selectedLocation,
                      title: 'Select location in Greater Jakarta',
                    );
                    if (picked != null && mounted) {
                      final nearest = findNearestLandmark(picked);
                      setState(() {
                        _selectedLocation = picked;
                        _selectedLocationName =
                            nearest?.name ??
                            'Lat: ${picked.latitude.toStringAsFixed(3)}, Lon: ${picked.longitude.toStringAsFixed(3)}';
                        _selectedAdm4 = null;
                        _liveConditions = null;
                      });
                      _refreshAll();
                    }
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Pick on Interactive Map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SupraTheme.brand,
                    side: const BorderSide(color: SupraTheme.brand),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Popular Jabodetabek Locations',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: SupraTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: 8,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final presets = [
                        const NamedLocation(
                          name: 'Kuningan, Jakarta',
                          area: 'South Jakarta',
                          point: LatLng(latitude: -6.2297, longitude: 106.8295),
                          adm4: '31.74.02.1001',
                        ),
                        const NamedLocation(
                          name: 'Monas (Central Jakarta)',
                          area: 'Central Jakarta',
                          point: LatLng(latitude: -6.1754, longitude: 106.8272),
                          adm4: '31.71.01.1001',
                        ),
                        const NamedLocation(
                          name: 'Bundaran HI',
                          area: 'Central Jakarta',
                          point: LatLng(latitude: -6.1950, longitude: 106.8230),
                          adm4: '31.71.03.1001',
                        ),
                        const NamedLocation(
                          name: 'Sudirman CBD (SCBD)',
                          area: 'South Jakarta',
                          point: LatLng(latitude: -6.2250, longitude: 106.8080),
                          adm4: '31.74.02.1002',
                        ),
                        const NamedLocation(
                          name: 'Gelora Bung Karno (GBK)',
                          area: 'Central Jakarta',
                          point: LatLng(latitude: -6.2185, longitude: 106.8025),
                        ),
                        const NamedLocation(
                          name: 'Kota Bogor',
                          area: 'Bogor',
                          point: LatLng(latitude: -6.5950, longitude: 106.7950),
                          adm4: '32.71.01.1001',
                        ),
                        const NamedLocation(
                          name: 'Universitas Indonesia (Depok)',
                          area: 'Depok',
                          point: LatLng(latitude: -6.3650, longitude: 106.8280),
                        ),
                        const NamedLocation(
                          name: 'BSD City',
                          area: 'South Tangerang',
                          point: LatLng(latitude: -6.3020, longitude: 106.6520),
                        ),
                      ];
                      final item = presets[index];
                      final isSelected = item.name == _selectedLocationName;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.location_city_outlined,
                          color: isSelected
                              ? SupraTheme.brand
                              : SupraTheme.textSecondary,
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? SupraTheme.brand
                                : SupraTheme.onSurface,
                          ),
                        ),
                        subtitle: Text(item.area),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedLocationName = item.name;
                            _selectedLocation = item.point;
                            _selectedAdm4 = item.adm4;
                            _liveConditions = null;
                          });
                          _refreshAll();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Explains what the Air Quality Index (AQI) and PM2.5 values mean.
  void _showAirQualityExplanation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bands = [
          (
            '0 - 50',
            'Good',
            const Color(0xFF22C55E),
            const Color(0xFFDCFCE7),
            'Air quality is satisfactory. Safe for all outdoor activities and open ventilation.',
          ),
          (
            '51 - 100',
            'Moderate',
            const Color(0xFFCA8A04),
            const Color(0xFFFEF08A),
            'Air is acceptable. Sensitive individuals (asthma/allergies) should limit prolonged outdoor exertion.',
          ),
          (
            '101 - 150',
            'Unhealthy for Sensitive Groups',
            const Color(0xFFEA580C),
            const Color(0xFFFFEDD5),
            'Elderly, children, and people with lung disease at risk. Motorcyclists and cyclists should wear masks.',
          ),
          (
            '151 - 200',
            'Unhealthy',
            const Color(0xFFDC2626),
            const Color(0xFFFEE2E2),
            'Everyone may experience health effects. Wear N95 respirator masks outdoors; keep car windows closed with AC recirculation.',
          ),
          (
            '201 - 300',
            'Very Unhealthy',
            const Color(0xFF7C3AED),
            const Color(0xFFF3E8FF),
            'Health alert: serious risk for everyone. Avoid non-essential outdoor commuting.',
          ),
          (
            '301+',
            'Hazardous',
            const Color(0xFF881337),
            const Color(0xFFFFE4E6),
            'Emergency conditions: entire population is likely affected. Stay indoors.',
          ),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: SupraTheme.brand.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.air_rounded,
                          color: SupraTheme.brand,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Understanding Air Quality (AQI)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: SupraTheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The Air Quality Index (AQI) converts fine particulate matter (PM2.5) concentrations from environmental sensors into a simple 0 to 500 health scale. PM2.5 particles are small enough to penetrate deep into lungs and enter the bloodstream.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'AQI Severity Bands & Health Advisory',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: SupraTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final b in bands)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: b.$4,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              b.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: b.$3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.$2,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: b.$3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  b.$5,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: Color(0xFF475569),
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
        );
      },
    );
  }

  /// Explains what the rainfall accumulation (mm) and rain probability (%) mean.
  void _showRainExplanation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final rainLevels = [
          (
            '< 0.5 mm',
            'Drizzle / Dry',
            const Color(0xFF64748B),
            const Color(0xFFF1F5F9),
            'Negligible road accumulation. Safe for standard commuting without wet gear.',
          ),
          (
            '0.5 - 2.5 mm',
            'Light Rain',
            const Color(0xFF0284C7),
            const Color(0xFFE0F2FE),
            'Road paint markings, zebra crossings, and metal expansion joints become slippery. Motorcyclists should reduce cornering speed.',
          ),
          (
            '2.5 - 10 mm',
            'Moderate Rain',
            const Color(0xFF2563EB),
            const Color(0xFFDBEAFE),
            'Active water spray from tires, reduced braking distance. Equip waterproof raincoat gear and headlights.',
          ),
          (
            '> 10 mm',
            'Heavy Rain / Downpour',
            const Color(0xFF1D4ED8),
            const Color(0xFFBFDBFE),
            'High risk of hydroplaning, poor visibility, and water ponding / flash floods on Greater Jakarta arterial roads and underpasses.',
          ),
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.umbrella_rounded,
                          color: Color(0xFF3B82F6),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Understanding Rain & Commute Risk',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: SupraTheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Rain metrics show either active precipitation accumulation rate (in millimeters) or probability percentage (% chance of rain during the forecast hour).',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: SupraTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Rainfall Rates & Commuter Precautions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: SupraTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final r in rainLevels)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: r.$4,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              r.$1,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: r.$3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.$2,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: r.$3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r.$5,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: Color(0xFF475569),
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = SupraService.instance;
    final unreadCount = service.notifications.where((n) => !n.isRead).length;

    final snapshot = _liveConditions?.agedAt(DateTime.now());
    final air = snapshot?.airQuality;
    final weather = snapshot?.weather;
    final traffic = snapshot?.traffic;
    final pm25 = air?.number('pm25_ug_m3');
    // Only display a supplied, identified AQI; never convert an instantaneous PM sample.
    final currentAqi = air?.data?['aqi_standard'] == 'US EPA'
        ? air?.number('aqi')?.round()
        : null;
    final aqiMeta = currentAqi == null
        ? (
            pm25 == null ? 'No cached data' : 'PM2.5',
            const Color(0xFFF1F5F9),
            const Color(0xFF475569),
            pm25 == null
                ? 'No cached reading for this location yet. Pull to refresh.'
                : 'Nearby station PM2.5, not an AQI or an ML prediction.',
          )
        : _getAqiMeta(currentAqi);
    final rain = weather?.number('precipitation_mm');
    final rainValue = rain == null ? 'No data' : '${rain.toStringAsFixed(1)} mm';
    final weatherLabel = weather?.isStale == true
        ? 'Rain · STALE'
        : weather?.kind == 'provider_forecast'
        ? 'Rain forecast'
        : 'Rain';
    final speed = traffic?.number('speed_kmh');
    final trafficValue = speed == null
        ? 'No data'
        : '${speed.toStringAsFixed(0)} km/h';
    final temp = weather?.number('temperature_c');
    final tempValue = temp == null ? 'No data' : '${temp.toStringAsFixed(0)}°C';

    // Forecast items: always next 12 hours (13 items total: Now + 12 hours ahead)
    final forecastItems = _generateHourlyForecasts(
      currentAqi,
      13,
      showMl: _showMl,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          color: SupraTheme.brand,
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loading)
                const LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: SupraTheme.brand,
                ),
              if (_loading) const SizedBox(height: 8),

              // -------------------------------------------------------------
              // 1. TOP HEADER
              // -------------------------------------------------------------
              _buildTopHeader(unreadCount),

              const SizedBox(height: 20),

              // -------------------------------------------------------------
              // 2. TODAY'S AIR QUALITY CURVED CARD
              // -------------------------------------------------------------
              _buildTodaysAirQualityCard(
                value:
                    currentAqi?.toString() ?? pm25?.toStringAsFixed(1) ?? '—',
                category:
                    '${air?.isStale == true ? "STALE · " : ""}${aqiMeta.$1}',
                categoryBg: air?.isStale == true
                    ? const Color(0xFFFEF3C7)
                    : aqiMeta.$2,
                categoryText: aqiMeta.$3,
                advisory: air?.isStale == true
                    ? 'Last-known reading — not current. ${aqiMeta.$4}'
                    : aqiMeta.$4,
                sourceLabel:
                    '${currentAqi == null ? "PM2.5 µg/m³" : "US AQI"} · ${air?.source ?? "No source yet"}'
                    '${air?.validAt == null ? "" : "\nObserved ${_wib(air!.validAt!)}"}'
                    '${air?.receivedAt == null ? "" : "\nFetched ${_wib(air!.receivedAt!)}"}',
                weatherLabel: weatherLabel,
                rainValue: rainValue,
                trafficValue: trafficValue,
                tempValue: tempValue,
                trafficLabel: traffic?.isStale == true
                    ? 'Traffic · STALE'
                    : 'Traffic',
                tempLabel: weather?.isStale == true
                    ? 'Temp · STALE'
                    : weather?.kind == 'provider_forecast'
                    ? 'Temp forecast'
                    : 'Temp',
              ),

              const SizedBox(height: 28),

              // -------------------------------------------------------------
              // 3. NEXT 12 HOURS (COMBINED LOCAL FORECAST)
              // -------------------------------------------------------------
              _buildNextFewHoursSection(forecastItems),

              const SizedBox(height: 28),

              // -------------------------------------------------------------
              // 4. RECENT TRIPS SUMMARY (TAP TO SHOW IN TRIP PLANNER)
              // -------------------------------------------------------------
              _buildRecentTripsSection(service),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // SUB-BUILDERS
  // =========================================================================

  /// 1. Top Header: Leftmost Logo + SUPRA graphic, Location with 'v' arrow, Right Notification Bell.
  Widget _buildTopHeader(int unreadCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left Column: Logo + SUPRA wordmark on top, Location switcher with 'v' below
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Logo + App name graphic "SUPRA"
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App Logo Graphic (Teal rounded squircle with stylized route S-curve)
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: SupraTheme.brandDark,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: SupraTheme.brand.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(18, 18),
                        painter: _SupraLogoPainter(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // App Name Graphic SUPRA
                  const Text(
                    'SUPRA',
                    style: TextStyle(
                      fontFamily: 'sans-serif',
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.2,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Current Location + 'v' arrow (interactive selector)
              InkWell(
                onTap: _showLocationPicker,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _selectedLocationName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Column: Notification Bell with optional unread badge
        InkWell(
          onTap: () {
            if (widget.onNavigateToAlerts != null) {
              widget.onNavigateToAlerts!();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    unreadCount > 0
                        ? '$unreadCount unread active transit alerts'
                        : 'No unread alerts at this time.',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF0F172A),
                  size: 22,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 10,
                    right: 11,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF97316),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 2. TODAY'S AIR QUALITY Curved Card:
  /// - Top: TODAY'S AIR QUALITY + (?) help button explaining AQI and PM2.5
  /// - Number on the left
  /// - Right of number: top is category (e.g. Moderate), bottom is source (US AQI)
  /// - Below number: health description
  /// - Bottom divided into three horizontal metrics:
  ///   Left: Umbrella symbol, Weather, value, and (?) help button explaining Rain
  ///   Middle: Traffic symbol, Traffic, value
  ///   Right: Thermometer symbol, Temp, value
  Widget _buildTodaysAirQualityCard({
    required String value,
    required String category,
    required Color categoryBg,
    required Color categoryText,
    required String advisory,
    required String weatherLabel,
    required String rainValue,
    required String trafficValue,
    required String tempValue,
    required String sourceLabel,
    required String trafficLabel,
    required String tempLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F766E), // Deep Supra Teal
            Color(0xFF115E59), // Rich Emerald Shade
            Color(0xFF0D9488), // Bright Cyan Teal accent
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative Weather Glow Illustration in the top-right (Sun + Translucent Cloud)
          Positioned(
            top: 16,
            right: 20,
            child: SizedBox(
              width: 84,
              height: 64,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  // Warm golden sun disc
                  Positioned(
                    top: 4,
                    right: 8,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFBBF24)
                                .withValues(alpha: 0.5),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Overlapping cloud graphic
                  Positioned(
                    bottom: 8,
                    right: 0,
                    child: Icon(
                      Icons.cloud_rounded,
                      size: 46,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main Card Content
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: TODAY'S AIR QUALITY + (?) help icon button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "TODAY'S AIR QUALITY",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _showAirQualityExplanation,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.question_mark_rounded,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Row: Large AQI Number on the left + (Category badge & Source) on the right
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Big Number
                    Flexible(
                      flex: 3,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.0,
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Right side divided into two parts: top is category, bottom is source
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top: Category Pill Badge (e.g. Moderate)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: categoryBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: categoryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Bottom: Source
                          Text(
                            sourceLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Health advisory description below the number
                Text(
                  advisory,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),

                const SizedBox(height: 20),

                // Subtle horizontal line divider
                Divider(
                  color: Colors.white.withValues(alpha: 0.18),
                  height: 1,
                  thickness: 1,
                ),

                const SizedBox(height: 16),

                // Divided into three parts horizontally: Left (Umbrella), Middle (Traffic), Right (Wind)
                Row(
                  children: [
                    // LEFT: Umbrella symbol, Weather, value, and (?) help button
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.umbrella_rounded,
                        topLabel: weatherLabel,
                        bottomValue: rainValue,
                        onHelpTap: _showRainExplanation,
                      ),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),

                    // MIDDLE: Traffic symbol, Traffic, value
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.traffic_rounded,
                        topLabel: trafficLabel,
                        bottomValue: trafficValue,
                      ),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),

                    // RIGHT: Thermometer symbol, Temp, value (replaces wind)
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.thermostat_rounded,
                        topLabel: tempLabel,
                        bottomValue: tempValue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper for the 3 horizontal metrics inside the Today's Air Quality card.
  Widget _buildMetricItem({
    required IconData icon,
    required String topLabel,
    required String bottomValue,
    VoidCallback? onHelpTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Frosted translucent icon container
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),

          // Right top is label (with optional (?) icon), right bottom is value
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          topLabel,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                    if (onHelpTap != null) ...[
                      const SizedBox(width: 3),
                      InkWell(
                        onTap: onHelpTap,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 0.9,
                            ),
                          ),
                          child: const Icon(
                            Icons.question_mark_rounded,
                            size: 8,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  bottomValue,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Next 12 Hours (Combined Local Forecast):
  /// - Left: "Next 12 Hours Forecast" on top, "Combined local weather, air quality & temperature predictions" below
  /// - Right: Chevron buttons to easily slide left/right across all 12 boxes
  /// - Horizontally scrolling boxes containing Time, Weather Symbol, Temperature, AQI for the full 12 hours
  Widget _buildNextFewHoursSection(List<HourlyForecast> forecastItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row with Left Title and Right Scroll Navigation Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next 12 Hours Forecast',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _showMl
                        ? 'ML predictions requested; values appear only when the model provides them'
                        : 'Live readings first; future ML predictions are optional',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Quick scroll controls to easily slide left/right across all 12 hours
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHourlyNavArrow(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Scroll left',
                  onTap: () {
                    final target = (_hourlyScrollController.offset - 192).clamp(
                      0.0,
                      _hourlyScrollController.hasClients
                          ? _hourlyScrollController.position.maxScrollExtent
                          : 1000.0,
                    );
                    _hourlyScrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
                const SizedBox(width: 6),
                _buildHourlyNavArrow(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Scroll right',
                  onTap: () {
                    final target = (_hourlyScrollController.offset + 192).clamp(
                      0.0,
                      _hourlyScrollController.hasClients
                          ? _hourlyScrollController.position.maxScrollExtent
                          : 1000.0,
                    );
                    _hourlyScrollController.animateTo(
                      target,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Explicit opt-in for future ML output. Off by default so live/stale
        // observations are never mistaken for model predictions.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_graph_rounded,
                size: 18,
                color: SupraTheme.brand,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Show ML predictions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SupraTheme.onSurface,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _showMl,
                activeThumbColor: SupraTheme.brand,
                onChanged: (value) =>
                    DisplayPreferences.instance.setShowMlPredictions(value),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: SizedBox(
            height: 178,
            child: ListView.separated(
              controller: _hourlyScrollController,
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: forecastItems.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = forecastItems[index];
                return Container(
                  width: 84,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: index == 0
                          ? SupraTheme.brand.withValues(alpha: 0.3)
                          : const Color(0xFFE2E8F0),
                      width: index == 0 ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. Time (Now, +1 hr, etc.)
                      Text(
                        item.time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: index == 0
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: index == 0
                              ? SupraTheme.brand
                              : const Color(0xFF64748B),
                        ),
                      ),

                      // 2. Weather shown by a symbol
                      Icon(
                        item.weatherIcon,
                        size: 26,
                        color: item.weatherColor,
                      ),

                      Text(
                        item.weatherCondition,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: SupraTheme.textSecondary,
                        ),
                      ),
                      // 3. Temperature
                      Text(
                        item.temperatureC == null
                            ? 'Temp —'
                            : '${item.temperatureC}°C',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),

                      Text(
                        item.aqi == null ? 'AQI —' : 'AQI ${item.aqi}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // State is separate from temperature, AQI and weather.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.aqiBgColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            item.status,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: item.aqiTextColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHourlyNavArrow({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF475569)),
        ),
      ),
    );
  }

  /// 4. Recent Trips Section:
  /// Synchronized with TripHistoryStore (same store used by TripScreen).
  /// Tapping any saved trip triggers navigation to TripScreen and shows the route.
  Widget _buildRecentTripsSection(SupraService service) {
    final recentTrips = TripHistoryStore.instance.getSortedTrips(
      TripHistorySort.recent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent trips',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            if (recentTrips.isNotEmpty)
              Text(
                '${recentTrips.length} saved',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (recentTrips.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SupraTheme.brand.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.bookmark_border_rounded,
                    color: SupraTheme.brand,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No saved trips yet',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Confirm a trip to add it to your history. ML forecasts will be added in the future.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: recentTrips.take(4).map((trip) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.route_outlined,
                      color: SupraTheme.brand,
                    ),
                    title: Text(
                      trip.displayTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${trip.start} → ${trip.destination} • ${trip.timeAgo}',
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: trip.frequency >= 4
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${trip.frequency}x',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: trip.frequency >= 4
                                  ? const Color(0xFFB45309)
                                  : SupraTheme.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    onTap: () {
                      if (widget.onNavigateToTrip != null) {
                        widget.onNavigateToTrip!(trip.toTrip());
                      }
                    },
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ===========================================================================
// PAINTERS
// ===========================================================================

/// Logo vector painter rendering the modern Supra route icon.
class _SupraLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Stylized S-curve connecting two network sensor nodes
    final path = Path();
    path.moveTo(size.width * 0.25, size.height * 0.28);
    path.cubicTo(
      size.width * 0.75,
      size.height * 0.25,
      size.width * 0.25,
      size.height * 0.75,
      size.width * 0.75,
      size.height * 0.72,
    );
    canvas.drawPath(path, paintLine);

    // Nodes
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.28),
      2.2,
      paintDot,
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.72),
      2.2,
      paintDot,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
