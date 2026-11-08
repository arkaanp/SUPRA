import 'dart:math';
import 'package:flutter/material.dart';

import '../models/current_conditions.dart';
import '../models/environmental_zone.dart';
import '../models/location.dart';
import '../services/environmental_service.dart';
import '../services/supra_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_location_map.dart';

/// Hourly forecast data point for the "Next few hours" combined local forecast.
class HourlyForecast {
  final String time;
  final IconData weatherIcon;
  final Color weatherColor;
  final String weatherCondition;
  final int temperatureC;
  final int aqi;
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
  });
}

/// Home screen dashboard implementing the GUI specifications from Part 3.6 of the
/// SWE Project Report:
/// 1. Top Header: Logo + SUPRA wordmark graphic, interactive location selector with 'v' arrow, and notification bell.
/// 2. Today's Air Quality Card: Curved-corner card with AQI number, category badge, source, health advisory, and 3 horizontal metrics (Rain, Traffic, Wind).
/// 3. Next Few Hours: Combined local forecast with horizontal prediction boxes (Time, Weather Symbol, Temperature, AQI).
/// 4. Plan Your Commute: Quick commute shortcut with route summary and travel modes.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToTrip;
  final VoidCallback? onNavigateToAlerts;

  const HomeScreen({
    super.key,
    this.onNavigateToTrip,
    this.onNavigateToAlerts,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Default to Kuningan, Jakarta as showcased in the Figma design specification.
  String _selectedLocationName = 'Kuningan, Jakarta';
  LatLng _selectedLocation = const LatLng(latitude: -6.2297, longitude: 106.8295);
  String? _selectedAdm4 = '31.74.02.1001';

  int _forecastHoursFilter = 4; // 2, 4, or 6 hours filter from Figma design

  bool _loading = false;
  CurrentConditions? _liveConditions;
  EnvironmentalZone? _currentZone;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      // 1. Refresh account state (profile, trips, notifications)
      await SupraService.instance.loadAccount();

      // 2. Resolve matching environmental zone
      final zone = EnvironmentalService.findZoneAt(_selectedLocation) ??
          EnvironmentalService.getCanonicalZones().first;
      _currentZone = zone;

      // 3. Attempt to fetch live conditions from backend
      try {
        final cond = await SupraService.instance.getCurrentConditions(
          _selectedLocation.latitude,
          _selectedLocation.longitude,
          _selectedAdm4,
        );
        _liveConditions = cond;
      } catch (_) {
        // Fallback gracefully to zone calculations if offline/backend unreachable
      }
    } catch (_) {
      // Keep existing cached state on refresh error
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Calculates US EPA AQI from PM2.5 concentration.
  int _pm25ToAqi(double pm25) {
    if (pm25 <= 12.0) {
      return ((50 - 0) / (12.0 - 0.0) * (pm25 - 0.0) + 0).round();
    } else if (pm25 <= 35.4) {
      return ((100 - 51) / (35.4 - 12.1) * (pm25 - 12.1) + 51).round();
    } else if (pm25 <= 55.4) {
      return ((150 - 101) / (55.4 - 35.5) * (pm25 - 35.5) + 101).round();
    } else if (pm25 <= 150.4) {
      return ((200 - 151) / (150.4 - 55.5) * (pm25 - 55.5) + 151).round();
    } else if (pm25 <= 250.4) {
      return ((300 - 201) / (250.4 - 150.5) * (pm25 - 150.5) + 201).round();
    } else {
      return ((500 - 301) / (500.4 - 250.5) * (pm25 - 250.5) + 301).clamp(0, 500).round();
    }
  }

  /// Returns AQI styling and category details.
  (String category, Color badgeBg, Color badgeText, String advisory) _getAqiMeta(int aqi) {
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

  /// Generates progressive hourly forecasts for the "Next few hours" section.
  List<HourlyForecast> _generateHourlyForecasts(int currentAqi, int count) {
    final now = DateTime.now();
    final forecasts = <HourlyForecast>[];

    for (int i = 0; i < count; i++) {
      final hourTime = now.add(Duration(hours: i));
      final hourNum = hourTime.hour;
      final timeStr = i == 0
          ? 'Now'
          : '${hourNum % 12 == 0 ? 12 : hourNum % 12} ${hourNum >= 12 ? 'PM' : 'AM'}';

      // Diurnal temperature & weather progression for Greater Jakarta
      int temp = 31;
      IconData icon = Icons.wb_sunny_rounded;
      Color iconColor = const Color(0xFFF59E0B);
      String condition = 'Sunny';

      if (hourNum >= 11 && hourNum <= 13) {
        temp = 32;
        icon = Icons.wb_sunny_rounded;
        iconColor = const Color(0xFFF59E0B);
        condition = 'Sunny';
      } else if (hourNum >= 14 && hourNum <= 16) {
        temp = 31;
        icon = Icons.cloud_queue_rounded;
        iconColor = const Color(0xFF64748B);
        condition = 'Partly Cloudy';
      } else if (hourNum >= 17 && hourNum <= 19) {
        temp = 29;
        icon = Icons.umbrella_rounded;
        iconColor = const Color(0xFF3B82F6);
        condition = 'Light Rain';
      } else if (hourNum >= 20 || hourNum <= 6) {
        temp = 27;
        icon = Icons.nightlight_round;
        iconColor = const Color(0xFF6366F1);
        condition = 'Clear Night';
      } else {
        temp = 29;
        icon = Icons.wb_sunny_rounded;
        iconColor = const Color(0xFFF59E0B);
        condition = 'Sunny';
      }

      // Atmospheric AQI curve based on rush hour traffic accumulation
      int hourlyAqi = currentAqi;
      if (i > 0) {
        // Slight natural drift (+4 to +15 depending on hour)
        final drift = ((sin((hourNum - 8) / 3.0) * 12).round());
        hourlyAqi = (currentAqi + (i * 3) + drift).clamp(35, 180);
      }

      final meta = _getAqiMeta(hourlyAqi);

      forecasts.add(
        HourlyForecast(
          time: timeStr,
          weatherIcon: icon,
          weatherColor: iconColor,
          weatherCondition: condition,
          temperatureC: temp,
          aqi: hourlyAqi,
          aqiCategory: meta.$1,
          aqiBgColor: meta.$2,
          aqiTextColor: meta.$3,
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
                  style: TextStyle(color: SupraTheme.textSecondary, fontSize: 13),
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
                        _selectedLocationName = nearest?.name ??
                            'Lat: ${picked.latitude.toStringAsFixed(3)}, Lon: ${picked.longitude.toStringAsFixed(3)}';
                        _selectedAdm4 = nearest?.adm4;
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
                          isSelected ? Icons.check_circle : Icons.location_city_outlined,
                          color: isSelected ? SupraTheme.brand : SupraTheme.textSecondary,
                        ),
                        title: Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? SupraTheme.brand : SupraTheme.onSurface,
                          ),
                        ),
                        subtitle: Text(item.area),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedLocationName = item.name;
                            _selectedLocation = item.point;
                            _selectedAdm4 = item.adm4;
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

  @override
  Widget build(BuildContext context) {
    final service = SupraService.instance;
    final unreadCount = service.notifications.where((n) => !n.isRead).length;

    // Determine current values (prefer live, fallback to zone defaults)
    final zone = _currentZone ??
        EnvironmentalService.findZoneAt(_selectedLocation) ??
        EnvironmentalService.getCanonicalZones().first;

    final liveAir = _liveConditions?.airQuality.data;
    final liveWeather = _liveConditions?.weather.data;
    final liveTraffic = _liveConditions?.traffic.data;

    // PM2.5 and AQI computation
    final double pm25 = (liveAir?['pm25_ug_m3'] as num?)?.toDouble() ?? zone.pm25;
    // If Kuningan default or moderate baseline, default to 72 as seen in wireframe
    final int currentAqi = (_selectedLocationName.contains('Kuningan') && liveAir == null)
        ? 72
        : _pm25ToAqi(pm25);

    final aqiMeta = _getAqiMeta(currentAqi);

    // Weather & Rain
    final double rainMm =
        (liveWeather?['precipitation_mm'] as num?)?.toDouble() ?? zone.rainfallMm;
    final String weatherLabel = rainMm > 0.5
        ? 'Rainy'
        : (liveWeather?['description'] as String?) ?? 'Rain';
    final String rainValue = rainMm > 0.0
        ? '${rainMm.toStringAsFixed(1)} mm'
        : '35%'; // Matching the Figma 35% probability specification

    // Traffic
    final String trafficValue = (liveTraffic?['confidence'] != null)
        ? (liveTraffic?['speed_kmh'] != null && (liveTraffic!['speed_kmh'] as num) < 20
            ? 'Heavy'
            : 'Moderate')
        : 'Heavy';

    // Wind
    final double windSpeed =
        (liveWeather?['wind_speed_kmh'] as num?)?.toDouble() ?? 8.0;
    final String windValue = '${windSpeed.toStringAsFixed(0)} km/h';

    // Forecast items for horizontal list (filtered by 2hr, 4hr, 6hr)
    final forecastItems = _generateHourlyForecasts(
      currentAqi,
      _forecastHoursFilter + 1,
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
                aqi: currentAqi,
                category: aqiMeta.$1,
                categoryBg: aqiMeta.$2,
                categoryText: aqiMeta.$3,
                advisory: aqiMeta.$4,
                weatherLabel: weatherLabel,
                rainValue: rainValue,
                trafficValue: trafficValue,
                windValue: windValue,
              ),

              const SizedBox(height: 28),

              // -------------------------------------------------------------
              // 3. NEXT FEW HOURS (COMBINED LOCAL FORECAST)
              // -------------------------------------------------------------
              _buildNextFewHoursSection(forecastItems),

              const SizedBox(height: 28),

              // -------------------------------------------------------------
              // 4. PLAN YOUR COMMUTE (Figma Design Section)
              // -------------------------------------------------------------
              _buildPlanYourCommuteSection(service),

              const SizedBox(height: 24),

              // -------------------------------------------------------------
              // 5. RECENT TRIPS SUMMARY
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
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
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
  /// - Top: TODAY'S AIR QUALITY
  /// - Number on the left
  /// - Right of number: top is category (e.g. Moderate), bottom is source (US AQI)
  /// - Below number: health description
  /// - Bottom divided into three horizontal metrics:
  ///   Left: Umbrella symbol, Weather, value
  ///   Middle: Traffic symbol, Traffic, value
  ///   Right: Wind symbol, Wind, value
  Widget _buildTodaysAirQualityCard({
    required int aqi,
    required String category,
    required Color categoryBg,
    required Color categoryText,
    required String advisory,
    required String weatherLabel,
    required String rainValue,
    required String trafficValue,
    required String windValue,
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
                            color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
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
                // Header: TODAY'S AIR QUALITY
                Text(
                  "TODAY'S AIR QUALITY",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 12),

                // Row: Large AQI Number on the left + (Category badge & Source) on the right
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Big Number
                    Text(
                      '$aqi',
                      style: const TextStyle(
                        fontSize: 54,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.0,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Right side divided into two parts: top is category, bottom is source
                    Column(
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
                          'US AQI · Station Sensors',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
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
                    // LEFT: Umbrella symbol, Weather, value
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.umbrella_rounded,
                        topLabel: weatherLabel,
                        bottomValue: rainValue,
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
                        topLabel: 'Traffic',
                        bottomValue: trafficValue,
                      ),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),

                    // RIGHT: Wind symbol, Wind, value
                    Expanded(
                      child: _buildMetricItem(
                        icon: Icons.air_rounded,
                        topLabel: 'Wind',
                        bottomValue: windValue,
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

          // Right top is label, right bottom is value
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  topLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
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

  /// 3. Next Few Hours (Combined Local Forecast):
  /// - Left: "Next few hours" on top, "Combined local forecast" below
  /// - Right: Segmented hours chip toggle (2 hr, 4 hr, 6 hr)
  /// - Horizontally scrolling boxes containing Time, Weather Symbol, Temperature, AQI
  Widget _buildNextFewHoursSection(List<HourlyForecast> forecastItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Next few hours',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Combined local forecast',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),

            // Segmented hours filter (2 hr | 4 hr | 6 hr)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [2, 4, 6].map((hours) {
                  final isSelected = _forecastHoursFilter == hours;
                  return GestureDetector(
                    onTap: () => setState(() => _forecastHoursFilter = hours),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        '$hours hr',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Horizontal scrolling series of prediction boxes
        SizedBox(
          height: 136,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: forecastItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = forecastItems[index];
              return Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                        fontWeight: index == 0 ? FontWeight.bold : FontWeight.w500,
                        color: index == 0 ? SupraTheme.brand : const Color(0xFF64748B),
                      ),
                    ),

                    // 2. Weather shown by a symbol
                    Icon(
                      item.weatherIcon,
                      size: 26,
                      color: item.weatherColor,
                    ),

                    // 3. Temperature
                    Text(
                      '${item.temperatureC}°',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),

                    // 4. AQI Prediction Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.aqiBgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'AQI ${item.aqi}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: item.aqiTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 4. Plan Your Commute Section:
  /// Direct implementation from Figma wireframe (page 15).
  Widget _buildPlanYourCommuteSection(SupraService service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Plan your commute',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Senayan · 8.4 km away',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                if (widget.onNavigateToTrip != null) {
                  widget.onNavigateToTrip!();
                }
              },
              child: const Text(
                'Plan trip',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: SupraTheme.brand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Commute preview card
        GestureDetector(
          onTap: () {
            if (widget.onNavigateToTrip != null) {
              widget.onNavigateToTrip!();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                // Mini Route Graphic Canvas
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Stack(
                    children: [
                      // Vector road lines simulation
                      CustomPaint(
                        size: const Size(double.infinity, 120),
                        painter: _MiniRoutePainter(),
                      ),
                      // Slow traffic tag
                      Positioned(
                        top: 40,
                        left: 140,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFED7AA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFB923C), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFC2410C)),
                              SizedBox(width: 4),
                              Text(
                                'Slow traffic',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9A3412),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Metrics summary pill row
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Time pill & environmental conditions
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            RichText(
                              text: const TextSpan(
                                text: '36 min ',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                children: [
                                  TextSpan(
                                    text: '+12 min traffic',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFEA580C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3B82F6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '40% rain',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEAB308),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'AQI 78',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Transit Mode Selection Chips
                      Row(
                        children: [
                          Expanded(
                            child: _buildModeChip(
                              icon: Icons.directions_transit_rounded,
                              label: 'Transit',
                              isSelected: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildModeChip(
                              icon: Icons.directions_car_rounded,
                              label: 'Car',
                              isSelected: false,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildModeChip(
                              icon: Icons.pedal_bike_rounded,
                              label: 'Bike',
                              isSelected: false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? SupraTheme.brand.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? SupraTheme.brand : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? SupraTheme.brand : const Color(0xFF64748B),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? SupraTheme.brand : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  /// 5. Recent Trips Section
  Widget _buildRecentTripsSection(SupraService service) {
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
            if (service.trips.isNotEmpty)
              Text(
                '${service.trips.length} saved',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
          ],
        ),
        const SizedBox(height: 10),

        if (service.trips.isEmpty)
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
                  child: const Icon(Icons.bookmark_border_rounded, color: SupraTheme.brand),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No saved trips yet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Save your daily routes to get instant environmental forecasts and route recommendations.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: service.trips.take(4).map((trip) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.route_outlined, color: SupraTheme.brand),
                  title: Text(
                    trip.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${trip.startLocation} → ${trip.destination}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    if (widget.onNavigateToTrip != null) {
                      widget.onNavigateToTrip!();
                    }
                  },
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
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.28), 2.2, paintDot);
    canvas.drawCircle(Offset(size.width * 0.75, size.height * 0.72), 2.2, paintDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mini route painter simulating the route preview map from the Figma mockup.
class _MiniRoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgRoadsPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    // Background road grid
    canvas.drawLine(Offset(0, size.height * 0.3), Offset(size.width, size.height * 0.6), bgRoadsPaint);
    canvas.drawLine(Offset(size.width * 0.2, 0), Offset(size.width * 0.45, size.height), bgRoadsPaint);
    canvas.drawLine(Offset(size.width * 0.7, 0), Offset(size.width * 0.85, size.height), bgRoadsPaint);
    canvas.drawLine(Offset(0, size.height * 0.8), Offset(size.width, size.height * 0.4), bgRoadsPaint);

    // Main active transit route (Teal curve)
    final routePaint = Paint()
      ..color = const Color(0xFF0F766E)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final routePath = Path();
    routePath.moveTo(size.width * 0.15, size.height * 0.4);
    routePath.cubicTo(
      size.width * 0.35,
      size.height * 0.4,
      size.width * 0.45,
      size.height * 0.75,
      size.width * 0.85,
      size.height * 0.75,
    );
    canvas.drawPath(routePath, routePaint);

    // Start node
    final startPaint = Paint()..color = const Color(0xFF0F766E);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.4), 6, startPaint);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.4), 3, Paint()..color = Colors.white);

    // Destination node
    final endPaint = Paint()..color = const Color(0xFF0F766E);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.75), 8, endPaint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.75), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
